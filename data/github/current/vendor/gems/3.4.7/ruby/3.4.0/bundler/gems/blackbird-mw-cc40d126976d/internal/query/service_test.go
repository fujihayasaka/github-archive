package query

import (
	"bytes"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"math/rand"
	"sort"
	"strings"
	"testing"
	"time"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/gitaccess/gitaccessfakes"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/types"
)

func TestMultipleShards_Success(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 5)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}
	bbDocs := shardsReturn(t, shards, 3)

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.Query(context.Background(), request)
	successCheck(t, shards, 6, response, response.Metadata.Shards, err)
	verifyDocOrdering(t, response.Documents, bbDocs)
}

func shardsReturn(t *testing.T, shards [][]*routing.SearchHost, limit int) []*searchpb.GitDocumentMatch {
	bbDocs := []*searchpb.GitDocumentMatch{}
	for shardID, shard := range shards {
		bbResp := generator.BlackbirdResponse(t, shardID, limit, limit)
		bbDocs = append(bbDocs, bbResp.Documents...)
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}
	return bbDocs
}

func TestLimits(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 10, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	hosts := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 70, 5)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}
	bbDocs := shardsReturn(t, hosts, 10)

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.Query(context.Background(), request)
	// Make sure that we only got 70 results back which is our limit
	successCheck(t, hosts, 70, response, response.Metadata.Shards, err)
	verifyDocOrdering(t, response.Documents, bbDocs)
}

func TestDefaultLimits(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 10, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	// We specify the limit 0 to mimick that a client did not provide a limit param
	request := generator.QueryServiceRequest(t, "test", 0, 2)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}
	bbDocs := shardsReturn(t, shards, 10)

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.Query(context.Background(), request)
	// Make sure default doc limit is honored
	successCheck(t, shards, int(search.DefaultDocsLimit), response, response.Metadata.Shards, err)
	verifyDocOrdering(t, response.Documents, bbDocs)
}

// If a single shard/host is down, we should tolerate that and return partial results.
func TestOneHostDown(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 32, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	hosts := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 2)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}

	goodHosts := hosts[1:]
	badHosts := hosts[0:1]

	bbDocs := shardsReturn(t, goodHosts, 10)

	c := helpers.FakeShardClient(t, hosts[0][0])
	c.SearchReturns(nil, twirp.NewError(twirp.Internal, "shard down"))
	c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)

	badMetas := []*pb.ShardMetadata{}
	goodMetas := []*pb.ShardMetadata{}

	// check failures
	for _, meta := range response.Metadata.Shards {
		if meta.Error != "" {
			badMetas = append(badMetas, meta)
		} else {
			goodMetas = append(goodMetas, meta)
		}

	}
	require.Equal(t, len(badHosts), len(badMetas), "failed metadatas don't match bad shards, they should be equal")

	// check all the usual success assertions against the two shards
	incompleteResultsCheck(t, goodHosts, 50, response, goodMetas, err)
	verifyDocOrdering(t, response.Documents, bbDocs)
}

// If more than one shard is down, the query should fail
func TestManyHostsDown(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 10, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	hosts := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 2)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}

	shardsReturn(t, hosts[3:], 10)
	for _, host := range hosts[0:3] {
		c := helpers.FakeShardClient(t, host[0])
		c.SearchReturns(nil, twirp.NewError(twirp.Internal, "host down"))
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	service := newTestService(t, corpus, searchClusters, &db.Repository{})
	response, err := service.Query(context.Background(), request)
	require.Nil(t, response)
	require.Error(t, err)
}

func TestAllHostsDown(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 5, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	hosts := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 2)

	for _, host := range hosts {
		c := helpers.FakeShardClient(t, host[0])
		c.SearchReturns(nil, twirp.NewError(twirp.Internal, "host down"))
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	service := newTestService(t, corpus, searchClusters, &db.Repository{})
	response, err := service.Query(context.Background(), request)
	require.Nil(t, response, "all hosts down is a hard error going back to the client")
	require.Error(t, err)
}

func TestServingTsOffset(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(ctx, corpus)

	require.GreaterOrEqual(t, time.Now().UTC().UnixMilli(), routes.ServingTs.UnixMilli())
	require.Equal(t, routing.ServingOffset(10), routes.ServingOffset) // Default value of helpers.ClusterLayout
	// TODO: Should the DSA client return index and binary version?
	// require.Equal(t, uint32(1), routes.IndexVersion)
	// require.Equal(t, "test", routes.BinaryVersion)
}

func TestChooseCorpusInCtx(t *testing.T) {
	ctx := context.Background()
	ctx = experiments.WithExperiment(ctx, experiments.ForceCorpus, "green")

	searchClusters := helpers.SearchClustersN(t, 1)
	blueShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Blue).ServingHosts[0][0])
	greenShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Green).ServingHosts[0][0])
	greenShard.SearchReturns(generator.BlackbirdResponse(t, 0, 10, 1), nil)
	greenShard.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	yellowShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Yellow).ServingHosts[0][0])

	service := newTestService(
		t,
		routing.Green,
		searchClusters,
		[]*db.Repository{
			{RepoID: 123, OwnerID: 1, OwnerLogin: "test-owner", Name: "test_repo_1", IsPublic: false},
		}...,
	)

	request := generator.QueryServiceRequest(t, "test", 50, 5)
	resp, err := service.Query(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, 0, yellowShard.SearchCallCount())
	require.Equal(t, 0, blueShard.SearchCallCount())
	require.Equal(t, 2, greenShard.SearchCallCount()) // Two calls: original search and then fetch missing content
}

