package helpers

import (
	"bytes"
	"context"
	"crypto/sha1"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"math/rand"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/IBM/sarama"
	semantic "github.com/github/blackbird/clients/go/semantic/v1"
	"github.com/github/blackbird/crates/client/pkg/blackbird"
	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	clientauth "github.com/github/go-twirp/client/auth"
	hydroschemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	blackbirdpb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	ghclient "github.com/github/blackbird-mw/internal/github/client"

	"github.com/github/blackbird-mw/internal/copilot/copilotfakes"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/http"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
	"github.com/github/blackbird-mw/internal/models"
	admin "github.com/github/blackbird-mw/internal/proto/admin/v1"
	query "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/searchfakes"
	"github.com/github/blackbird-mw/internal/test/fakegithub"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

// Pick an arbitrary corpus.
func Corpus(t *testing.T) routing.Corpus {
	return routing.Corpora[rand.Intn(len(routing.Corpora))]
}

// Pick an arbitrary corpus that's available on Proxima.
func ProximaCorpus(t *testing.T) routing.Corpus {
	proximaCorpora := routing.ProximaStamps[0].EnabledCorpora()

	return proximaCorpora[rand.Intn(len(proximaCorpora))]
}

// Pick an arbitrary corpus that's not the given one.
func OtherCorpus(t *testing.T, corpus routing.Corpus) routing.Corpus {
	for _, c := range routing.Corpora {
		if c != corpus {
			return c
		}
	}

	panic("this shouldn't be possible")
}

// IntegrationTest is a convenience function to be called by integration tests
// to make sure that they are allowed to run.
func IntegrationTest(t *testing.T) {
	if os.Getenv("RUN_INT_TESTS") == "" {
		t.Skipf("RUN_INT_TESTS is not set, skipping %s", t.Name())
	}
}

func FakeGitHubClient(t *testing.T) *fakegithub.FakeGitHubAPIHttpClient {
	t.Helper()
	inner := ghclient.NewInternalAPIClient(http.Default("test"), "http://localhost:11223", "octocat", "octocat")
	return fakegithub.NewFakeGitHubAPIClient(inner)
}

func BlackbirdQueryClient(t *testing.T) query.QueryAPI {
	t.Helper()

	client, err := clientauth.NewRequestHMACSigner("octocat", http.Default("test_client"))
	require.NoError(t, err)

	return query.NewQueryAPIProtobufClient("http://localhost:9888", client)
}

// Client for the Rust-based semantic query service.
func BlackbirdSemanticQueryClient(t *testing.T) semantic.SemanticQueryAPI {
	t.Helper()

	client, err := clientauth.NewRequestHMACSigner("octocat", http.Default("test_client"))
	require.NoError(t, err)

	return semantic.NewSemanticQueryAPIProtobufClient("http://localhost:9890", client)
}

func BlackbirdAdminClient(t *testing.T) admin.AdminAPI {
	t.Helper()

	client, err := clientauth.NewRequestHMACSigner("octocat", http.Default("test_client"))
	require.NoError(t, err)

	return admin.NewAdminAPIProtobufClient("http://localhost:9889", client)
}

// Returns a ServingAPI client for the integration test cache cluster.
func CacheClusterServingAPI(t *testing.T) servingpb.ServingAPI {
	t.Helper()

	return servingpb.NewServingAPIProtobufClient("http://localhost:9947", http.Default("test_client"))
}

var seq = uint32(1_000_000)

// RepoID generates a unique repo ID for use in tests. For example, you can
// insert this in the database and it won't conflict with other repo IDs.
func RepoID(t *testing.T) types.RepoID {
	t.Helper()

	return types.RepoID(atomic.AddUint32(&seq, 1))
}

func OwnerID(t *testing.T) uint32 {
	t.Helper()

	return atomic.AddUint32(&seq, 1)
}

func NetworkID(t *testing.T) types.NetworkID {
	t.Helper()

	return types.NetworkID(atomic.AddUint32(&seq, 1))
}

func RepoIDs(t *testing.T, n int) []types.RepoID {
	t.Helper()

	out := make([]types.RepoID, n)
	for i := 0; i < n; i++ {
		out[i] = RepoID(t)
	}

	return out
}

// KafkaPartition returns a stable fake Kafka partition number given a repo ID.
func KafkaPartition(t *testing.T, repoID types.RepoID) int32 {
	t.Helper()
	return int32(repoID % 32)
}

func KafkaOffset(t *testing.T) int64 {
	t.Helper()
	return int64(atomic.AddUint32(&seq, 1))
}

func TreeEntryID(t *testing.T) uint64 {
	t.Helper()
	return uint64(atomic.AddUint32(&seq, 1))
}

// Returns a tuple of (sha, content) where sha is the Git blob hash of the
// content. The content is deterministic and unique based on
// the shard ID and position.
func Content(t *testing.T, shardID int, id int) ([]byte, []byte) {
	content := fmt.Sprintf("document-shardID:%d-position:%d", shardID, id)

	// TODO: We can use this, but it changes the sha ranges for pagination queries you you'll have to update
	// pagination_test.go.
	// oid := OIDFromContent(t, content)

	hash := sha1.New()
	hash.Write([]byte(content))
	bs := hash.Sum(nil)
	oid := gitaccess.NewObjectIDFromBytes(bs)

	return oid.Bytes(), []byte(content)
}

// Generate a score for a document that is unique within this test run.
func Score(t *testing.T) float32 {
	t.Helper()
	id := atomic.AddUint32(&seq, 1)
	return float32(math.Log(float64(id)))
}

func Repositories(t *testing.T, n int) []*db.Repository {
	t.Helper()

	out := make([]*db.Repository, 0, n)
	ids := RepoIDs(t, n)

	for _, id := range ids {
		ownerID := OwnerID(t)
		repo := &db.Repository{
			RepoID:          id,
			OwnerID:         ownerID,
			OwnerLogin:      fmt.Sprintf("owner-%d", ownerID),
			Name:            fmt.Sprintf("repo-%d", id),
			IsPublic:        false,
			SourceTopic:     sql.NullString{},
			IsArchived:      false,
			PushedAt:        sql.NullTime{Time: time.Now().UTC(), Valid: true},
			CreatedAt:       sql.NullTime{Time: time.Now().UTC(), Valid: true},
			HasLicense:      sql.NullBool{Bool: false, Valid: true},
			LicenseName:     sql.NullString{String: "", Valid: true}, // This is how we store missing license names :(
			NumWatchers:     sql.NullInt32{Int32: 0, Valid: true},
			NumStars:        sql.NullInt32{Int32: 0, Valid: true},
			HasReadme:       sql.NullBool{Bool: false, Valid: true},
			PublicForkCount: sql.NullInt32{Int32: 0, Valid: true},
			IsFork:          sql.NullBool{Bool: false, Valid: true},
			NetworkID:       sql.NullInt32{Int32: int32(NetworkID(t)), Valid: true},
			CommitOID:       UniqueOID(t).Bytes(),
			CommitSeqNo:     sql.NullInt64{Int64: 1, Valid: true},
			RepoSeqNo:       sql.NullInt64{Int64: 1, Valid: true},
		}

		out = append(out, repo)
	}

	return out
}

// Helper to create repos with known IDs from [1, n] for testing partitioning.
// Using helpers.Repositories can cause tests to interfere with each other,
// because the ID is unique within a test run.
func RepositoriesWithID(t *testing.T, n int) []*db.Repository {
	t.Helper()

	out := []*db.Repository{}
	for i := 0; i < n; i++ {
		repoID := types.RepoID(i + 1)
		ownerID := OwnerID(t)
		repo := &db.Repository{
			RepoID:          repoID,
			OwnerID:         ownerID,
			OwnerLogin:      fmt.Sprintf("owner-%d", ownerID),
			Name:            fmt.Sprintf("repo-%d", repoID),
			IsPublic:        false,
			SourceTopic:     sql.NullString{},
			IsArchived:      false,
			PushedAt:        sql.NullTime{Time: time.Now().UTC(), Valid: true},
			CreatedAt:       sql.NullTime{Time: time.Now().UTC(), Valid: true},
			HasLicense:      sql.NullBool{Bool: false, Valid: true},
			LicenseName:     sql.NullString{},
			NumWatchers:     sql.NullInt32{Int32: 0, Valid: true},
			NumStars:        sql.NullInt32{Int32: 0, Valid: true},
			HasReadme:       sql.NullBool{Bool: false, Valid: true},
			PublicForkCount: sql.NullInt32{Int32: 0, Valid: true},
			IsFork:          sql.NullBool{Bool: false, Valid: true},
			NetworkID:       sql.NullInt32{Int32: int32(NetworkID(t)), Valid: true},
			RepoSeqNo:       sql.NullInt64{Int64: 1, Valid: true},
		}

		out = append(out, repo)
	}

	return out
}

// InsertRepositories inserts one or more repository records. Compare
// CreateRepository, which sets up a repository in Spokesd.
func InsertRepositories(t *testing.T, db *sqlx.DB, repos ...*db.Repository) {
	t.Helper()

	sql := `
INSERT INTO
  blackbird_repositories (id, owner_id, owner_login, name, is_public, source_topic, deleted_at, is_archived, pushed_at, created_at, has_license, num_watchers, num_stars, has_readme, public_fork_count, commit_oid, network_id, license_name, is_fork, experiments, seq_no, repo_seq_no)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`
	for _, repo := range repos {
		_, err := db.Exec(
			sql,
			repo.RepoID,
			repo.OwnerID,
			repo.OwnerLogin,
			repo.Name,
			repo.IsPublic,
			repo.SourceTopic,
			repo.DeletedAt,
			repo.IsArchived,
			repo.PushedAt,
			repo.CreatedAt,
			repo.HasLicense,
			repo.NumWatchers,
			repo.NumStars,
			repo.HasReadme,
			repo.PublicForkCount,
			repo.CommitOID,
			repo.NetworkID,
			repo.LicenseName,
			repo.IsFork,
			repo.Experiments,
			repo.CommitSeqNo,
			repo.RepoSeqNo,
		)
		require.NoError(t, err)
	}
}

// CreateRepository is a hacktacular way to create a new copy of Spokesd's repo
// ID 1. Only valid in integration tests. Returns the new repo ID.
func CreateRepository(t *testing.T) int {
	t.Helper()

	if os.Getenv("RUN_INT_TESTS") == "" {
		require.Fail(t, "Cannot run CreateRepository outside of an integration test. It requires Spokesd")
	}

	// First, clone repo ID 1 out of Spokesd
	dir, err := os.MkdirTemp("", "git-tfs")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	cmd := exec.Command("git", "clone", "../../../deps/spokes-proto/repositories/c/nw/c4/ca/42/1/1.git", dir)
	err = cmd.Run()
	require.NoError(t, err)
	t.Logf("cloned repo 1 to %s", dir)

	// Then, use clone-repo to put a new copy of the repo into Spokesd under a different ID
	cmd = exec.Command("script/clone-repo", dir)
	cmd.Dir = "../../../deps/spokes-proto"
	out, err := cmd.Output()
	t.Logf("spokesd clone-repo output: %s", string(out))
	require.NoError(t, err)

	re := regexp.MustCompile(`Repository (\d+) is ready to go!`)
	match := re.FindStringSubmatch(string(out))
	require.Len(t, match, 2, "could not find repo ID in spokesd output")

	repoID, err := strconv.Atoi(match[1])
	require.NoError(t, err)

	return repoID
}

// Make a fake ingernal API response object from a database repo.
func GitHubRepositoryFromRepository(t *testing.T, repo *db.Repository) *github.Repository {
	pushedAt := time.Now().UTC()
	if repo.PushedAt.Valid {
		pushedAt = repo.PushedAt.Time
	}

	createdAt := time.Now().UTC()
	if repo.CreatedAt.Valid {
		createdAt = repo.CreatedAt.Time
	}

	licenseName := ""
	if repo.LicenseName.Valid {
		licenseName = repo.LicenseName.String
	}

	numWatchers := int32(123)
	if repo.NumWatchers.Valid {
		numWatchers = int32(repo.NumWatchers.Int32)
	}

	numStars := int32(123)
	if repo.NumStars.Valid {
		numStars = int32(repo.NumStars.Int32)
	}

	hasReadme := true
	if repo.HasReadme.Valid {
		hasReadme = repo.HasReadme.Bool
	}

	publicForkCount := int32(123)
	if repo.PublicForkCount.Valid {
		publicForkCount = int32(repo.PublicForkCount.Int32)
	}

	repoSeqNo := int64(1)
	if repo.RepoSeqNo.Valid {
		repoSeqNo = repo.RepoSeqNo.Int64
	}

	return &github.Repository{
		ID:              repo.RepoID,
		NetworkID:       types.NetworkID(repo.NetworkID.Int32),
		OwnerID:         repo.OwnerID,
		OwnerLogin:      repo.OwnerLogin,
		OwnerSpammy:     false,
		Name:            repo.Name,
		Public:          repo.IsPublic,
		Archived:        repo.IsArchived,
		DiskUsage:       0,
		PushedAt:        pushedAt,
		CreatedAt:       createdAt,
		LicenseName:     licenseName,
		NumWatchers:     numWatchers,
		NumStars:        numStars,
		HasReadme:       hasReadme,
		PublicForkCount: publicForkCount,
		PayingCustomer:  false,
		IsFork:          repo.IsFork.Bool,
		Experiments:     repo.Experiments,
		UpdatedAt:       time.Now(),
		RepoSeqNo:       types.RepoSeqNo(repoSeqNo),
	}
}

func OID(t *testing.T, sha string) gitaccess.ObjectID {
	oid, err := gitaccess.NewObjectIDFromSHA(sha)
	if err != nil {
		t.Fatal(err)
	}
	return oid
}

func OIDFromContent(t *testing.T, content string) gitaccess.ObjectID {
	hash := sha1.New()
	header := fmt.Sprintf("blob %d\\0", len(content))
	hash.Write([]byte(header))
	hash.Write([]byte(content))
	bs := hash.Sum(nil)
	return gitaccess.NewObjectIDFromBytes(bs)
}

func RandomOID(t *testing.T) gitaccess.ObjectID {
	randString := RandomString(32)
	hash := sha1.New()
	hash.Write([]byte(randString))
	bs := hash.Sum(nil)
	return gitaccess.NewObjectIDFromBytes(bs)
}

// https://gist.github.com/nicklaw5/9d2d76b04d345152364d9b8cb4b554e9
var characterRunes = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

func RandomString(n int) string {
	b := make([]rune, n)
	for i := range b {
		b[i] = characterRunes[rand.Intn(len(characterRunes))]
	}
	return string(b)
}

var stringSeq atomic.Uint32

// UniqueString generates a process-unique string using a sequence.
func UniqueString(t *testing.T) string {
	t.Helper()
	id := stringSeq.Add(1)
	return fmt.Sprintf("unique-string-%d", id)
}

var oidSeq atomic.Uint32

// UniqueOID generates a process-unique object ID using a sequence.
func UniqueOID(t *testing.T) gitaccess.ObjectID {
	t.Helper()
	val := oidSeq.Add(1)
	b := make([]byte, 4)
	for i := uint32(0); i < 4; i++ {
		b[i] = byte((val >> (8 * i)) & 0xff)
	}

	data := bytes.Repeat(b, 5)

	return gitaccess.NewObjectIDFromBytes(data)
}

// GetTime returns a time.Time for a RFC3339 formated string: e.g., "2006-01-02T15:04:05Z07:00"
func GetTime(t *testing.T, timeStr string) time.Time {
	t.Helper()
	ret, err := time.Parse(time.RFC3339, timeStr)
	require.NoError(t, err)
	return ret
}

func GetNullTime(t *testing.T, timeStr string) sql.NullTime {
	t.Helper()
	return sql.NullTime{Time: GetTime(t, timeStr), Valid: true}
}

func SearchIndexWithRepos(t *testing.T, repos ...*db.Repository) search.Index {
	snaps := []*snapshotpb.SnapshotEntry{}
	for _, repo := range repos {
		snaps = append(snaps, &snapshotpb.SnapshotEntry{
			RepoId:         uint32(repo.RepoID),
			OwnerId:        repo.OwnerID,
			Nwo:            repo.NWO(),
			IsRepoPublic:   repo.IsPublic,
			IsRepoArchived: repo.IsArchived,
		})
	}
	return SearchIndexWithSnapshots(t, snaps...)
}

func NameAndOwnerFromSnapshot(entry *snapshotpb.SnapshotEntry) (string, string) {
	components := strings.Split(entry.Nwo, "/")
	return components[0], components[1]
}

func SearchIndexWithSnapshots(t *testing.T, snapshots ...*snapshotpb.SnapshotEntry) search.Index {
	t.Helper()
	var validateQ func(t *testing.T, q *querypb.Query)

	// Make sure the  proto queries received by stubs are valid.
	validateQ = func(t *testing.T, q *querypb.Query) {
		t.Helper()
		for _, sub := range q.Subqueries {
			validateQ(t, sub)
		}

		switch q.Kind {
		case querypb.QueryKind_QUERY_KIND_QUALIFIER:
			if q.Domain == querypb.Domain_DOMAIN_UNSPECIFIED {
				t.Fatalf("a domain must be specified for %s qualifier", q.Kind)
			}
		}
	}

	index := &searchfakes.FakeIndex{}
	index.BuildCacheFromQueryStub = func(ctx context.Context, isGloballyScoped bool, a *models.Actor, query *querypb.Query) (*search.RepoAndOwnerCache, error) {
		validateQ(t, query)
		cache := search.NewRepoAndOwnerCache()
		var accessibleRepos types.RepoIDSet
		if a != nil {
			accessibleRepos = a.AccessiblePrivateRepoIDs
		}
		for _, entry := range snapshots {
			// An errored snapshot may not have a valid NWO
			if entry.Nwo == "" {
				continue
			}

			nwo := types.NWOFromString(entry.Nwo)
			cache.OwnersByID[entry.OwnerId] = &models.Owner{OwnerID: entry.OwnerId, OwnerLogin: nwo.Owner().String()}
			cache.OwnersByLogin[strings.ToLower(nwo.Owner().String())] = &models.Owner{OwnerID: entry.OwnerId, OwnerLogin: nwo.Owner().String()}
			_, ok := accessibleRepos[types.RepoID(entry.RepoId)]
			if ok || entry.IsRepoPublic {
				cache.ReposByID[types.RepoID(entry.RepoId)] = entry
				cache.ReposByName[strings.ToLower(nwo.Name())] = append(cache.ReposByName[strings.ToLower(nwo.Name())], entry)
				cache.ReposByNWO[strings.ToLower(entry.Nwo)] = entry
			}
		}
		return cache, nil
	}

	index.GetRepositoryByNWOStub = func(ctx context.Context, a *models.Actor, n types.NWO) (*db.Repository, error) {
		return nil, nil
	}
	index.GetRepositoryByIDStub = func(ctx context.Context, a *models.Actor, ri types.RepoID) (*db.Repository, error) {
		return nil, nil
	}
	index.GetOwnerStub = func(ctx context.Context, login string) (*models.Owner, error) {
		for _, entry := range snapshots {
			nwo := types.NWOFromString(entry.Nwo)
			if nwo.Owner().String() == login {
				return &models.Owner{OwnerID: entry.OwnerId, OwnerLogin: login}, nil
			}
		}
		return nil, nil
	}
	index.GetOwnersStub = func(ctx context.Context, ids []int64) ([]*models.Owner, error) {
		owners := []*models.Owner{}
		for _, entry := range snapshots {
			nwo := types.NWOFromString(entry.Nwo)
			for _, id := range ids {
				if id == int64(entry.OwnerId) {
					owners = append(owners, &models.Owner{OwnerID: entry.OwnerId, OwnerLogin: nwo.Owner().String()})
				}
			}
		}
		return owners, nil
	}
	return index
}

func FakeShardClientWithRepos(t *testing.T, shard *routing.SearchHost, repos ...*db.Repository) *mocks.FakeSearchAPI {
	t.Helper()

	fake := shard.SearchAPI.(*mocks.FakeSearchAPI)
	entries := []*snapshotpb.SnapshotEntry{}
	for _, r := range repos {
		entries = append(entries, &snapshotpb.SnapshotEntry{
			RepoId:       uint32(r.RepoID),
			OwnerId:      r.OwnerID,
			Nwo:          r.NWO(),
			IsRepoPublic: r.IsPublic,
		})
	}
	fake.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
		Snapshots: []*snapshotpb.Snapshot{{Entries: entries}},
	}, nil)

	return fake
}

