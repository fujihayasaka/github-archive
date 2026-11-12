package query

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/gitaccess/gitaccessfakes"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/types"
)

func TestEpochs(t *testing.T) {
	corpus := helpers.Corpus(t)
	ctx := context.Background()

	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	shards := routes.ServingHosts

	// Setup related to repo scoped queries
	repos := []*db.Repository{
		{RepoID: 123, OwnerID: 1, OwnerLogin: "test-owner", Name: "test_repo_1", IsPublic: false},
	}

	// Create a request with accessible repo ids
	searchStr := fmt.Sprintf("test repo_id:%d", repos[0].RepoID)
	request := generator.QueryServiceRequest(t, searchStr, 50, 10)

	// Fake store to return state of the repositories
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2, EpochID: 1}, nil
	}
	store.LoadRepositoriesByIDsStub = func(c context.Context, m map[types.RepoID]*db.Repository) error {
		for _, repo := range repos {
			if _, ok := m[repo.RepoID]; ok {
				m[repo.RepoID] = repo
			}
		}
		return nil
	}

	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{uint64(repos[0].RepoID)}),
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		&gitaccessfakes.FakeClient{},
		helpers.CopilotClient(t),
	)

	for shardID, shard := range shards {
		fake := helpers.FakeShardClientWithRepos(t, shard[0], repos...)
		fake.SearchReturns(generator.BlackbirdResponse(t, shardID, 10, 10), nil)
	}

	resp, err := service.Query(ctx, request)

	require.NoError(t, err)
	require.NotNil(t, resp)

	for _, shard := range shards {
		_, req := helpers.FakeShardClient(t, shard[0]).SearchArgsForCall(0)
		require.EqualValues(t, 1, req.EpochId)
	}
}
