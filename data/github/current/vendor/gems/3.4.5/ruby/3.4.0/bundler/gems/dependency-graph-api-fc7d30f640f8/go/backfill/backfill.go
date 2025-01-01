// The backfill command takes a list of repositories and a manifest name to look
// for, finds any manifests in those repositories, and submits
// ManifestFileChange events to the Dependency Graph API. It is used when the
// Dependency Graph API adds support for a new language or manifest type to
// backfill data for already existing manifests that were previously
// unsupported. It must be given the name of an ecosystem to backfill. By
// default it will backfill public repositories, but may optionally be given a
// CSV file with a list of repository IDs to backfill instead.  It will retrieve
// a list of files for each repository from Spokes, find files with names that
// match the given string, gather any extra repository metadata needed from the
// monolith-twirp FindRepositories API, and publish messages to Hydro that will
// be consumed by Dependency Graph API workers to add the manifests and their
// dependencies to the database.
//
// The various service connections are configured via environment variable,
// which in production will be set automatically from vault. The services and
// the expected environment variables are:
//
//   - Dependency graph api - used for checkpointing
//     Environment variables:
//     DEPENDENCY_GRAPH_API_URL
//
//   - Monolith-twirp (https://github.com/github/monolith-twirp, an API running within the primary github app, aka github/github, dotcom, the monolith)
//     The specific API being used is at https://github.com/github/github/blob/master/app/api/internal/twirp/repositories/v1/repositories_api_handler.rb
//     Environment variables:
//     MONOLITH_TWIRP_HMAC_KEY
//     MONOLITH_API_URL
//
//   - Spokes (https://github.com/github/spokes-api/)
//     This is the interface to stored repository data
//     Environment variables:
//     SPOKES_BASE_URI
//     SPOKES_CA_FILE
//     SPOKES_CLIENT_KEY
//     SPOKES_CLIENT_CERT
//
//   - Hydro (https://thehub.github.com/engineering/development-and-ops/hydro/)
//     An interface to Kafka
//     Environment variables:
//     HYDRO_BROKERS_SSL
//     HYDRO_CERT_PATH
//
//   - Trino (FKA Presto) (https://data.githubapp.com/) (https://trino.io)
//     A SQL interface to the warehouse.
//     Environment variables:
//     TRINO_URI - Must include a username component, but no password
//
// The hydro events can be monitored at
// https://hydro.githubapp.com/schemas/github-dependencygraph-v0-RepositoryManifestFileChange
// Note that messages are published to the v1 topic.
//
// Example invocation for public repos:
// root@shell-64bf4b7f74-gxz48:/src/app# ./backfill -v [-noop] -ecosystem go
//
// Invocation using a list of repositories:
// root@shell-64bf4b7f74-gxz48:/src/app# ./backfill -v -ecosystem go -repos repositories.csv
//
// Invocation using a regex instead of an ecosystem (requires some additional params):
// root@shell-64bf4b7f74-gxz48:/src/app# ./backfill -v -path-regex '.*yarn\.lock\z' -checkpoint-name one_off_yarn -repos repositories.csv
//
// Current as of 5/12/2022, this is a regex that captures all of DG-API's manifest types:
// ((\A|\/)(?:gemfile|gems\.rb)\z)|((\A|\/)(?:gemfile\.lock|gems\.locked)\z)|(\.gemspec\z)|((\A|\/)package\.json\z)|((\A|\/)package-lock\.json\z)|((\A|\/)yarn\.lock\z)|((\A|\/)pipfile\z)|((\A|\/)pipfile\.lock\z)|((\A|\/)setup\.py\z)|((\A|\/)pyproject\.toml\z)|((\A|\/)poetry\.lock\z)|((\A|\/)pom\.xml\z)|(\.nuspec\z)|((\A|\/)(.*)?\.csproj\z)|((\A|\/)(.*)?\.vbproj\z)|((\A|\/)(.*)?\.vcxproj\z)|((\A|\/)(.*)?\.fsproj\z)|((\A|\/)packages\.config\z)|((\A|\/)composer\.lock\z)|((\A|\/)composer\.json\z)|((\A|\/)go\.mod\z)|((\A|\/)go\.sum\z)|(\A\.github\/workflows\/[^\/]+\.ya?ml\z)|((?:\-|\.|\_|\A|\/)requirements[^\s]*\.txt\z)|((?:[^\s|\.]*)require(?:(?:\-|\_|\/)[^\s|\.]*)?\.txt\z)|((\A|\/)(.*)?node_modules(\z|\/))|((\A|\/)cargo\.lock\z)|((\A|\/)cargo\.toml\z)
//
// For shell access, see
// https://github.com/github/dependency-graph-api/blob/doc-backfill/README.md#shell-console.
//
// Currently supported ecosystems are 'go', 'actions', 'cargo', 'pub', 'swift'.
// For the actions ecosystem, all repositories will be backfilled.
// For the go ecosystem, public repositories are backfilled using the data
// warehouse(https://data.githubapp.com) querying the suez table representing
// file change events
// (https://data.githubapp.com/warehouse/hive/suez/file_change_metadata#!schema-tab).
// There is no way to do a similar search for private repositories so we had to
// run the backfill process on the full set of private repositories. If this
// process needs to be run again for the Go ecosystem it should be sufficient to
// get a list of repositories with manifests in that ecosystem from the
// dependency graph database. See
// https://github.com/github/dependency-graph-api/blob/doc-backfill/README.md#mysql-console
// for database access. For Go this would look like:
//
// select distinct github_repository_id from dg_repositories join dg_manifests on dg_repositories.id = dg_manifests.repository_id where dg_manifests.package_manager = 7;
//
// For Cargo and pub, we capture the list of repositories via the repositories_current table,
// using the "linguist id"* to find repos with Rust code and Dart code in them.
// * Technically, the ID being used in the query is a primary key id in the `hive.snapshots_presto.language_names` table,
// that maps to the true linguist id!
package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	_ "net/http/pprof"

	dg_proto "github.com/github/dependency-graph-api/gen/hydro/schemas/github/dependencygraph/v0"
	repositories "github.com/github/github-proto/gen/go/repositories/v1"
	twirpauth "github.com/github/go-twirp/client/auth"
	"github.com/github/go-twirp/client/requestid"
	"github.com/github/hydro-client-go/v4/pkg/hydro"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/trees"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/go-enry/go-enry/v2"
	"github.com/trinodb/trino-go-client/trino"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type match struct {
	id         uint64
	repository *repositories.RepositoryListItem
	manifest   []repositoryPath
	commit     *types.ObjectID
}