func TestChooseCorpus(t *testing.T) {
	ctx := context.Background()

	searchClusters := helpers.SearchClustersN(t, 1)
	blueShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Blue).ServingHosts[0][0])
	greenShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Green).ServingHosts[0][0])
	yellowShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Yellow).ServingHosts[0][0])
	yellowShard.SearchReturns(generator.BlackbirdResponse(t, 0, 10, 1), nil)
	yellowShard.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)

	service := newTestService(
		t,
		routing.Yellow,
		searchClusters,
		[]*db.Repository{
			{RepoID: 123, OwnerID: 1, OwnerLogin: "test-owner", Name: "test_repo_1", IsPublic: false},
		}...,
	)

	request := generator.QueryServiceRequest(t, "test", 50, 5)
	request.Experiments = map[string]string{"corpus": "yellow"}
	resp, err := service.Query(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, 2, yellowShard.SearchCallCount()) // Two calls: original search and then fetch missing content
	require.Equal(t, 0, blueShard.SearchCallCount())
	require.Equal(t, 0, greenShard.SearchCallCount())
}

func TestChooseCorpusByExperimentId(t *testing.T) {
	ctx := context.Background()

	searchClusters := helpers.SearchClustersN(t, 1)
	blueShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Blue).ServingHosts[0][0])
	blueShard.SearchReturns(generator.BlackbirdResponse(t, 0, 10, 1), nil)
	blueShard.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	greenShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Green).ServingHosts[0][0])
	yellowShard := helpers.FakeShardClient(t, searchClusters.GetServingRoutes(ctx, routing.Yellow).ServingHosts[0][0])

	service := newTestService(
		t,
		routing.Blue,
		searchClusters,
		[]*db.Repository{
			{RepoID: 123, OwnerID: 1, OwnerLogin: "test-owner", Name: "test_repo_1", IsPublic: false},
		}...,
	)

	request := generator.QueryServiceRequest(t, "test", 50, 5)
	request.Experiments = map[string]string{"corpus": "blue"}
	resp, err := service.Query(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, 0, yellowShard.SearchCallCount())
	require.Equal(t, 2, blueShard.SearchCallCount()) // Two calls: original search and then fetch missing content
	require.Equal(t, 0, greenShard.SearchCallCount())
}

func TestSuggestNoSuchRepo(t *testing.T) {
	ctx := context.Background()
	queryStr := "repo:github/nonexisting-repo symbol:main lang"

	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus) // NB: b/c snapshot search picks a random host each time.
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	repos := []*db.Repository{
		{RepoID: 123, OwnerID: 1, OwnerLogin: "test-owner", Name: "test_repo_1", IsPublic: false},
		{RepoID: 234, OwnerID: 1, OwnerLogin: "test-owner", Name: "test_repo_2", IsPublic: false},
	}
	for shardID, shard := range routes.ServingHosts {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchReturns(generator.BlackbirdResponse(t, shardID, 10, 10), nil)
	}

	service := newTestService(t, corpus, searchClusters, repos...)

	req := generator.SuggestServiceRequest(t, queryStr, 50, 10)
	response, err := service.Suggest(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata, "short circuited suggestions should have metadata")

	foundInaccessible := false
	foundUnsatisfiable := false
	for _, err := range response.QueryErrors {
		if err.Type == pb.ErrorType_ERROR_TYPE_MISSING_INACCESSIBLE_REPO_ORG {
			foundInaccessible = true
		} else if err.Type == pb.ErrorType_ERROR_TYPE_SCOPE_UNSATISFIABLE {
			foundUnsatisfiable = true
		}
	}
	require.True(t, foundInaccessible,
		"Expected an error with ERROR_TYPE_MISSING_INACCESSIBLE_REPO_ORG, got: %s", response.String())
	require.False(t, foundUnsatisfiable,
		"Expected not to get unsatisfiable error, got: %s", response.String())

	c := helpers.FakeShardClient(t, routes.ServingHosts[0][0])
	require.Equal(t, 1, c.SearchSnapshotsCallCount()) // We only make a single query to resolve repos and owners during rewrite
	_, r := c.SearchSnapshotsArgsForCall(0)
	node := r.QueryAst.Subqueries[0]
	require.Equal(t, "nwo_github/nonexisting-repo", node.ValueString)
	require.Equal(t, querypb.Domain_DOMAIN_TRAIT, node.Domain)
}

func TestSuggestPathCompletion(t *testing.T) {
	ctx := context.Background()
	queryStr := "repo:test-owner/test_repo_1 hide"

	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus) // NB: b/c snapshot search picks a random host each time
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	repos := []*db.Repository{
		{RepoID: 123, OwnerID: 1, OwnerLogin: "test-owner", Name: "test_repo_1", IsPublic: false},
		{RepoID: 234, OwnerID: 1, OwnerLogin: "test-owner", Name: "test_repo_2", IsPublic: false},
	}
	for shardID, shard := range routes.ServingHosts {
		fake := helpers.FakeShardClientWithRepos(t, shard[0], repos...)
		fake.SearchReturns(generator.BlackbirdResponse(t, shardID, 10, 10), nil)
	}
	service := newTestService(t, corpus, searchClusters, repos...)

	req := generator.SuggestServiceRequest(t, queryStr, 50, 10)
	response, err := service.Suggest(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)

	c := helpers.FakeShardClient(t, routes.ServingHosts[0][0])
	require.Equal(t, 1, c.SearchSnapshotsCallCount())

	_, sr := c.SearchSnapshotsArgsForCall(0)
	// expect an trait:nwo_ query
	node := sr.QueryAst.Subqueries[0]
	require.Equal(t, "nwo_test-owner/test_repo_1", node.ValueString)
	require.Equal(t, querypb.Domain_DOMAIN_TRAIT, node.Domain)

	require.Equal(t, 1, c.SearchCallCount())
	_, r := c.SearchArgsForCall(0)

	// expect one path and one symbol query
	node = r.QueryAst.Subqueries[0].Subqueries[1]
	require.Equal(t, "hide", node.Subqueries[0].ValueString)
	domain := node.Subqueries[0].Domain
	require.True(t, domain == querypb.Domain_DOMAIN_SYMBOLS || domain == querypb.Domain_DOMAIN_PATH)
	require.Equal(t, "hide", node.Subqueries[1].ValueString)
	domain = node.Subqueries[1].Domain
	require.True(t, domain == querypb.Domain_DOMAIN_SYMBOLS || domain == querypb.Domain_DOMAIN_PATH)
}

