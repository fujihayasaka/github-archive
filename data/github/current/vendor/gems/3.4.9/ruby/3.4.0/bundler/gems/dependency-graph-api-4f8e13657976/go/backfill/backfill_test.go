package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"regexp"
	"strings"
	"testing"

	dg_proto "github.com/github/dependency-graph-api/gen/hydro/schemas/github/dependencygraph/v0"
	repositories "github.com/github/github-proto/gen/go/repositories/v1"
	hydro_pb "github.com/github/hydro-client-go/v4/generated/hydro/schemas/hydro/v1"
	"github.com/github/hydro-client-go/v4/pkg/hydro"
	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/trees"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/golang/protobuf/proto"
)

var (
	mockGoRepo = []string{
		"go.mod",
		"nested/package/go.mod",
		"nested/package/main.go",
		"vendor/github.com/coolalgorithms/go.mod",
	}
	mockActionsRepo = []string{
		".github/workflows/dostuff.yaml",
		".github/workflows/more.yml",
		"workflows/notthis.yml",
		"actions.yml",
	}
	mockArbitraryRepo = []string{
		"some/folder/package.json",
		"some/other/folder/package-lock.json",
		"almosttoplevel/yarn.lock",
	}
	mockCargoRepo = []string{
		"cargo.toml",
		"nested/package/cargo.toml",
		"cargo.lock",
		"nested/package/cargo.lock",
		"nested/package/cargo",
		"cargo.not",
		"Cargo.lock",
		"Cargo.toml",
		"nested/package/Cargo.toml",
		"nested/package/Cargo.lock",
	}
)

// Given a slice of paths, create a fake ListTreesResponse as if each path were
// a blob in the tree. Other fields only exist for structure and do not have
// meaningful values.
func newBlobTree(paths []string) *trees.ListTreesResponse {
	var entries []*types.TreeEntry
	for _, path := range paths {
		entries = append(entries, &types.TreeEntry{
			Mode:   types.NewMode(0),
			Object: types.NewBlobObject(types.NewObjectID("some_blob_oid")),
			Path:   types.NewPath([]byte(path)),
		})
	}
	return &trees.ListTreesResponse{
		Entries:    entries,
		NextCursor: nil,
	}
}

// Mock spokes TreesAPI implementation
type treeSvc struct{ trees.TreesAPI }

func (t *treeSvc) ListTrees(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
	return newBlobTree(mockGoRepo), nil
}

type objectSvc struct{ objects.ObjectsAPI }

func (o *objectSvc) ResolveObject(ctx context.Context, req *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error) {
	return &objects.ResolveObjectResponse{
		Oid: types.NewObjectID("thesha"),
	}, nil
}

// Mock spokes BlobsAPI implementation
type blobSvc struct{ blobs.BlobsAPI }

func (s *blobSvc) GetBlobContents(ctx context.Context, req *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error) {
	return &blobs.GetBlobContentsResponse{
		Contents:  []byte{},
		Size:      0,
		Truncated: false,
	}, nil
}

// Mock github/github RepositoriesAPI implementation
type repoSvc struct{ repositories.RepositoriesAPI }

func (s *repoSvc) FindRepositories(ctx context.Context, req *repositories.FindRepositoriesRequest) (*repositories.FindRepositoriesResponse, error) {
	var repos []*repositories.RepositoryListItem
	for _, id := range req.Ids {
		repos = append(repos,
			&repositories.RepositoryListItem{
				Id:         id,
				OwnerId:    4,
				Name:       fmt.Sprintf("repo_%d", id),
				OwnerLogin: fmt.Sprintf("owner_%d", id),
				Status:     0,
				Visibility: 0,
			})
	}
	return &repositories.FindRepositoriesResponse{Repositories: repos}, nil
}