func FakeShardClient(t *testing.T, shard *routing.SearchHost) *mocks.FakeSearchAPI {
	t.Helper()
	return shard.SearchAPI.(*mocks.FakeSearchAPI)
}

type HostShardSetup struct {
	Shards     [][]*HostShard
	CacheHosts [][]*HostShard
}

type HostShard struct {
	IsAvail bool
}

// Layout for a single corpus where individual hosts for each shard can be
// configured to return errors.
func CorpusLayoutExt(t *testing.T, corpus routing.Corpus, setup *HostShardSetup) *routing.SearchClusters {
	t.Helper()
	const epochID = 1

	allHosts := make([][]*blackbird.IndexHost, len(setup.Shards))
	for i, shards := range setup.Shards {
		shardHosts := []*blackbird.IndexHost{}
		for j, host := range shards {
			hostname := fmt.Sprintf("host-%d-for-shard-%d", j, i)
			client := &mocks.FakeSearchAPI{}
			if host.IsAvail {
				client.SearchReturns(&searchpb.SearchResponse{}, nil)
				client.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
			} else {
				client.SearchReturns(nil, errors.New("testing: host not available"))
				client.SearchSnapshotsReturns(nil, errors.New("testing: host not available"))
			}
			shardHosts = append(shardHosts, &blackbird.IndexHost{Hostname: hostname, SearchClient: client})
		}
		allHosts[i] = shardHosts
	}

	client := &mocks.FakeBlackbirdClient{}
	client.RoutesReturns(blackbird.Routes{Hosts: allHosts, ServingOffset: 10, ServingTs: time.Now().UnixMilli(), Epoch: epochID})

	clients := map[routing.Corpus]blackbird.Client{
		corpus: client,
	}

	return routing.NewSearchClusters(clients)
}

