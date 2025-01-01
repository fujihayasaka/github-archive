package healthcheck

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"testing"
	"time"

	bbclient "github.com/github/blackbird/crates/client/pkg/blackbird"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/github/githubfakes"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_exemplarSearchesAllSuccessful(t *testing.T) {
	ctx := context.Background()
	searchClusters := helpers.SearchClustersN(t, 1)
	indexerClusters := helpers.IndexerClusters(t)
	corpus := helpers.Corpus(t)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	client := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	client.EpochInfoReturns(bbclient.EpochInfo{EpochID: 1, EpochMode: bbclient.EpochMode(epoch.EpochModeLexical), NumShards: 1})

	idxHost := helpers.FakeShardClient(t, routes.ServingHosts[0][0])
	setupSnapSearch(t, idxHost)

	res := generator.BlackbirdResponse(t, 0, 1, 1)
	idxHost.SearchReturns(res, nil)

	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}

	githubClient := &githubfakes.FakeInternalAPIClient{}
	repoPublisher := repo.NewPublisher(&mocks.FakeSyncProducer{}, 1)
	prober := NewProber(store, cache.NewInMemory(), nil, routing.Dotcom, searchClusters, indexerClusters, &mocks.FakeSaramaClient{}, githubClient, repoPublisher, nil /* copilotClient */, helpers.MockDelayedTimestampReader(t))
	err := prober.runExemplarQueries(ctx, corpus)
	require.NoError(t, err)
}

func Test_exemplarSearchesAllFailures(t *testing.T) {
	ctx := context.Background()
	searchClusters := helpers.SearchClustersN(t, 1)
	indexerClusters := helpers.IndexerClusters(t)
	corpus := helpers.Corpus(t)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	idxHost := helpers.FakeShardClient(t, routes.ServingHosts[0][0])
	client := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	client.EpochInfoReturns(bbclient.EpochInfo{EpochID: 1, EpochMode: bbclient.EpochMode(epoch.EpochModeLexical), NumShards: 1})

	setupSnapSearch(t, idxHost)
	idxHost.SearchReturns(nil, errors.New("search failure"))

	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}

	githubClient := &githubfakes.FakeInternalAPIClient{}
	repoPublisher := repo.NewPublisher(&mocks.FakeSyncProducer{}, 1)
	prober := NewProber(store, cache.NewInMemory(), nil, routing.Dotcom, searchClusters, indexerClusters, &mocks.FakeSaramaClient{}, githubClient, repoPublisher, nil /* copilotClient */, helpers.MockDelayedTimestampReader(t))
	err := prober.runExemplarQueries(ctx, corpus)
	require.EqualError(t, err, "not enough shards responded to serve the query: 100% (1 of 1) of shards are unresponsive, max allowed: 0%: search failure")
}

// Each exemplar issues two queries:
//
// 1. A direct snapshot search to verify that the repo exists.
// 2. Via regular query path (e.g. during query rewriting) an NWO query.
//
// This method stubs snapshot searches for these types of calls. It's possible
// that an exemplar may not have a repo associated with it. In these cases, an
// empty search result will be returned.
func setupSnapSearch(t *testing.T, fake *mocks.FakeSearchAPI) {
	t.Helper()

	repos := map[types.RepoID]string{}
	for _, exemplars := range exemplars[routing.Dotcom] {
		for _, exemplar := range exemplars {
			for repoID, nwo := range exemplar.repos {
				if priorNWO, ok := repos[repoID]; ok && priorNWO != nwo {
					t.Fatalf("exemplar misconfiguration: same repo ID has different NWOs: prior NWO: %s, nwo: %s", priorNWO, nwo)
				}

				repos[repoID] = nwo
			}
		}
	}

	getRepoIDFromLookupQuery := func(req *snapshotpb.SearchSnapshotsRequest) int32 {
		if req.QueryAst.Kind == querypb.QueryKind_QUERY_KIND_QUALIFIER &&
			req.QueryAst.Domain == querypb.Domain_DOMAIN_REPO_ID &&
			len(req.QueryAst.ValueInt) == 1 {
			return req.QueryAst.ValueInt[0]
		}

		return 0
	}

	getRepoIDFromRewriteQuery := func(req *snapshotpb.SearchSnapshotsRequest) int32 {
		if req.QueryAst.Kind == querypb.QueryKind_QUERY_KIND_OR &&
			len(req.QueryAst.Subqueries) == 1 &&
			req.QueryAst.Subqueries[0].Kind == querypb.QueryKind_QUERY_KIND_QUALIFIER &&
			req.QueryAst.Subqueries[0].Domain == querypb.Domain_DOMAIN_TRAIT &&
			strings.HasPrefix(req.QueryAst.Subqueries[0].ValueString, "nwo_") {

			queryNWO, _ := strings.CutPrefix(req.QueryAst.Subqueries[0].ValueString, "nwo_")
			for repoID, nwo := range repos {
				if queryNWO == nwo {
					return repoID.ToInt32()
				}
			}
		}

		return 0
	}

	fake.SearchSnapshotsStub = func(ctx context.Context, req *snapshotpb.SearchSnapshotsRequest) (*snapshotpb.SearchSnapshotsResponse, error) {
		repoID := getRepoIDFromLookupQuery(req)
		if repoID == 0 {
			repoID = getRepoIDFromRewriteQuery(req)
		}

		if repoID == 0 {
			return &snapshotpb.SearchSnapshotsResponse{}, nil
		}

		nwo, ok := repos[types.RepoID(repoID)]
		if !ok {
			t.Fatalf("exemplar misconfiguration: repo ID %d has no NWO", repoID)

		}
		return &snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{
				{
					Entries: []*snapshotpb.SnapshotEntry{
						{
							RepoId: uint32(repoID),
							Nwo:    nwo,
						},
					},
				},
			},
		}, nil
	}
}