func Test_QueryExceedsMaxLength(t *testing.T) {
	corpus := helpers.Corpus(t)
	ctx := context.Background()
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	query := strings.Repeat("a", 1001)
	request := generator.QueryServiceRequest(t, string(query), 50, 5)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}
	bbDocs := shardsReturn(t, shards, 3)

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.Query(ctx, request)
	require.EqualError(t, err, "twirp error invalid_argument: query exceeds max length")
	require.Nil(t, response)

	response2, err := service.Suggest(ctx, generator.SuggestServiceRequest(t, string(query), 50, 5))
	require.EqualError(t, err, "twirp error invalid_argument: query exceeds max length")
	require.Nil(t, response2)
}

func Test_QueryMissingRepo(t *testing.T) {
	corpus := helpers.Corpus(t)
	ctx := context.Background()
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	request := generator.QueryServiceRequest(t, "repo:github/blackbird", 50, 5)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	for shardID, shard := range shards {
		bbResp := generator.BlackbirdResponse(t, shardID, 0, 0)
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	service := newTestService(t, corpus, searchClusters)
	response, err := service.Query(ctx, request)
	require.NoError(t, err)
	require.Len(t, response.QueryErrors, 1)
	require.Equal(t, "github/blackbird", response.QueryErrors[0].MissingOrInaccessibleRepoOrgNwo)
}

func TestTextDocumentDefinitionWithBadRequests(t *testing.T) {
	corpus := helpers.Corpus(t)
	ctx := context.Background()
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	for shardID, shard := range shards {
		bbResp := generator.BlackbirdResponse(t, shardID, 0, 0)
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	service := newTestService(t, corpus, searchClusters)
	request := &pb.TextDocumentDefinitionRequest{
		Body: &pb.AlephLocationRequest{
			SymbolName: "",
			Path:       "foo/bar.rb",
			CommitOid:  helpers.RandomOID(t).String(),
			Position: &pb.AlephPosition{
				Line:      1,
				Character: 1,
			},
			RepositoryOwner: "github",
			RepositoryName:  "test",
			Ref:             helpers.RandomOID(t).String(),
			Language:        "Ruby",
			SymbolKind:      entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF,
		},
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
	_, err := service.TextDocumentDefinition(ctx, request)
	require.Errorf(t, err, "empty symbols are not permitted")

	request.Body.SymbolName = "foo bar"
	_, err = service.TextDocumentDefinition(ctx, request)
	require.Errorf(t, err, "symbols with spaces are not permitted")

	request.Body.SymbolName = "foo"
	request.Body.Language = "ATS"
	res, err := service.TextDocumentDefinition(ctx, request)
	require.NoError(t, err)
	require.Empty(t, res.Body.Locations, "should return empty response for invalid languages")
}

func TestTextDocumentDefinition(t *testing.T) {
	corpus := helpers.Corpus(t)
	ctx := context.Background()
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	shardResponses := mockFindDefinitionResponse(t)
	request := &pb.TextDocumentDefinitionRequest{
		Body: &pb.AlephLocationRequest{
			SymbolName: "test_this",
			Path:       "test.rb",
			CommitOid:  helpers.RandomOID(t).String(),
			Position: &pb.AlephPosition{
				Line:      1,
				Character: 1,
			},
			RepositoryOwner: "github",
			RepositoryName:  "test",
			RepositoryId:    123,
			Ref:             helpers.RandomOID(t).String(),
			Language:        "Ruby",
			SymbolKind:      entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF,
		},
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
	for i, shard := range shards {
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(shardResponses[i], nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{
				Entries: []*snapshotpb.SnapshotEntry{
					{
						RepoId:      123,
						CommitSha:   gitaccess.NullObjectID.Bytes(),
						Experiments: map[string]string{"my_exp": "1"},
						Versions: []*snapshotpb.SnapshotEntryVersion{
							{
								OffsetId: 1,
								State:    snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE,
							},
						},
						Nwo:            "github/test",
						OwnerId:        456,
						EntryId:        1,
						NetworkId:      789,
						IsRepoPublic:   true,
						IsRepoArchived: false,
						RepoScore:      10,
					},
				},
			}},
			ServingStatus: generator.Status(t),
		}, nil)
	}
	store := fakeStoreWithReposForCorpus(
		t,
		corpus,
		&db.Repository{
			Name:       "test",
			OwnerLogin: "github",
			RepoID:     123,
			OwnerID:    456,
			IsPublic:   true,
		},
	)

	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		treelights.NewFakeClient(nil, errors.New("bad luck")),
		nil,
		helpers.CopilotClient(t),
	)
	response, err := service.TextDocumentDefinition(ctx, request)
	require.NoError(t, err)
	require.Len(t, response.Body.Locations, 1)
	request.Body.Language = "ATS"
	response, err = service.TextDocumentDefinition(ctx, request)
	require.NoError(t, err)
	require.Empty(t, response.Body.Locations, "should return empty results on unrecognized language")
}

func TestTextDocumentReferences(t *testing.T) {
	corpus := helpers.Corpus(t)
	ctx := context.Background()
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	shardResponses := mockFindReferencesResponse(t)
	request := &pb.TextDocumentReferencesRequest{
		Body: &pb.AlephLocationRequest{
			SymbolName: "test_this",
			Path:       "test.rb",
			CommitOid:  helpers.RandomOID(t).String(),
			Position: &pb.AlephPosition{
				Line:      1,
				Character: 1,
			},
			RepositoryOwner: "github",
			RepositoryName:  "test",
			RepositoryId:    123,
			Ref:             helpers.RandomOID(t).String(),
			Language:        "Ruby",
		},
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
	for i, shard := range shards {
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(shardResponses[i], nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{
				Entries: []*snapshotpb.SnapshotEntry{
					{
						RepoId:      123,
						CommitSha:   gitaccess.NullObjectID.Bytes(),
						Experiments: map[string]string{"my_exp": "1"},
						Versions: []*snapshotpb.SnapshotEntryVersion{
							{
								OffsetId: 1,
								State:    snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE,
							},
						},
						Nwo:            "github/test",
						OwnerId:        456,
						EntryId:        1,
						NetworkId:      789,
						IsRepoPublic:   true,
						IsRepoArchived: false,
						RepoScore:      10,
					},
				},
			}},
			ServingStatus: generator.Status(t),
		}, nil)
	}
	store := fakeStoreWithReposForCorpus(
		t,
		corpus,
		&db.Repository{
			Name:       "test",
			OwnerLogin: "github",
			RepoID:     123,
			OwnerID:    456,
			IsPublic:   true,
		},
	)

	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		treelights.NewFakeClient(nil, errors.New("bad luck")),
		nil,
		helpers.CopilotClient(t),
	)
	response, err := service.TextDocumentReferences(ctx, request)
	require.NoError(t, err)
	require.Len(t, response.Body.Locations, 1)
}