type repositoryPath struct {
	path string
	// This is passed as git_ref, but today is the blob_oid. This is likely a bug.
	blobOid string
}

type ecosystem struct {
	name       string
	isManifest func(string) bool
	trinoQuery string
}

type app struct {
	context context.Context

	// dependency graph api for checkpoints
	dependencyGraphURL string

	// monolith api
	repositoriesAPI repositories.RepositoriesAPI

	// spokes apis
	treesAPI   trees.TreesAPI
	objectsAPI objects.ObjectsAPI

	hydroPublisher *hydro.Publisher

	// concurrency configuration
	maxSpokesWorkers int
	maxGithubWorkers int
	maxHydroWorkers  int
	sleep            time.Duration

	noOpMode bool
}

// This should match the limit defined in
// https://github.com/github/github/blob/master/app/models/repository/dependencies_dependency.rb
const maxManifestFiles = 150

var (
	ecosystemName    = flag.String("ecosystem", "", "The name of the ecosystem to backfill")
	pathRegex        = flag.String("path-regex", "", "The regex to apply to a path to determine if something is a manifest")
	checkpointName   = flag.String("checkpoint-name", "", "Custom checkpoint name, inferred if an ecosystem is provided")
	repoFile         = flag.String("repos", "", "Path to a list of repositories to process in CSV")
	verbose          = flag.Bool("v", false, "enable verbose logging")
	noOp             = flag.Bool("noop", false, "run backfill in no-op mode")
	maxSpokesWorkers = flag.Int("max-spokes-workers", 10, "maximum concurrent connections to spokes")
	maxGithubWorkers = flag.Int("max-github-workers", 2, "maximum concurrent connections to the github repositories api")
	maxHydroWorkers  = flag.Int("max-hydro-workers", 1, "maximum concurrent processes enqueuing to hydro")
	sleep            = flag.Duration("sleep", 100*time.Millisecond, "time to sleep between repositories enqueued")
	profile          = flag.Bool("profile", false, "enable profiling")

	actionsPattern = regexp.MustCompile(`\A\.github\/workflows\/[^\/]+\.ya?ml\z`)
	ecosystems     = map[string]ecosystem{
		"go": {
			name: "go",
			isManifest: func(pathname string) bool {
				basename := path.Base(pathname)
				return basename == "go.mod"
			},
			trinoQuery: "SELECT DISTINCT repository_id FROM hive.suez.file_change_metadata" +
				"WHERE filename = 'go.mod' AND is_vendored = FALSE AND change_type IN ('A', 'M')" +
				"ORDER BY repository_id ASC",
		},
		"actions": {
			name: "actions",
			isManifest: func(pathname string) bool {
				return actionsPattern.MatchString(pathname)
			},
			// Unlike in other ecosystems, this query includes both public and private repositories
			trinoQuery: "WITH repos AS (SELECT DISTINCT repository_id FROM hive.snapshots_presto.workflows WHERE present_in_default_branch = true)" +
				"SELECT id FROM hive.canonical.repositories_current JOIN repos ON (repository_id = id)" +
				"WHERE is_archived = false ORDER BY repository_id ASC",
		},
		"cargo": {
			name: "cargo",
			isManifest: func(pathname string) bool {
				basename := strings.ToLower(path.Base(pathname))
				return basename == "cargo.toml" || basename == "cargo.lock"
			},
			// All repositories that have Rust as a detected language via Linguist
			// NOTE! hive.snapshots_presto.language_names language codes are used in hive.canonical!
			trinoQuery: "SELECT DISTINCT id AS repository_id FROM hive.canonical.repositories_current " +
				"CROSS JOIN UNNEST(language_ids) AS t (lang_found_id) " +
				"WHERE (lang_found_id = 249 OR primary_language_id = 249) " +
				"AND is_archived = FALSE AND is_spammy_owner = FALSE " +
				"ORDER BY repository_id ASC",
		},
		"pub": {
			name: "pub",
			isManifest: func(pathname string) bool {
				basename := strings.ToLower(path.Base(pathname))
				return basename == "pubspec.yaml" || basename == "pubspec.yml" || basename == "pubspec.lock"
			},
			// All repositories that have Dart as a detected language via Linguist
			// NOTE! hive.snapshots_presto.language_names language codes are used in hive.canonical!
			trinoQuery: "SELECT DISTINCT id AS repository_id FROM hive.canonical.repositories_current " +
				"CROSS JOIN UNNEST(language_ids) AS t (lang_found_id) " +
				"WHERE (lang_found_id = 277 OR primary_language_id = 277) " +
				"AND is_archived = FALSE AND is_spammy_owner = FALSE " +
				"ORDER BY repository_id ASC",
		},
		"swift": {
			name: "swift",
			isManifest: func(pathname string) bool {
				basename := path.Base(pathname)
				return basename == "Package.resolved"
			},
			// All repositories that have Package.resolved manifests
			trinoQuery: "SELECT DISTINCT repository_id FROM hive.suez.metadata_current " +
				"WHERE filename = 'Package.resolved' AND is_vendored = FALSE " +
				"ORDER BY repository_id ASC",
		},
		"pnpm": {
			name: "pnpm",
			isManifest: func(pathname string) bool {
				basename := path.Base(pathname)
				return basename == "pnpm-lock.yaml"
			},
			// All repositories that have pnpm-lock.yaml manifests
			trinoQuery: "SELECT DISTINCT repository_id FROM hive.suez.metadata_current " +
				"WHERE filename = 'pnpm-lock.yaml' AND is_vendored = FALSE " +
				"ORDER BY repository_id ASC",
		},
	}
)