// Extended version of SearchClusters with all the settings. You should only use
// this if your tests rely on a specific servingOffset, servingTs, or epochID.
//
// Each IndexHost will have stubbed Twirp RPCs that return default, empty
// results (not nil).
//
// Use helpers.FakeShardClient to get at the mock query api clients if you need
// to do further stubbing.
func SearchClustersExt(
	t *testing.T,
	epochMode epoch.EpochMode,
	numHosts,
	numServingHosts,
	numCacheHosts int,
	servingOffset routing.ServingOffset,
	servingTs int64,
	epochID types.EpochID,
	servingCorpus routing.Corpus,
	blobFiltering bool,
) *routing.SearchClusters {
	t.Helper()

	clients := map[routing.Corpus]blackbird.Client{}
	for _, corpus := range routing.Corpora {
		hosts := make([][]*blackbird.IndexHost, numHosts)
		for i := 0; i < numHosts; i++ {
			hostname := fmt.Sprintf("shard-%s-%d", corpus.String(), i)
			client := &mocks.FakeSearchAPI{}
			// Stub all responses
			client.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
			client.SearchReturns(&searchpb.SearchResponse{}, nil)
			if i < numServingHosts {
				hosts[i] = []*blackbird.IndexHost{{Hostname: hostname, SearchClient: client}}
			}
			client.StatusReturns(&servingpb.StatusResponse{
				Status: &servingpb.ServingStatus{
					IndexVersion:   42,
					Sha:            "deadbeef",
					BuildTimestamp: timestamppb.New(time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)),
					EpochId:        uint32(epochID),
					Shards:         []*servingpb.Shard{},
				},
			}, nil)
		}

		client := &mocks.FakeBlackbirdClient{}
		client.RoutesReturns(blackbird.Routes{Hosts: hosts, ServingOffset: int64(servingOffset), ServingTs: servingTs, Epoch: uint32(epochID), EpochMode: blackbird.EpochMode(epochMode)})
		client.EpochInfoReturns(blackbird.EpochInfo{EpochID: uint32(epochID), EpochMode: blackbird.EpochMode(epochMode), NumShards: numHosts})
		client.BlobFilteringReturns(blobFiltering)

		if corpus == servingCorpus {
			client.IsServingReturns(true)
		}
		clients[corpus] = client
	}

	return routing.NewSearchClusters(clients)
}