func TestCountingWithNoAccess(t *testing.T) {
	corpus := helpers.Corpus(t)
	shardCount := 32
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, shardCount, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.CountRequest{
		Query: "Test",
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}

	shardResponses := mockCountResponses(t, shardCount)
	for i, shard := range shards {
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(shardResponses[i], nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	store := fakeStoreWithReposForCorpus(
		t,
		corpus,
		&db.Repository{
			Name:       "repo",
			OwnerLogin: "owner",
			RepoID:     123,
			OwnerID:    321,
			IsPublic:   false,
		},
	)
	fakeTreelights := treelights.NewFakeClient(nil, errors.New("bad luck"))

	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)
	response, err := service.Count(context.Background(), request)
	require.NoError(t, err)
	require.Equal(t, 0, len(response.QueryErrors))

	// Should count zero, since we don't have access to the returned repo
	require.Equal(t, 0, int(response.Count))

	// generate new responses
	shardResponses = mockCountResponses(t, shardCount)
	for i, shard := range shards {
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(shardResponses[i], nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}
	service = NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{123}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)
	response, err = service.Count(context.Background(), request)
	require.NoError(t, err)
	require.Equal(t, 0, len(response.QueryErrors))

	// Now we have access to the private repo so it should be counted
	require.Equal(t, 1008, int(response.Count))
}

func TestCountingWithBlobFiltering(t *testing.T) {
	corpus := helpers.Corpus(t)
	store := fakeStoreWithReposForCorpus(
		t,
		corpus,
		&db.Repository{
			Name:       "repo",
			OwnerLogin: "owner",
			RepoID:     123,
			OwnerID:    321,
			IsPublic:   true,
		},
	)

	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}
	brokenOID := helpers.RandomOID(t)
	searchClusters := setupClusterForCountQueries(t, corpus, brokenOID, false)
	fakeTreelights := treelights.NewFakeClient(nil, errors.New("bad luck"))
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	request := &pb.CountRequest{
		Query: "Test",
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
	response, err := service.Count(context.Background(), request)
	require.NoError(t, err)
	require.Equal(t, 0, len(response.QueryErrors))

	// Should count 11, since we have 10 blobs + one broken blob, but blob
	// filtering has not been enabled yet
	require.Equal(t, 11, int(response.Count))

	searchClusters = setupClusterForCountQueries(t, corpus, brokenOID, true)
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}
	gitClient := &gitaccessfakes.FakeClient{}
	gitClient.ResolveBlobsStub = func(ctx context.Context, rbm gitaccess.RepoBlobsMap) error {
		for id := range rbm {
			delete(rbm, id)
		}
		rbm[123] = gitaccess.BlobSet{brokenOID: true}
		return nil
	}

	service = NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{123}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		gitClient,
		helpers.CopilotClient(t),
	)
	response, err = service.Count(context.Background(), request)
	require.NoError(t, err)
	require.Equal(t, 0, len(response.QueryErrors))

	// The broken blob should be filtered, leaving 10 blobs
	require.Equal(t, 10, int(response.Count))
}