func main() {
	log.SetPrefix("backfill: ")
	flag.Parse()
	if *ecosystemName == "" && *pathRegex == "" {
		flag.Usage()
		log.Fatal("Either ecosystem or path-regex must be provided")
	}

	if *noOp {
		log.Println("Currently running in no-op mode...")
	}

	if *profile {
		go func() {
			log.Println(http.ListenAndServe("localhost:6060", nil))
		}()
	}
	eco, ok := ecosystems[*ecosystemName]
	if !ok && *ecosystemName != "" {
		var keys []string
		for key := range ecosystems {
			keys = append(keys, key)
		}
		log.Fatalf("unknown ecosystem \"%v\" - known ecosystems: %v", *ecosystemName, strings.Join(keys, ", "))
	}

	if *pathRegex != "" && *repoFile == "" {
		log.Fatalf("path-regex is currently only supported on CSV file input using the repoFile parameter, which is empty")
	}
	if *pathRegex != "" && *checkpointName == "" {
		log.Fatalf("checkpoint-name must be provided when using a path regex!")
	}

	var repositories []uint64
	var err error
	if *repoFile != "" {
		repositories, err = readRepositories(*repoFile)
		if err != nil {
			log.Fatalf("failed to read repositories list: %v", err)
		}
	} else {
		db, err := newTrinoConnection()
		if err != nil {
			log.Fatalf("failed to connect to trino: %v", err)
		}
		repositories, err = fetchRepositories(context.Background(), db, eco)
		if err != nil {
			log.Fatalf("failed to read repositories list: %v", err)
		}
	}

	log.Printf("Found %v repositories to backfill", len(repositories))
	config := newApp()

	var isManifestPredicate func(string) bool
	finalCheckpointName := *checkpointName
	if eco.name != "" {
		isManifestPredicate = eco.isManifest
		if finalCheckpointName == "" {
			finalCheckpointName = eco.name
		}
	} else {
		manifestPattern := regexp.MustCompile(*pathRegex)
		isManifestPredicate = manifestPattern.MatchString
	}

	backfill(config, isManifestPredicate, finalCheckpointName, repositories)
	log.Println("Successfully completed backfill.")
}

