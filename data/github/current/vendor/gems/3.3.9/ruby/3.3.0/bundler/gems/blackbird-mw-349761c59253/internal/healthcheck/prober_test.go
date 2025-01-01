package healthcheck

import (
	"context"
	"errors"
	"fmt"
	"math"
	"testing"
	"time"

	bbclient "github.com/github/blackbird/crates/client/pkg/blackbird"
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
	client.EpochModeReturns(bbclient.EpochMode(epoch.EpochModeLexical))

	idxHost := helpers.FakeShardClient(t, routes.ServingHosts[0][0])
	setupSnapSearch(t, idxHost)

	res := generator.BlackbirdResponse(t, 0, 1, 1)
	idxHost.SearchReturns(res, nil)

	repos := map[types.RepoID]*db.Repository{}
	for _, d := range res.Documents {
		for _, l := range d.Locations {
			rid := types.RepoID(l.RepoId)
			repos[rid] = &db.Repository{RepoID: rid, IsPublic: l.IsRepoPublic}
		}
	}

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
	client.EpochModeReturns(bbclient.EpochMode(epoch.EpochModeLexical))

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

// Each exemplar issues two queries; 1. A direct snapshot search to verify that the repo exists 2. Via regular query path (e.g. during query rewriting)
// an NWO query. The following loop setups up snapshot searches for each fo those calls per exemplar. It's possible that an exemplar may not have a  repo
// associated with it, therefore; we only increment the snapSearchIdx when an exemplar is repo scoped. Key with this setup is that the the exact call number
// must match the exemplar being executed, if that's off then the test will be thrown off. Therefore, it's important that the cluster layout only contains
// a single host otherwise we don't know what call will end up at which host and the setup no longer works.
func setupSnapSearch(t *testing.T, fake *mocks.FakeSearchAPI) {
	t.Helper()

	var snapSearchIdx int
	for _, exemplar := range exemplars[routing.Dotcom][epoch.EpochModeLexical] {
		for repoID, nwo := range exemplar.repos {
			// First query is direct snapshot search
			fake.SearchSnapshotsReturnsOnCall(snapSearchIdx, &snapshotpb.SearchSnapshotsResponse{
				Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{{RepoId: uint32(repoID), Nwo: nwo}}}},
			}, nil)

			// Next query comes in via query rewriting so increment snapSearchIdx
			snapSearchIdx++
			fake.SearchSnapshotsReturnsOnCall(snapSearchIdx, &snapshotpb.SearchSnapshotsResponse{
				Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{{RepoId: uint32(repoID), Nwo: nwo}}}},
			}, nil)

			// Increment again for the subsequent repo or exemplar.
			snapSearchIdx++
		}
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