func setupClusterForCountQueries(t *testing.T, corpus routing.Corpus, brokenOID gitaccess.ObjectID, blobFiltering bool) *routing.SearchClusters {
	t.Helper()
	hostCount := 32
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, hostCount, corpus)
	if blobFiltering {
		searchClusters = helpers.SearchClustersWithBlobFiltering(t, hostCount, corpus)
	}

	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	s1 := rand.NewSource(4)
	r1 := rand.New(s1)
	shardResponses := []*searchpb.SearchResponse{}
	for i := 0; i < hostCount; i++ {
		shardResponses = append(shardResponses, &searchpb.SearchResponse{
			Documents:     []*searchpb.GitDocumentMatch{},
			Stats:         &searchpb.QueryStats{},
			ServingStatus: generator.Status(t),
		})
	}

	// Broken SHA will be filtered out later
	shardResponses[0].Documents = []*searchpb.GitDocumentMatch{{
		DocSha:  helpers.RandomOID(t).Bytes(),
		BlobSha: brokenOID.Bytes(),
		Locations: []*searchpb.Location{{
			Path:         "/path/to/broken/file.txt",
			RepoId:       uint32(123),
			Nwo:          "a/b",
			CommitSha:    helpers.RandomOID(t).Bytes(),
			OwnerId:      321,
			IsRepoPublic: true,
		}},
		TermMatches:       nil,
		Content:           nil,
		LanguageId:        0,
		TotalLocations:    0,
		ScoringInfo:       nil,
		RetrievalPosition: 0,
		MinDocsToRetrieve: 0,
		TermEmbeddings:    nil,
	}}

	for i := 0; i < 10; i++ {
		shard := r1.Intn(hostCount)
		shardResponses[shard].Documents = append(shardResponses[shard].Documents, &searchpb.GitDocumentMatch{
			DocSha:  helpers.RandomOID(t).Bytes(),
			BlobSha: helpers.RandomOID(t).Bytes(),
			Locations: []*searchpb.Location{{
				Path:         "/path/to/file/test.txt",
				RepoId:       uint32(123),
				Nwo:          "a/b",
				CommitSha:    helpers.RandomOID(t).Bytes(),
				OwnerId:      321,
				IsRepoPublic: true,
			}},
			TermMatches:       nil,
			Content:           nil,
			LanguageId:        0,
			TotalLocations:    0,
			ScoringInfo:       nil,
			RetrievalPosition: 0,
			MinDocsToRetrieve: 0,
			TermEmbeddings:    nil,
		})
	}

	for i, shard := range shards {
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(shardResponses[i], nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	return searchClusters
}

func Test_SearchWithBlobFiltering(t *testing.T) {
	corpus := helpers.Corpus(t)
	repoSpec := generator.RepoSpec{RepoID: 123, OwnerID: 321, Public: true, NumLocsPerDoc: 1, DocsToReturn: 10, DocsWithContent: 10}
	response := generator.BlackbirdResponseFromSpec(t, repoSpec)
	brokenOID := gitaccess.NewObjectIDFromBytes(response.Documents[0].BlobSha)

	setup := func(blobFiltering bool) pb.QueryAPI {
		searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)
		if blobFiltering {
			searchClusters = helpers.SearchClustersWithBlobFiltering(t, 1, corpus)
		}
		routes := searchClusters.GetServingRoutes(context.Background(), corpus)
		shards := routes.ServingHosts
		store := fakeStoreWithReposForCorpus(
			t,
			corpus,
			&db.Repository{
				Name:       "repo",
				OwnerLogin: "owner",
				RepoID:     repoSpec.RepoID,
				OwnerID:    repoSpec.OwnerID,
				IsPublic:   true,
			},
		)

		host := shards[0][0]
		helpers.FakeShardClient(t, host).SearchReturns(response, nil)

		gitClient := &gitaccessfakes.FakeClient{}
		gitClient.ResolveBlobsStub = func(ctx context.Context, rbm gitaccess.RepoBlobsMap) error {
			for id := range rbm {
				delete(rbm, id)
			}
			rbm[repoSpec.RepoID] = gitaccess.BlobSet{brokenOID: true}
			return nil
		}

		store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
			return &db.CorpusState{Corpus: c2}, nil
		}

		return NewService(
			routing.Dotcom,
			helpers.IndexerClusters(t),
			searchClusters,
			store,
			cache.NewInMemory(),
			newTestAuthClient(t, generator.TestActorID, []uint64{uint64(repoSpec.RepoID)}),
			quota.NewMemoryRateEstimator(),
			treelights.NewFakeClient(nil, errors.New("bad luck")),
			gitClient,
			helpers.CopilotClient(t),
		)
	}

	request := &pb.QueryRequest{
		Query: "Test",
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}

	// Setup service without blob filtering
	service := setup(false)

	result, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	require.Equal(t, 10, len(result.Documents))

	// Setup service with blob filtering turned on
	service = setup(true)

	result, err = service.Query(context.Background(), request)
	require.NoError(t, err)
	require.Equal(t, 9, len(result.Documents))
	for _, doc := range result.Documents {
		require.NotEqual(t, gitaccess.NewObjectIDFromBytes(doc.BlobSha), brokenOID)
	}
}

func TestQueryLintingForPromptQueries(t *testing.T) {
	const (
		servingOffset = 10
		epochID       = 1
		cacheHosts    = 2
		numHosts      = 2
	)
	servingTs := time.Now().UTC().UnixMilli()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersExt(t, epoch.EpochModeEmbeddings, numHosts, numHosts, cacheHosts, servingOffset, servingTs, epochID, corpus, false /*no blob filtering*/)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 `prompt:"hello world"`,
		ScopingQuery:          "repo:", // invalid, should trigger scoping rule requirement
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		Experiments:    map[string]string{"prompt_qualifier": "1"},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	for _, shard := range shards {
		bbResp := generator.BlackbirdResponseFromSpec(t, generator.RepoSpec{
			RepoID:          123,
			OwnerID:         321,
			Public:          true,
			NumLocsPerDoc:   2,
			DocsToReturn:    1,
			DocsWithContent: 1,
		})
		bbDocs = append(bbDocs, bbResp.Documents...)
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{
				{Nwo: "github/github", OwnerId: 9919, IsRepoPublic: true, Experiments: map[string]string{"blackbird_enable_code_embedding": "1"}},
			}}},
		}, nil)
	}

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 1, len(response.QueryErrors))
	require.Equal(t, "Semantic searches must be scoped to an organization or repository", response.QueryErrors[0].Message)

	// Correct the scoping query, should fix the query warning
	request.ScopingQuery = "repo:github/github"
	response, err = service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
}

func TestFrontendQueryDuplicateLocations(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	for _, shard := range shards {
		bbResp := generator.BlackbirdResponseFromSpec(t, generator.RepoSpec{
			RepoID:          123,
			OwnerID:         321,
			Public:          true,
			NumLocsPerDoc:   2,
			DocsToReturn:    1,
			DocsWithContent: 1,
		})
		bbDocs = append(bbDocs, bbResp.Documents...)
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	// The first doc will have two locations. Ensure it is ranked first
	bbDocs[0].ScoringInfo.Score = 10.0

	// Remove secondary locations from the second doc and ensure it ranks second
	bbDocs[1].Locations = []*searchpb.Location{
		bbDocs[1].Locations[0],
	}
	bbDocs[1].ScoringInfo.Score = 0.0

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))
	require.Equal(t, 1, len(response.Results[0].DuplicateLocations))
	require.Equal(t, 0, len(response.Results[1].DuplicateLocations))
}