func readRepositories(file string) ([]uint64, error) {
	f, err := os.Open(file)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	reader := csv.NewReader(f)
	unparsed, err := reader.ReadAll()
	if err != nil {
		return nil, err
	}

	var repositories []uint64
	for _, str := range unparsed {
		repo, err := strconv.ParseUint(str[0], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("couldn't parse repo %q: %v", str, err)
		}
		repositories = append(repositories, repo)
	}
	return repositories, nil
}

func newTrinoConnection() (*sql.DB, error) {
	uri := getenv("TRINO_URI", "http://dependency-graph@presto-coordinator.service.github.net:8080")
	config := trino.Config{
		ServerURI: uri,
		Catalog:   "hive",
		Schema:    "default",
	}
	dsn, err := config.FormatDSN()
	if err != nil {
		return nil, err
	}

	return sql.Open("trino", dsn)
}

func fetchRepositories(ctx context.Context, db *sql.DB, eco ecosystem) ([]uint64, error) {
	var repositories []uint64
	rows, err := db.QueryContext(ctx, eco.trinoQuery)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var id uint64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		repositories = append(repositories, id)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return repositories, nil
}

// backfill runs the main backfill loop for all repositories given
func backfill(config *app, isManifestPredicate func(string) bool, checkpointName string, repositories []uint64) {
	// We need to query github/github twirp API to find details on repositories
	// before submitting events. These queries can be batched, but since we
	// don't always know in advance which repositories have matching manifests
	// (ie when backfilling private repos) we want to accumulate matching
	// repositories and then query github/github whenever we have one batch of
	// results.

	startpoint, err := loadCheckpoint(config, checkpointName)
	if err != nil {
		log.Fatalf("failed to load checkpoint: %v", err)
	}

	matchChan := make(chan match)

	go func() {
		// RPC limiting counting semaphore
		spokesSema := make(chan struct{}, config.maxSpokesWorkers)
		var spokesWg sync.WaitGroup
		for _, repo := range repositories {
			if repo < startpoint {
				continue
			}

			// acquire token
			spokesSema <- struct{}{}
			spokesWg.Add(1)

			go func(repo uint64) {
				defer func() {
					spokesWg.Done()
					<-spokesSema
				}()
				if *verbose {
					log.Printf("Querying spokes for trees for %d", repo)
				}
				commit, err := resolveHead(config, repo)
				if err != nil {
					log.Printf("Failed to resolve HEAD for repository %d: %v", repo, err)
					return
				}
				treeEntries, err := listTree(config, repo, commit)
				if err != nil {
					log.Printf("Failed repository %d querying spokes for tree: %v", repo, err)
					return
				}
				matches := selectManifests(treeEntries, isManifestPredicate)
				if len(matches) > 0 {
					if *verbose {
						log.Printf("Found %d matching manifests for repository %d", len(matches), repo)
					}
					matchChan <- match{id: repo, manifest: matches, commit: commit}
				}
			}(repo)
		}
		spokesWg.Wait()
		close(matchChan)
	}()

	// Batch up repos into groups of 100 (the maximum for this API) and query
	// the monolith-twirp API to fill in repo data
	const batchSize = 100

	filledMatchChan := make(chan match)
	go func() {
		var repoBatch []match
		reposSema := make(chan struct{}, config.maxGithubWorkers)
		var reposWg sync.WaitGroup
		for m := range matchChan {
			repoBatch = append(repoBatch, m)
			if len(repoBatch) == batchSize {
				reposSema <- struct{}{}
				reposWg.Add(1)
				go func(batch []match) {
					defer func() {
						reposWg.Done()
						<-reposSema
					}()
					fillBatch(config, batch, filledMatchChan)
				}(repoBatch)
				repoBatch = nil
			}
		}
		if len(repoBatch) > 0 {
			fillBatch(config, repoBatch, filledMatchChan)
		}
		reposWg.Wait()
		close(filledMatchChan)
	}()

	// Checkpointing goroutine with a ticker so we aren't updating too frequently
	finishedIds := make(chan uint64)
	ticker := time.NewTicker(1 * time.Second)
	go func() {
		var latest uint64
		for {
			select {
			case latest = <-finishedIds:
			case <-ticker.C:
				err := saveCheckpoint(config, checkpointName, latest)
				if err != nil {
					log.Fatalf("failed to save checkpoint: %v", err)
				}
			}
		}
	}()

	// Take the filled in repository data and on each repo for each manifest emit a ManifestFileChanged event
	hydroSema := make(chan struct{}, config.maxHydroWorkers)
	var hydroWg sync.WaitGroup
	for m := range filledMatchChan {
		hydroSema <- struct{}{}
		hydroWg.Add(1)
		go func(m match) {
			defer func() {
				hydroWg.Done()
				<-hydroSema
			}()
			createManifestChanges(config, m)
			finishedIds <- m.id

			time.Sleep(config.sleep)
		}(m)
	}
	hydroWg.Wait()
}