func Test_pauseDuration(t *testing.T) {
	var tests = []struct {
		hashValue              uint64
		nextHashValue          uint64
		expectedTargetDuration time.Duration
	}{
		{
			hashValue:              0,
			nextHashValue:          math.MaxUint64 / 2,
			expectedTargetDuration: 12 * time.Hour,
		},
		{
			hashValue:              0,
			nextHashValue:          uint64(math.MaxUint64 / 2),
			expectedTargetDuration: 12 * time.Hour,
		},
		{
			hashValue:              0,
			nextHashValue:          uint64(math.MaxUint64 / 3),
			expectedTargetDuration: 8 * time.Hour,
		},
		{
			hashValue:              0,
			nextHashValue:          math.MaxUint64,
			expectedTargetDuration: 24 * time.Hour,
		},
		{
			hashValue:              uint64(2 * (math.MaxUint64 / 3)),
			nextHashValue:          0,
			expectedTargetDuration: 8 * time.Hour,
		},
		{
			hashValue:              uint64(2 * (math.MaxUint64 / 3)),
			nextHashValue:          math.MaxUint64 / 3,
			expectedTargetDuration: 16 * time.Hour,
		},
	}

	for _, test := range tests {
		t.Run(fmt.Sprintf("hash-%d-nexthash-%d-duration-%s", test.hashValue, test.nextHashValue, test.expectedTargetDuration), func(t *testing.T) {
			require.Equal(t, test.expectedTargetDuration, targetDuration(test.hashValue, test.nextHashValue))
		})
	}
}

func Test_SystemHealth(t *testing.T) {
	tests := []struct {
		name           string
		states         []clusterHealthState
		expectedStatus string
	}{
		{
			name:           "ok (hybrid and embeddings)",
			expectedStatus: "healthy",
			states: []clusterHealthState{
				{healthState: HealthStateValid, epochMode: epoch.EpochModeLegacyHybrid},
				{healthState: HealthStateValid, epochMode: epoch.EpochModeEmbeddings},
			},
		},
		{
			name:           "ok (lexical and embeddings)",
			expectedStatus: "healthy",
			states: []clusterHealthState{
				{healthState: HealthStateValid, epochMode: epoch.EpochModeLexical},
				{healthState: HealthStateValid, epochMode: epoch.EpochModeEmbeddings},
			},
		},
		{
			name:           "ok (hybrid only)",
			expectedStatus: "healthy",
			states: []clusterHealthState{
				{healthState: HealthStateValid, epochMode: epoch.EpochModeLegacyHybrid},
			},
		},
		{
			name:           "lexical only",
			expectedStatus: "unhealthy",
			states: []clusterHealthState{
				{healthState: HealthStateValid, epochMode: epoch.EpochModeLexical},
			},
		},
		{
			name:           "embeddings only",
			expectedStatus: "unhealthy",
			states: []clusterHealthState{
				{healthState: HealthStateValid, epochMode: epoch.EpochModeEmbeddings},
			},
		},
		{
			name:           "no clusters",
			expectedStatus: "unhealthy",
		},
		{
			name:           "invalid clusters",
			expectedStatus: "unhealthy",
			states: []clusterHealthState{
				{healthState: HealthStateNotServing, epochMode: epoch.EpochModeLegacyHybrid},
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			require.Equal(t, test.expectedStatus, overallSystemHealth(test.states))
		})
	}
}