// Default cluster layout for testing if you need to specify the number of index
// hosts in each corpus. Uses a serving_offset=10 and an epoch_id=1. A random cluster
// is selected to serve query traffic.
//
// Each IndexHost will have stubbed Twirp RPCs that return default, empty
// results (not nil).
//
// Use helpers.FakeShardClient to get at the mock query api clients if you need
// to do further stubbing.
func SearchClustersN(t *testing.T, numHosts int) *routing.SearchClusters {
	t.Helper()
	return SearchClustersNWithServingCorpus(t, numHosts, Corpus(t))

}

// Same as SearchClustersN except this lets you choose the serving corpus
func SearchClustersNWithServingCorpus(t *testing.T, numHosts int, corpus routing.Corpus) *routing.SearchClusters {
	t.Helper()

	const (
		servingOffset = 10
		epochID       = 1
		cacheHosts    = 2
	)
	servingTs := time.Now().UTC().UnixMilli()
	return SearchClustersExt(t, epoch.EpochModeLexical, numHosts, numHosts, cacheHosts, servingOffset, servingTs, epochID, corpus, false /*no blob filtering*/)
}

// Returns a cluster layout with blob filtering enabled for all the clusters returned.
func SearchClustersWithBlobFiltering(t *testing.T, numHosts int, servingCorpus routing.Corpus) *routing.SearchClusters {
	t.Helper()

	const (
		servingOffset = 10
		epochID       = 1
		cacheHosts    = 2
	)
	servingTs := time.Now().UTC().UnixMilli()
	return SearchClustersExt(t, epoch.EpochModeLexical, numHosts, numHosts, cacheHosts, servingOffset, servingTs, epochID, servingCorpus, true)

}