// fillBatch queries the monolith-twirp FindRepositories API to fill in
// repository data on a match struct
func fillBatch(config *app, repoBatch []match, filledMatchChan chan match) {
	err := fillRepositories(config, repoBatch)
	if err != nil {
		log.Printf("Failed to fill repositories: %v", err)
		return
	}
	for _, m := range repoBatch {
		filledMatchChan <- m
	}
}

func createManifestChanges(config *app, repo match) {
	for _, manifest := range repo.manifest {
		message := newMessage(repo.repository, repo.commit, manifest)

		if config.noOpMode {
			log.Printf("noop message: %+v", message)
			continue
		}

		if err := publishManifestFileChange(config, message); err != nil {
			log.Printf("Failed repository %d: %v", repo.id, err)
			continue
		}
	}
}

// publishManifestChange publishes an event to Hydro for a manifest change. It
// will fetch the contents of the manifest, encrypt those contents, and submit a
// RepositoryManifestFileChange event.
func publishManifestFileChange(config *app, message *dg_proto.RepositoryManifestFileChange) error {
	// There are two topics for this message type and the default one (v0) is incorrect so we have to specify
	puberr := config.hydroPublisher.Publish(message, hydro.WithTopic("github.dependencygraph.v1.RepositoryManifestFileChange"))
	if puberr != nil {
		return fmt.Errorf("publishing to hydro for %s/%s", message.ManifestFile.Path, message.ManifestFile)
	}
	log.Printf("Published RepositoryManifestFileChange for %s", message.RepositoryNwo)
	return nil
}