// Most are mocked at a network level but kafka is not an http service and
// doesn't have tooling readily available for this so we use a hydro memory sink
func TestIntegration(t *testing.T) {
	repoHandler := repositories.NewRepositoriesAPIServer(&repoSvc{}, nil)
	spokesHandler := http.NewServeMux()
	spokesHandler.Handle("/twirp/github.spokes.blobs.v1.BlobsAPI/", blobs.NewBlobsAPIServer(&blobSvc{}))
	spokesHandler.Handle("/twirp/github.spokes.trees.v1.TreesAPI/", trees.NewTreesAPIServer(&treeSvc{}))
	spokesHandler.Handle("/twirp/github.spokes.objects.v1.ObjectsAPI/", objects.NewObjectsAPIServer(&objectSvc{}))

	serve("localhost:12080", spokesHandler)
	serve("localhost:12345", repoHandler)
	serve("localhost:12346", http.HandlerFunc(depgraphServer))

	type envVars struct {
		name  string
		value string
	}
	vars := []envVars{
		{name: "SPOKES_BASE_URL", value: "http://localhost:12080"},
		{name: "MONOLITH_API_URL", value: "http://localhost:12345"},
		{name: "MONOLITH_TWIRP_HMAC_KEY", value: "secret"},
		{name: "HYDRO_CERT_PATH", value: "testdata/ca.crt"},
		{name: "HYDRO_BROKERS_SSL", value: "localhost:9092"},
		{name: "DEPENDENCY_GRAPH_API_URL", value: "http://localhost:12346"},
	}
	for _, v := range vars {
		err := os.Setenv(v.name, v.value)
		if err != nil {
			log.Fatal(err)
		}
	}

	config := newApp()

	hydroChan := make(chan hydro.Message, 100)
	sink, err := hydro.NewMemorySink(hydroChan)
	if err != nil {
		t.Fatal(err)
	}
	publisher, err := hydro.NewPublisher(sink)
	if err != nil {
		t.Fatal(err)
	}
	config.hydroPublisher = publisher

	config.maxSpokesWorkers = 5
	config.maxHydroWorkers = 5
	config.sleep = 0

	repos, err := readRepositories("testdata/test_repos.csv")
	if err != nil {
		t.Fatal(err)
	}

	go func() {
		backfill(config, ecosystems["go"].isManifest, "go", repos)
		close(hydroChan)
	}()

	var hydroMessages []hydro.Message

	for message := range hydroChan {
		hydroMessages = append(hydroMessages, message)
	}

	// Our mock returns two matching manifests per repo
	if len(hydroMessages) != len(repos)*2 {
		t.Errorf("%d hydro messages were queued, expected %d", len(hydroMessages), len(repos)*2)
	}

	backfilled := make(map[string]bool)

	for _, m := range hydroMessages {
		change, err := decodeManifestFileChange(m)
		if err != nil {
			t.Fatal(err)
		}

		fullPath := fmt.Sprintf("%s/%s", change.RepositoryNwo, path.Join(change.ManifestFile.Path, change.ManifestFile.Filename))
		if backfilled[fullPath] {
			t.Errorf("File %s seen twice", fullPath)
		} else {
			backfilled[fullPath] = true
		}

		if change.ManifestFile.Filename != "go.mod" {
			t.Errorf("filename: %s, expected go.mod", change.ManifestFile.Filename)
		}

		if change.ManifestFile.Path != "" && change.ManifestFile.Path != "nested/package" {
			t.Errorf("manifest path: %s, expected either '' or 'nested/package'", change.ManifestFile.Path)
		}

		if change.ManifestFile.GitRef != "thesha" {
			t.Errorf("manifest GitRef: %s, expected 'thesha'", change.ManifestFile.GitRef)
		}

		if change.ManifestFile.BlobOid != "some_blob_oid" {
			t.Errorf("manifest BlobOid: %s, expected 'some_blob_oid'", change.ManifestFile.BlobOid)
		}

		if !change.IsBackfill {
			t.Error("manifest is not marked as backfill")
		}
	}

	// Check that we saw every repository and manifest
	for i := 1; i <= len(repos); i++ {
		for _, fullPath := range []string{
			fmt.Sprintf("owner_%d/repo_%d/go.mod", i, i),
			fmt.Sprintf("owner_%d/repo_%d/nested/package/go.mod", i, i),
		} {
			if !backfilled[fullPath] {
				t.Errorf("Didn't backfill %s", fullPath)
			}
		}
	}
}

func decodeManifestFileChange(message hydro.Message) (dg_proto.RepositoryManifestFileChange, error) {
	envelope := hydro_pb.Envelope{}
	manifestFileChange := dg_proto.RepositoryManifestFileChange{}

	if err := proto.Unmarshal(message.Value, &envelope); err != nil {
		return manifestFileChange, err
	}
	if err := proto.Unmarshal(envelope.Message, &manifestFileChange); err != nil {
		return dg_proto.RepositoryManifestFileChange{}, err
	}
	return manifestFileChange, nil
}

func TestSelectGoManifests(t *testing.T) {
	mockTreeResponse := newBlobTree(mockGoRepo)
	result := selectManifests(mockTreeResponse.Entries, ecosystems["go"].isManifest)

	if len(result) != 2 {
		t.Errorf("result was %v, expected two files to be selected", result)
	}

	if path := string(result[0].path); path != "go.mod" {
		t.Errorf("got %s as first file selected, expected 'go.mod'", path)
	}

	if path := string(result[1].path); path != "nested/package/go.mod" {
		t.Errorf("got %s as second file selected, expected 'nested/package/go.mod'", path)
	}
}