// Default cluster layout for testing with 2 index hosts (each serving a single
// shard) in each corpus. A random cluster is selected to serve query traffic.
//
// Each IndexHost will have stubbed Twirp RPCs that return default, empty
// results (not nil).
//
// Use helpers.FakeShardClient to get at the mock query api clients if you need
// to do further stubbing.

func SearchClusters(t *testing.T) *routing.SearchClusters {
	t.Helper()

	const numHosts = 2
	return SearchClustersN(t, numHosts)
}

func SearchClustersWithServingCorpus(t *testing.T, servingCorpus routing.Corpus) *routing.SearchClusters {
	t.Helper()

	const (
		servingOffset = 10
		epochID       = 1
		cacheHosts    = 2
	)
	servingTs := time.Now().UTC().UnixMilli()
	const numHosts = 2

	return SearchClustersExt(t, epoch.EpochModeLexical, numHosts, numHosts, cacheHosts, servingOffset, servingTs, epochID, servingCorpus, false /*no blob filtering*/)
}

func CacheClusters(t *testing.T) *routing.CacheClusters {
	t.Helper()
	const numHosts = 1

	clients := map[string]blackbird.Client{}
	for _, cluster := range routing.CacheClusterNames {
		clients[cluster] = CacheClientForCluster(t, numHosts, cluster)
	}

	return routing.NewCacheClusters(clients)
}