// fillRepositories fills in a batch of match structs that only contain
// repository ids by querying the github/github twirp API for repository details
func fillRepositories(config *app, matches []match) error {
	ids := make([]int64, len(matches))
	for i, m := range matches {
		ids[i] = int64(m.id) // it seems like an error in the api that this is a signed int
	}

	if *verbose {
		log.Printf("filling repositories %v", ids)
	}
	result, err := config.repositoriesAPI.FindRepositories(config.context, &repositories.FindRepositoriesRequest{Ids: ids})
	if err != nil {
		return fmt.Errorf("FindRepositories %v: %v", ids, err)
	}

	// Build a map of repository Id to RepositoryListItem because we are not
	// guaranteed to receive results in order as far as I can tell
	repoResults := make(map[int64]*repositories.RepositoryListItem)
	for _, repo := range result.Repositories {
		repoResults[int64(repo.Id)] = repo
	}
	for i := range matches {
		matches[i].repository = repoResults[int64(matches[i].id)]
	}
	return nil
}

func listTree(config *app, repo uint64, commit *types.ObjectID) ([]*types.TreeEntry, error) {
	var entries []*types.TreeEntry
	request := trees.NewListTreesRequestWithTreeishSelector(
		types.NewRepository(repo),
		selectors.NewTreeishSelector(types.NewTreeishWithObjectID(commit)),
		true, // recursive
		nil,  // initial cursor
	)

	for {
		result, err := config.treesAPI.ListTrees(config.context, request)
		if err != nil {
			return nil, err
		}

		entries = append(entries, result.GetEntries()...)
		cursor := result.GetNextCursor()
		if cursor == nil {
			break
		}
		request.Cursor = cursor
	}
	return entries, nil
}

// resolveHead returns the ObjectID (commit sha) represented by HEAD in repo
func resolveHead(config *app, repo uint64) (*types.ObjectID, error) {
	request := objects.NewResolveObjectRequest(types.NewRepository(repo), types.NewRevision([]byte("HEAD")))
	result, err := config.objectsAPI.ResolveObject(config.context, request)
	if err != nil {
		return nil, fmt.Errorf("resolve HEAD in spokes: %w", err)
	}

	return result.Oid, nil
}