func TestSelectActionsManifests(t *testing.T) {
	mockTreeResponse := newBlobTree(mockActionsRepo)
	result := selectManifests(mockTreeResponse.Entries, ecosystems["actions"].isManifest)

	if len(result) != 2 {
		t.Errorf("result was %v, expected two files to be selected", result)
	}

	expected := ".github/workflows/dostuff.yaml"
	if path := string(result[0].path); path != expected {
		t.Errorf("got %s as first file selected, expected '%s'", path, expected)
	}

	expected = ".github/workflows/more.yml"
	if path := string(result[1].path); path != expected {
		t.Errorf("got %s as second file selected, expected '%s'", path, expected)
	}
}

func TestSelectCargoManifests(t *testing.T) {
	mockTreeResponse := newBlobTree(mockCargoRepo)
	result := selectManifests(mockTreeResponse.Entries, ecosystems["cargo"].isManifest)

	expected := []string{"cargo.toml", "nested/package/cargo.toml", "cargo.lock", "nested/package/cargo.lock",
		"Cargo.lock", "Cargo.toml", "nested/package/Cargo.toml", "nested/package/Cargo.lock"}

	if len(result) != len(expected) {
		t.Errorf("result was %v, expected %d files to be selected", result, len(expected))
	}

	for i := 0; i < len(expected); i++ {
		if path := string(result[i].path); path != expected[i] {
			t.Errorf("got %s as first file selected, expected '%s'", path, expected[i])
		}
	}
}

func TestSelectArbitraryManifests(t *testing.T) {
	mockTreeResponse := newBlobTree(mockArbitraryRepo)
	yarnLockPredicate := regexp.MustCompile(`.*yarn\.lock\z`)

	result := selectManifests(mockTreeResponse.Entries, yarnLockPredicate.MatchString)

	if len(result) != 1 {
		t.Errorf("result was %v, expected one file to be selected", result)
	}

	if path := string(result[0].path); path != "almosttoplevel/yarn.lock" {
		t.Errorf("got %s as first file selected, expected 'almosttoplevel/yarn.lock'", path)
	}
}

func TestNoTrailingSlashesInPaths(t *testing.T) {
	mockTreeResponse := newBlobTree(mockActionsRepo)
	actions_result := selectManifests(mockTreeResponse.Entries, ecosystems["actions"].isManifest)
	go_result := selectManifests(mockTreeResponse.Entries, ecosystems["go"].isManifest)
	results := append(actions_result, go_result...)

	repo := repositories.RepositoryListItem{Id: 1, OwnerId: 2, Name: "some_repo", OwnerLogin: "some_owner", Status: 3, Visibility: 1}
	commit := types.ObjectID{Id: "some_oid123"}

	for _, manifest := range results {
		full_path := repositoryPath{manifest.path, "bloboid2"}
		message := newMessage(&repo, &commit, full_path)

		if strings.HasSuffix(message.ManifestFile.Path, "/") {
			t.Errorf("%s has a trailing slash", manifest.path)
		}
	}
}

func serve(addr string, handler http.Handler) {
	go func() {
		if err := http.ListenAndServe(addr, handler); err != nil {
			log.Fatal(err)
		}
	}()
}

// depgraphServer fakes the Dependency Graph API service.
func depgraphServer(w http.ResponseWriter, req *http.Request) {
	log.Println("depgraph", req.Method, req.URL)

	// Assume /checkpoints/gopma
	switch req.Method {
	case "PUT":
		var check Checkpoint
		if err := readJSON(req, &check); err != nil {
			log.Printf("depgraph: %v", err)
		}
		log.Printf("checkpoint: %d", check.Value)

	case "GET":
		// Always return the Jan 1, 1970, regardless of PUTs.
		if err := writeJSON(w, Checkpoint{Value: 0}); err != nil {
			log.Printf("depgraph: %v", err)
		}
	}
}

// readJSON decodes JSON data from req.Body into the variable pointed to by x.
func readJSON(req *http.Request, x interface{}) error {
	data, err := io.ReadAll(req.Body)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, x)
}

// writeJSON writes the JSON encoding of x into w.
func writeJSON(w http.ResponseWriter, x interface{}) error {
	w.Header().Set("Content-Type", "application/json")
	data, err := json.Marshal(x)
	if err != nil {
		return err
	}
	_, err = w.Write(data)
	return err
}