func CacheClientForCluster(t *testing.T, numHosts int, name string) *mocks.FakeBlackbirdClient {
	require.Contains(t, routing.CacheClusterNames, name, "invalid cache cluster name")

	const (
		servingOffset = 10
		epochID       = 1
	)
	servingTs := time.Now().UTC().UnixMilli()

	handler := func(locations []*entities.Location) *cachepb.Published {
		for _, l := range locations {
			if l.Path == "vendor/foo.txt" {
				return &cachepb.Published{
					Partition: -1,
				}
			}
		}
		return nil
	}

	cacheHosts := make([][]*blackbird.IndexHost, numHosts)
	for i := 0; i < numHosts; i++ {
		hostname := fmt.Sprintf("%s-%d", name, i)
		client := &mocks.FakeCacheAPI{}
		client.MstReturns(&cachepb.MstResponse{}, nil)
		client.PublishCacheDocumentStub = func(ctx context.Context, pcdr *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
			p := handler(pcdr.GitDocument.Locations)
			return &cachepb.PublishCacheDocumentResponse{Published: p}, nil
		}
		client.PublishDocumentStub = func(ctx context.Context, pdr *cachepb.PublishDocumentRequest) (*cachepb.PublishDocumentResponse, error) {
			p := handler(pdr.GitDocument.Locations)
			return &cachepb.PublishDocumentResponse{Published: p}, nil
		}
		client.PublishDeleteDocumentStub = func(ctx context.Context, pddr *cachepb.PublishDeleteDocumentRequest) (*cachepb.PublishDeleteDocumentResponse, error) {
			p := handler(pddr.GitDocument.Locations)
			return &cachepb.PublishDeleteDocumentResponse{Published: p}, nil
		}
		client.StatusReturns(&servingpb.StatusResponse{
			Status: &servingpb.ServingStatus{
				IndexVersion:   42,
				Sha:            "deadbeef",
				BuildTimestamp: timestamppb.New(time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)),
				EpochId:        epochID,
				Shards:         []*servingpb.Shard{},
			},
		}, nil)
		cacheHosts[i] = []*blackbird.IndexHost{{Hostname: hostname, CacheClient: client}}
	}

	cacheClient := &mocks.FakeBlackbirdClient{}
	cacheClient.RoutesReturns(blackbird.Routes{Hosts: cacheHosts, ServingOffset: servingOffset, ServingTs: servingTs, Epoch: epochID})
	return cacheClient
}