// selectManifests selects the paths that match baseName and are not considered
// vendored from a ListTreesResponse
func selectManifests(treeEntries []*types.TreeEntry, isManifestPredicate func(string) bool) []repositoryPath {
	var result []repositoryPath
	matches := 0
	for _, entry := range treeEntries {
		name := string(entry.GetPath().GetName())
		if isManifestPredicate(name) && !enry.IsVendor(name) {
			blobOid := entry.GetObject().Oid.GetId()
			result = append(result, repositoryPath{
				path:    name,
				blobOid: blobOid,
			})
			matches++
		}
		if matches == maxManifestFiles {
			break
		}
	}

	return result
}

func newMessage(repo *repositories.RepositoryListItem, commit *types.ObjectID, entry repositoryPath) *dg_proto.RepositoryManifestFileChange {
	manifestPath, manifestFileName := path.Split(entry.path)
	manifestPath = strings.TrimSuffix(manifestPath, "/")
	manifestFile := dg_proto.RepositoryManifestFileChange_ManifestFile{
		Filename: manifestFileName,
		Path:     manifestPath,
		GitRef:   commit.Id,
		BlobOid:  entry.blobOid,
		PushedAt: timestamppb.Now(),
	}

	return &dg_proto.RepositoryManifestFileChange{
		RepositoryId:      uint64(repo.GetId()),
		RepositoryPrivate: repo.Visibility == repositories.Visibility_VISIBILITY_PRIVATE,
		ManifestFile:      &manifestFile,
		RepositoryNwo:     strings.Join([]string{repo.OwnerLogin, repo.Name}, "/"),
		OwnerId:           uint64(repo.OwnerId),
		IsBackfill:        true,
	}
}

// newApp initializes the app config from environment variables. On
// dependency-graph-api production instances these are set automatically from
// vault. They can be accessed from a normal shell instance using `vault-secret
// --application dependency-graph-api` after authenticating to vault using
// `.vault login`
//
// Some default values are set here because they were not in vault yet at the
// time of writing.
func newApp() *app {
	context := context.Background()

	hmacKey := getenv("MONOLITH_TWIRP_HMAC_KEY", "dg-api-hmac")
	ghApiUrl := getenv("MONOLITH_API_URL", "https://internal-api.service.iad.github.net/internal")
	twirpClient, err := newTwirpClient(hmacKey)
	if err != nil {
		log.Fatalf("initializing twirp client: %v", err)
	}
	repositoriesAPI := repositories.NewRepositoriesAPIProtobufClient(ghApiUrl, twirpClient)

	publisher, err := buildHydroPublisher()
	if err != nil {
		log.Fatal(err)
	}
	hydroPublisher := publisher

	transport, err := httpTransport()
	if err != nil {
		log.Fatal(err)
	}

	dependencyGraphURL := getenv("DEPENDENCY_GRAPH_API_URL", "http://localhost:9596")

	spokesHttpClient := &http.Client{Transport: transport}
	spokesURL := getenv("SPOKES_BASE_URI", "http://localhost:12080")
	treesAPI := trees.NewTreesAPIProtobufClient(spokesURL, spokesHttpClient)
	objectsAPI := objects.NewObjectsAPIProtobufClient(spokesURL, spokesHttpClient)

	return &app{
		context:            context,
		dependencyGraphURL: dependencyGraphURL,
		repositoriesAPI:    repositoriesAPI,
		treesAPI:           treesAPI,
		objectsAPI:         objectsAPI,
		hydroPublisher:     hydroPublisher,
		maxSpokesWorkers:   *maxSpokesWorkers,
		maxGithubWorkers:   *maxGithubWorkers,
		maxHydroWorkers:    *maxHydroWorkers,
		sleep:              *sleep,
		noOpMode:           *noOp,
	}
}

func newTwirpClient(hmacKey string) (*twirpauth.RequestHMACSigner, error) {
	client := requestid.NewForwarder(http.DefaultClient)
	return twirpauth.NewRequestHMACSigner(hmacKey, client)
}