func Test_prepareQueryParseGeyserQuery(t *testing.T) {
	var (
		repoA = types.RepoID(3)
		repoB = types.RepoID(4)
	)
	ctx := context.Background()
	actor := &models.Actor{ID: 1, AccessiblePrivateRepoIDs: types.RepoIDSet{repoA: true, repoB: true}}
	index := helpers.SearchIndexWithRepos(t, &db.Repository{RepoID: repoA, OwnerLogin: "test", Name: "repoA"}, &db.Repository{RepoID: repoB, OwnerLogin: "test", Name: "repoB"})
	service := &queryService{}

	res, err := service.prepareQuery(ctx, "foo bar repo_id:3 repo_id:4", "", nil, actor, nil /* tenant */, index, search.QueryTypeUser, pb.QueryParser_QUERY_PARSER_GEYSER, parser.DisallowPromptQueries{})
	require.NoError(t, err)
	require.Empty(t, res.queryErrors)
	require.False(t, res.fatal)
	expected := parser.And(parser.Content("foo"), parser.Content("bar"), parser.RepoID(3, 4), parser.NonForkRepo(), parser.NonArchivedRepo(), parser.DefaultBranch())
	require.Equal(t, parser.Serialize(expected), parser.Serialize(res.query))
}

func TestGetRepositoryStatus(t *testing.T) {
	searchClusters := helpers.SearchClusters(t)
	indexClusters := helpers.IndexerClusters(t)

	for _, corpus := range routing.Corpora {
		// mock the serving cluster
		routes := searchClusters.GetServingRoutes(context.Background(), corpus)
		hosts := routes.ServingHosts
		for _, shard := range hosts {
			mockResp := &snapshotpb.SearchSnapshotsResponse{
				Snapshots: []*snapshotpb.Snapshot{{
					Entries: []*snapshotpb.SnapshotEntry{
						{
							RepoId:      1234,
							CommitSha:   gitaccess.NullObjectID.Bytes(),
							Experiments: map[string]string{"my_exp": "1"},
							Versions: []*snapshotpb.SnapshotEntryVersion{
								{
									OffsetId: 1,
									State:    snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE,
								},
							},
						},
					},
				}},
			}
			helpers.FakeShardClient(t, shard[0]).SearchSnapshotsReturns(mockResp, nil)

			// Mock the index api too
			host, err := indexClusters.GetCluster(corpus).GetHost()
			require.NoError(t, err)
			helpers.FakeIndexAPI(t, host).SearchSnapshotsReturns(mockResp, nil)
		}
	}

	service := NewService(
		routing.Dotcom,
		indexClusters,
		searchClusters,
		&noop.Store{},
		cache.NewInMemory(),
		nil,
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.GetRepositoryStatus(context.Background(), &pb.GetRepositoryStatusRequest{
		RepositoryIds: []uint32{1234},
	})
	require.NoError(t, err)
	require.Equal(t, len(routing.Corpora), len(response.Corpora))
	require.Equal(t, 1, len(response.Corpora[0].Repositories))
	require.Equal(t, 1, len(response.Corpora[0].Repositories[0].Commits))
	require.Equal(t, 1, len(response.Corpora[0].Repositories[0].Commits[0].Experiments))
}

func newTestAuthClient(t *testing.T, actorID int64, repoIDs []uint64) *auth.Client {
	t.Helper()
	return auth.NewClient(cache.NewInMemory(), auth.NewMockzd(actorID, repoIDs), noop.New())
}

func newFailingTestAuthClient(t *testing.T, err error) *auth.Client {
	t.Helper()
	return auth.NewClient(cache.NewInMemory(), auth.FailingAuthClient{Error: err}, noop.New())
}

// Return a new test service with corpus serving and indexing.
func newTestService(t *testing.T, corpus routing.Corpus, s *routing.SearchClusters, repos ...*db.Repository) pb.QueryAPI {
	store := fakeStoreWithReposForCorpus(t, corpus, repos...)
	repoIDs := []uint64{}
	for _, r := range repos {
		if !r.IsPublic {
			repoIDs = append(repoIDs, uint64(r.RepoID))
		}
	}
	return NewService(
		routing.Dotcom, // Use dotcom stamp, because it has all Corpora
		helpers.IndexerClusters(t),
		s,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, repoIDs),
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)
}

// Returns a store with repos and this corpus indexing and serving; all others not.
func fakeStoreWithReposForCorpus(t *testing.T, corpus routing.Corpus, repos ...*db.Repository) *dbfakes.FakeStore {
	ownersMap := map[uint32]*models.Owner{}
	reposMap := map[types.RepoID]*db.Repository{}
	for _, repo := range repos {
		reposMap[repo.RepoID] = repo
		ownersMap[repo.OwnerID] = &models.Owner{OwnerID: repo.OwnerID, OwnerLogin: repo.OwnerLogin}
	}

	reposByNWOMap := map[types.NWO]*db.Repository{}
	for _, repo := range repos {
		if !types.IsValidRepoNWO(repo.NWO()) {
			repo.Name = fmt.Sprintf("repo-%d", repo.RepoID)
			repo.OwnerLogin = fmt.Sprintf("owner-%d", repo.OwnerID)
		}
		reposByNWOMap[types.NWOFromString(repo.NWO())] = repo
	}

	store := &dbfakes.FakeStore{}
	store.LoadRepositoriesByIDsStub = func(c context.Context, repos map[types.RepoID]*db.Repository) error {
		for id := range repos {
			if r, ok := reposMap[id]; ok {
				repos[id] = r
			}
		}
		return nil
	}
	store.GetRepositoryByNWOStub = func(c context.Context, nwo types.NWO) (*db.Repository, error) {
		for id := range repos {
			if repos[id].NWO() == nwo.String() {
				return repos[id], nil
			}
		}
		return nil, errors.New("no repo")
	}

	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}

	return store
}

// Returns a fake git Client whose `ResolveBlobs` never returns unresolved blobs
func fakeGitClient() gitaccess.Client {
	gitClient := &gitaccessfakes.FakeClient{}
	gitClient.ResolveBlobsReturns(nil)
	return gitClient
}