func MakeBackfillableCluster(
	t *testing.T,
	shardRepos []*db.Repository,
	servingCorpus routing.Corpus,
	sourceEpochID types.EpochID,
) (*routing.SearchClusters, *routing.CacheClusters, *mocks.FakeCacheAPI) {
	t.Helper()

	const partitions = 2

	mockCacheClient := &mocks.FakeCacheAPI{}
	mockCacheClient.MstStub = func(ctx context.Context, req *cachepb.MstRequest) (*cachepb.MstResponse, error) {
		offsets := map[uint32]int64{}
		for _, sr := range shardRepos {
			partition := types.PartitionID(sr.RepoID, partitions)
			offsets[partition]++
		}

		published := []*cachepb.Published{}
		for partition, offset := range offsets {
			published = append(published, &cachepb.Published{Partition: int32(partition), Offset: offset})
		}

		return &cachepb.MstResponse{
			Status: &servingpb.ServingStatus{
				EpochId: uint32(sourceEpochID),
				Shards:  []*servingpb.Shard{{ServingTs: 0, ServingOffset: 1}},
			},
			Offsets: published,
			SourceKafkaOffsets: []*entities.SourceKafkaOffsets{
				{
					Topic:            routing.IncrementalSourceTopic,
					PartitionOffsets: []*entities.SourceKafkaOffsets_PartitionOffset{{Partition: 0, Offset: 100}, {Partition: 1, Offset: 200}},
				},
			},
		}, nil
	}

	epochMode := epoch.EpochModeHybrid
	searchClusters := SearchClustersWithServingCorpus(t, servingCorpus)
	// return same cache cluster for all the corpora
	for _, c := range routing.Corpora {
		searchClient := searchClusters.ClientForCorpus(c).(*mocks.FakeBlackbirdClient)
		searchClient.CacheClusterReturns(routing.CacheClusterNames[0])
	}

	clients := map[string]blackbird.Client{}
	cacheHosts := make([][]*blackbird.IndexHost, 1)
	hostname := fmt.Sprintf("cache-%s-01", servingCorpus.String())
	cacheHosts[0] = []*blackbird.IndexHost{{Hostname: hostname, CacheClient: mockCacheClient}}
	cacheClient := &mocks.FakeBlackbirdClient{}
	cacheClient.EpochInfoReturns(blackbird.EpochInfo{EpochID: uint32(sourceEpochID), EpochMode: blackbird.EpochMode(epochMode), NumShards: 1})
	cacheClient.RoutesReturns(blackbird.Routes{Hosts: cacheHosts, ServingOffset: 10, ServingTs: time.Now().UTC().UnixMilli(), Epoch: uint32(sourceEpochID), EpochMode: blackbird.EpochMode(epochMode)})
	clients[routing.CacheClusterNames[0]] = cacheClient

	return searchClusters, routing.NewCacheClusters(clients), mockCacheClient
}

func CacheClient(t *testing.T, numHosts int) *mocks.FakeBlackbirdClient {
	return CacheClientForCluster(t, numHosts, routing.CacheClusterNames[0])
}

func FakeClient(t *testing.T, client blackbird.Client) *mocks.FakeBlackbirdClient {
	t.Helper()

	return client.(*mocks.FakeBlackbirdClient)
}

func FakeCacheAPI(t *testing.T, client blackbird.Client, shardID int) *mocks.FakeCacheAPI {
	t.Helper()

	routes := client.Routes()
	if shardID > len(routes.Hosts) {
		t.Fatalf("shard ID %d larger than number of hosts %d", shardID, len(routes.Hosts))
	}

	indexHost := routes.Hosts[shardID][0]
	return indexHost.CacheClient.(*mocks.FakeCacheAPI)
}

func CopilotClient(t *testing.T) *copilotfakes.FakeClient {
	t.Helper()
	return &copilotfakes.FakeClient{}
}

func IndexerCluster(t *testing.T) *routing.IndexerCluster {
	t.Helper()

	const numHosts = 1
	client := IndexClient(t, numHosts, Corpus(t))

	return routing.NewIndexerCluster(client)
}

func IndexerClusters(t *testing.T) *routing.IndexerClusters {
	t.Helper()

	const numHosts = 1
	clients := map[routing.Corpus]blackbird.Client{}
	for _, corpus := range routing.Corpora {
		clients[corpus] = IndexClient(t, numHosts, corpus)
	}

	return routing.NewIndexerClusters(clients)
}