// httpTransport returns an http transport with TLS configuration based on
// environment variables that are set from Vault when running in production.
// When these are empty a default configuration is produced. Otherwise this sets
// the local certificate chain using the PEM-encoded keypair stored in
// SPOKES_CLIENT_KEY and SPOKES_CLIENT_CERT, and the RootCA field using
// SPOKES_CA_FILE (which, despite its name, is also PEM-encoded data). If any of
// these environment variables are set then they all must be set and any errors
// in parsing are treated as failures.
func httpTransport() (http.RoundTripper, error) {
	caFile := os.Getenv("SPOKES_CA_FILE")
	clientKey := os.Getenv("SPOKES_CLIENT_KEY")
	clientCert := os.Getenv("SPOKES_CLIENT_CERT")

	if caFile == "" && clientKey == "" && clientCert == "" {
		return http.DefaultTransport, nil
	}

	rootCAs := x509.NewCertPool()
	if ok := rootCAs.AppendCertsFromPEM([]byte(caFile)); !ok {
		// No useful error information is returned by AppendCertsFromPEM
		return nil, errors.New("Failed to parse PEM data in SPOKES_CA_FILE")
	}

	cert, err := tls.X509KeyPair([]byte(clientCert), []byte(clientKey))
	if err != nil {
		return nil, err
	}

	tlsConfig := tls.Config{
		Certificates: []tls.Certificate{cert},
		RootCAs:      rootCAs,
	}

	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.TLSClientConfig = &tlsConfig
	return transport, nil
}

func buildHydroPublisher() (*hydro.Publisher, error) {
	hydro.SetKafkaLogger(log.Default())

	brokers := strings.Split(os.Getenv("HYDRO_BROKERS_SSL"), " ")
	rootCA := os.Getenv("HYDRO_CERT_PATH")

	kafkaConfig, err := hydro.NewKafkaConfig(brokers,
		hydro.WithClientID("dependency-graph-api-production"),
		hydro.WithRootCA(rootCA),
	)
	if err != nil {
		return nil, err
	}

	// A sink is responsible for writing events to a destination.
	sink, err := hydro.NewKafkaSink(*kafkaConfig)
	if err != nil {
		return nil, err
	}

	return hydro.NewPublisher(sink)
}

func getenv(name, defaultValue string) string {
	value, present := os.LookupEnv(name)
	if present {
		return value
	}
	return defaultValue
}

// loadCheckpoint reads the last checkpoint from the DG API server.
func loadCheckpoint(config *app, checkpointName string) (uint64, error) {
	if config.noOpMode {
		return 0, nil
	}

	resp, err := http.Get(config.dependencyGraphURL + "/checkpoints/backfill_" + checkpointName)
	if err != nil {
		return 0, fmt.Errorf("checkpoint GET request failed: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("checkpoint request returned %s", resp.Status)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, fmt.Errorf("reading checkpoint response: %v", err)
	}
	var cp Checkpoint
	if err := json.Unmarshal(data, &cp); err != nil {
		return 0, fmt.Errorf("decoding checkpoint JSON: %v", err)
	}
	return cp.Value, nil
}

// saveCheckpoint saves the last checkpoint to the DG API server.
func saveCheckpoint(config *app, ecosystemName string, value uint64) error {
	if config.noOpMode {
		return nil
	}

	url := config.dependencyGraphURL + "/checkpoints/backfill_" + ecosystemName
	data, err := json.Marshal(Checkpoint{Value: value})
	if err != nil {
		return fmt.Errorf("marshaling Checkpoint JSON: %v", err)
	}
	req, err := http.NewRequest("PUT", url, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("PUT to %s returned %s", url, response.Status)
	}
	return nil
}

// A Checkpoint is the state recorded by the DG API server; see checkpoints_controller.rb.
type Checkpoint struct {
	Value uint64 `json:"value"` // checkpointed repository id
}