func successCheck(t *testing.T, shards [][]*routing.SearchHost, expectedDocs int, response *pb.QueryResponse, metas []*pb.ShardMetadata, err error) {
	t.Helper()

	docs := response.Documents

	// basic checks for a successful response
	require.NoError(t, err)
	require.NotNil(t, response, "unexpected nil response")
	require.NotNil(t, response.Metadata)
	require.Empty(t, response.QueryErrors, "unexpected query error %v", response.QueryErrors)
	require.Equal(t, expectedDocs, len(docs), "unexpected number of docs received")
	require.Equal(t, len(shards), len(metas), "unexpected number of shard metas received")

	// Make sure the content for the docs is never empty
	for _, doc := range response.Documents {
		require.NotEmpty(t, doc.Content, "unexpected empty content for doc %v", doc)
		require.Greater(t, len(doc.TermMatches), 0, "expected at least one term match")
	}

	// ensure some standard metadata checks
	for _, meta := range metas {
		require.Empty(t, meta.Error, "unexpected shard error")
		require.NotNil(t, meta.Stats, "unexpected nil shard stats")
	}
}

func incompleteResultsCheck(t *testing.T, shards [][]*routing.SearchHost, expectedDocs int, response *pb.QueryResponse, metas []*pb.ShardMetadata, err error) {
	t.Helper()

	docs := response.Documents

	// basic checks for a successful response
	require.NoError(t, err)
	require.NotNil(t, response, "unexpected nil response")
	require.Equal(t, len(response.QueryErrors), 1)
	require.Equal(t, response.QueryErrors[0].Type, pb.ErrorType_ERROR_TYPE_RESULTS_INCOMPLETE)
	require.Equal(t, expectedDocs, len(docs), "unexpected number of docs received")
	require.Equal(t, len(shards), len(metas), "unexpected number of shard metas received")

	// ensure some standard metadata checks
	for _, meta := range metas {
		require.Empty(t, meta.Error, "unexpected shard error")
		require.NotNil(t, meta.Stats, "unexpected nil shard stats")
	}
}

func verifyDocOrdering(t *testing.T, qsDocs []*pb.GitDocumentMatch, bbDocs []*searchpb.GitDocumentMatch) {
	t.Helper()

	// First make sure that the query service docs themselves are in the right order
	sorted := sort.SliceIsSorted(qsDocs, func(i, j int) bool {
		return qsDocs[i].ScoringInfo.Score > qsDocs[j].ScoringInfo.Score
	})
	require.True(t, sorted, "documents returned from service are not sorted")

	// Sort all the blackbird documents by score and sha
	sort.Slice(bbDocs, func(i, j int) bool {
		if bbDocs[i].ScoringInfo.Score > bbDocs[j].ScoringInfo.Score {
			return true
		}

		if bbDocs[i].ScoringInfo.Score < bbDocs[j].ScoringInfo.Score {
			return false
		}

		return bytes.Compare(bbDocs[i].BlobSha, bbDocs[j].BlobSha) > 0
	})

	// Get all the shas that came back from blackbird and chop them to the length the docs query service
	// is returning
	bbShas := make([]string, 0, len(qsDocs))
	for i := 0; i < len(qsDocs); i++ {
		sha := hex.EncodeToString(bbDocs[i].BlobSha)
		bbShas = append(bbShas, sha)
	}

	// Get the shas of all the docs we are returning from query service
	qsShas := make([]string, 0, len(qsDocs))
	for i := 0; i < len(qsDocs); i++ {
		sha := hex.EncodeToString(qsDocs[i].BlobSha)
		qsShas = append(qsShas, sha)
	}

	// Make sure that the ordering was preserved by query service
	require.Equalf(
		t,
		bbShas,
		qsShas,
		"document order mismatch between blackbird and query service.\n\nExpected:\n%s\n\nGot:\n%s",
		shaAndScoreForBBDoc(bbDocs),
		shaAndScoreForMWDoc(qsDocs),
	)
}

func reposForSpec(specs ...generator.RepoSpec) []*db.Repository {
	repos := []*db.Repository{}
	for _, spec := range specs {
		repos = append(repos, &db.Repository{
			Name:       fmt.Sprintf("repo-%d", spec.RepoID),
			OwnerLogin: fmt.Sprintf("owner-%d", spec.OwnerID),
			RepoID:     spec.RepoID,
			OwnerID:    spec.OwnerID,
			IsPublic:   spec.Public,
		})
	}

	return repos
}

func reposForDocs(docs []*searchpb.GitDocumentMatch) []*db.Repository {
	repos := []*db.Repository{}
	for _, d := range docs {
		for _, l := range d.Locations {
			repo := &db.Repository{
				Name:       fmt.Sprintf("repo-%d", l.RepoId),
				OwnerLogin: fmt.Sprintf("owner-%d", l.OwnerId),
				RepoID:     types.RepoID(l.RepoId),
				OwnerID:    l.OwnerId,
				IsPublic:   l.IsRepoPublic,
			}
			repos = append(repos, repo)
		}
	}
	return repos
}

func shaAndScoreForBBDoc(docs []*searchpb.GitDocumentMatch) string {
	shaScores := []string{}
	for _, doc := range docs {
		shaScores = append(shaScores, fmt.Sprintf("%s=%f", hex.EncodeToString(doc.GetBlobSha()), doc.GetScoringInfo().GetScore()))
	}

	return strings.Join(shaScores, "\n")
}

func shaAndScoreForMWDoc(docs []*pb.GitDocumentMatch) string {
	shaScores := []string{}
	for _, doc := range docs {
		shaScores = append(shaScores, fmt.Sprintf("%s=%f", hex.EncodeToString(doc.GetBlobSha()), doc.GetScoringInfo().GetScore()))
	}

	return strings.Join(shaScores, "\n")
}