func IndexClient(t *testing.T, numHosts int, corpus routing.Corpus) *mocks.FakeBlackbirdClient {
	const (
		servingOffset = 10
		epochID       = 1
	)
	cluster := corpus.ClusterName()
	servingTs := time.Now().UTC().UnixMilli()

	indexerHosts := make([][]*blackbird.IndexHost, numHosts)
	for i := 0; i < numHosts; i++ {
		hostname := fmt.Sprintf("%s-%d", cluster, i)
		client := &mocks.FakeIndexAPI{}
		client.StatusReturns(&servingpb.StatusResponse{
			Status: &servingpb.ServingStatus{
				IndexVersion:   42,
				Sha:            "deadbeef",
				BuildTimestamp: timestamppb.New(time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)),
				EpochId:        epochID,
				Shards: []*servingpb.Shard{{
					Id:            uint32(0),
					ServingOffset: int64(servingOffset),
					ServingTs:     servingTs,
					SourceKafkaInfo: map[string]*servingpb.KafkaInfo{
						routing.IncrementalSourceTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								1: {Offset: 100, Timestamp: time.Now().Unix()},
							},
						},
					},
				}},
				SequenceNumber: 0,
			},
		}, nil)
		indexerHosts[i] = []*blackbird.IndexHost{{Hostname: hostname, IndexClient: client}}
	}

	client := &mocks.FakeBlackbirdClient{}
	client.RoutesReturns(blackbird.Routes{Hosts: indexerHosts, ServingOffset: servingOffset, ServingTs: servingTs, Epoch: epochID})
	client.CacheClusterReturns(routing.CacheClusterNames[0])
	client.EpochInfoReturns(blackbird.EpochInfo{EpochID: uint32(epochID), NumShards: 1})

	return client
}

// Retrieve the mocked IndexAPI client for the given IndexerHost.
func FakeIndexAPI(t *testing.T, host *routing.IndexerHost) *mocks.FakeIndexAPI {
	t.Helper()

	return host.IndexAPI.(*mocks.FakeIndexAPI)
}

func MockOffsetTracker(t *testing.T, topic string, partition int32) *kafka.OffsetTracker {
	consumer := &kafkafakes.FakeIngestConsumer{}
	tracker := kafka.NewOffsetTracker(consumer)
	// Initialize the topic/partition.
	tracker.TrackMsg(context.Background(), topic, partition, 0, time.Time{})
	return tracker
}

func DecodeSnapshot(t *testing.T, msg *sarama.ProducerMessage) *blackbirdpb.SnapshotTreeUpdate {
	event := blackbirdpb.SnapshotTreeUpdate{}
	envelope := hydroschemas.Envelope{}

	err := proto.Unmarshal([]byte(msg.Value.(sarama.ByteEncoder)), &envelope)
	require.NoError(t, err)

	err = proto.Unmarshal(envelope.Message, &event)
	require.NoError(t, err)

	return &event
}
func MockDelayedTimestampReader(t *testing.T) *kafka.DelayedTimestampReader {
	t.Helper()

	return kafka.NewDelayedTimestampReader(func() kafka.MessageReader { return &kafka.SaramaMessageReader{} }, routing.IncrementalSourceTopic)
}

func FakeSharedKafkaClient(t *testing.T) sarama.Client {
	client := &mocks.FakeSaramaClient{}
	client.ConfigReturns(sarama.NewConfig())
	return client
}

func FakeAdminClient(t *testing.T, corpus routing.Corpus, epochID types.EpochID, offset int64) *kafka.AdminClient {
	backfillTopic := corpus.EpochBackfillTopic(epochID)
	return FakeAdminClientWithOffsets(
		t,
		epochID,
		map[string]map[int32]*sarama.OffsetFetchResponseBlock{
			backfillTopic: {0: {Offset: offset + 1}},
		},
	)
}

func FakeAdminClientWithOffsets(
	t *testing.T,
	epochID types.EpochID,
	offsetBlocks map[string]map[int32]*sarama.OffsetFetchResponseBlock,
) *kafka.AdminClient {

	clusterAdmin := &mocks.FakeClusterAdmin{}
	clusterAdmin.ListConsumerGroupsStub = func() (map[string]string, error) {
		res := map[string]string{}
		for _, c := range routing.Corpora {
			res[c.ConsumerGroup(epochID)] = "blah"
		}
		return res, nil
	}

	clusterAdmin.ListConsumerGroupOffsetsStub = func(cg string, topics map[string][]int32) (*sarama.OffsetFetchResponse, error) {
		return &sarama.OffsetFetchResponse{Blocks: offsetBlocks}, nil
	}

	makeAdminClient := func() sarama.ClusterAdmin {
		return clusterAdmin
	}
	return kafka.NewAdminClient(makeAdminClient, FakeSharedKafkaClient(t))

}

func NoopConsumerGroupManager(t *testing.T) kafka.ConsumerGroupManager {
	return &noopConsumerGroupManager{}
}

type noopConsumerGroupManager struct{}

func (n *noopConsumerGroupManager) Create(ctx context.Context, topic string, consumerGroup string, offsets map[int32]int64) error {
	return nil
}

func (n *noopConsumerGroupManager) CreateWithLatestOffsets(ctx context.Context, topic string, consumerGroup string) error {
	return nil
}