func mockCountResponses(t *testing.T, shardCount int) []*searchpb.SearchResponse {
	const seed = 4
	s1 := rand.NewSource(seed)
	r1 := rand.New(s1)
	shardResponses := []*searchpb.SearchResponse{}
	for i := 0; i < shardCount; i++ {
		shardResponses = append(shardResponses, &searchpb.SearchResponse{
			Documents:     []*searchpb.GitDocumentMatch{},
			Stats:         &searchpb.QueryStats{},
			ServingStatus: generator.Status(t),
		})
	}

	for i := 0; i < 1024; i++ {
		data := make([]byte, 20)
		r1.Read(data)

		shard := r1.Intn(shardCount)

		if shardResponses[shard].Documents == nil {
			shardResponses[shard].Documents = []*searchpb.GitDocumentMatch{}
		}
		shardResponses[shard].Documents = append(shardResponses[shard].Documents, &searchpb.GitDocumentMatch{
			DocSha:  data,
			BlobSha: helpers.RandomOID(t).Bytes(),
			Locations: []*searchpb.Location{{
				Path:         "/path/to/file/test.txt",
				RepoId:       uint32(123),
				Nwo:          "a/b",
				CommitSha:    data,
				OwnerId:      321,
				IsRepoPublic: false,
			}},
			TermMatches:       nil,
			Content:           nil,
			LanguageId:        0,
			TotalLocations:    0,
			ScoringInfo:       nil,
			RetrievalPosition: 0,
			MinDocsToRetrieve: 0,
			TermEmbeddings:    nil,
		})
	}
	return shardResponses
}

func mockFindReferencesResponse(t *testing.T) []*searchpb.SearchResponse {
	shardCount := 4
	blobSha, _ := gitaccess.NewObjectIDFromSHA("33cfe11057f84b1ae8d65acd0ddbd28c5db44bfd")
	shardResponses := []*searchpb.SearchResponse{}
	for i := 0; i < shardCount; i++ {
		shardResponses = append(shardResponses, &searchpb.SearchResponse{
			Documents:     []*searchpb.GitDocumentMatch{},
			Stats:         &searchpb.QueryStats{},
			ServingStatus: generator.Status(t),
		})
	}

	shardResponses[0].Documents = []*searchpb.GitDocumentMatch{
		{
			ScoringInfo: &searchpb.ScoringInfo{
				Score: 10,
				MatchedSymbols: []*searchpb.Symbol{
					{
						FullyQualifiedName: "test_this",
						Kind:               entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF,
						IdentStart:         4,
						IdentEnd:           13,
						ExtentStart:        4,
						ExtentEnd:          13,
						Score:              10,
					},
				},
			},
			Content: []byte("def test_this; end"),
			TermMatches: []*searchpb.Range{
				{
					Start: 4,
					End:   13,
				},
			},
			BlobSha:        blobSha.Bytes(),
			LanguageId:     326,
			TotalLocations: 1,
			Locations: []*searchpb.Location{
				{
					Path:         "test.rb",
					RepoId:       123,
					OwnerId:      456,
					CommitSha:    helpers.RandomOID(t).Bytes(),
					RefName:      helpers.RandomOID(t).String(),
					RepoScore:    10,
					IsRepoPublic: true,
					Score:        10,
					NetworkId:    789,
					Nwo:          "github/test",
				},
			},
		},
		{
			ScoringInfo: &searchpb.ScoringInfo{
				Score: 10,
				MatchedSymbols: []*searchpb.Symbol{
					{
						FullyQualifiedName: "test_this",
						Kind:               entities.SymbolKind_SYMBOL_KIND_CALL_REF,
						IdentStart:         4,
						IdentEnd:           13,
						ExtentStart:        0,
						ExtentEnd:          13,
						Score:              10,
					},
				},
			},
			Content: []byte("test_this()"),
			TermMatches: []*searchpb.Range{
				{
					Start: 0,
					End:   9,
				},
			},
			BlobSha:        blobSha.Bytes(),
			LanguageId:     326,
			TotalLocations: 1,
			Locations: []*searchpb.Location{
				{
					Path:         "client.rb",
					RepoId:       123,
					OwnerId:      456,
					CommitSha:    helpers.RandomOID(t).Bytes(),
					RefName:      helpers.RandomOID(t).String(),
					RepoScore:    10,
					IsRepoPublic: true,
					Score:        10,
					NetworkId:    789,
					Nwo:          "github/test",
				},
			},
		},
	}

	return shardResponses
}

func mockFindDefinitionResponse(t *testing.T) []*searchpb.SearchResponse {
	shardCount := 4
	blobSha, _ := gitaccess.NewObjectIDFromSHA("33cfe11057f84b1ae8d65acd0ddbd28c5db44bfd")
	shardResponses := []*searchpb.SearchResponse{}
	for i := 0; i < shardCount; i++ {
		shardResponses = append(shardResponses, &searchpb.SearchResponse{
			Documents:     []*searchpb.GitDocumentMatch{},
			Stats:         &searchpb.QueryStats{},
			ServingStatus: generator.Status(t),
		})
	}

	shardResponses[0].Documents = []*searchpb.GitDocumentMatch{
		{
			ScoringInfo: &searchpb.ScoringInfo{
				Score: 10,
				MatchedSymbols: []*searchpb.Symbol{
					{
						FullyQualifiedName: "test_this",
						Kind:               entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF,
						IdentStart:         4,
						IdentEnd:           13,
						ExtentStart:        4,
						ExtentEnd:          13,
						Score:              10,
					},
				},
			},
			Content: []byte("def test_this; end"),
			TermMatches: []*searchpb.Range{
				{
					Start: 4,
					End:   13,
				},
			},
			BlobSha:        blobSha.Bytes(),
			LanguageId:     326,
			TotalLocations: 1,
			Locations: []*searchpb.Location{
				{
					Path:         "test.rb",
					RepoId:       123,
					OwnerId:      456,
					CommitSha:    helpers.RandomOID(t).Bytes(),
					RefName:      helpers.RandomOID(t).String(),
					RepoScore:    10,
					IsRepoPublic: true,
					Score:        10,
					NetworkId:    789,
					Nwo:          "github/test",
				},
			},
		},
	}

	return shardResponses
}
