package blackbird_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	bbclient "github.com/github/blackbird/crates/client/pkg/blackbird"
	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_ConvertEpochMode(t *testing.T) {
	require.Equal(t, blackbird.ConvertEpochMode(epoch.EpochModeLegacyHybrid), entities.EpochMode_LEGACY_HYBRID)
	require.Equal(t, blackbird.ConvertEpochMode(epoch.EpochModeLexical), entities.EpochMode_LEXICAL)
	require.Equal(t, blackbird.ConvertEpochMode(epoch.EpochModeEmbeddings), entities.EpochMode_EMBEDDINGS)
	require.Equal(t, blackbird.ConvertEpochMode(epoch.EpochModeEmbeddingsGraph), entities.EpochMode_EMBEDDINGS_GRAPH)
	require.Equal(t, blackbird.ConvertEpochMode(epoch.EpochModeHybrid), entities.EpochMode_HYBRID)

	require.Len(t, entities.EpochMode_name, 5, "number of epoch modes in the proto changed")
}

func Test_GetOwner(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersN(t, 1)

	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)

	c := selectCluster(t, searchClusters, store)

	shard, err := c.RandomHost() // should be only one
	require.NoError(t, err)
	helpers.FakeShardClient(t, shard).SearchSnapshotsReturns(
		&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{{Nwo: "github/github", OwnerId: 9919}}}},
		},
		nil)

	owner, err := c.GetOwner(ctx, "github")
	require.NoError(t, err)
	require.NotNil(t, owner)
	require.Equal(t, "github", owner.OwnerLogin)
	require.EqualValues(t, 9919, owner.OwnerID)
	require.Equal(t, 1, helpers.FakeShardClient(t, shard).SearchSnapshotsCallCount())
}

func Test_GetOwnerNotFound(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersN(t, 1)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)
	c := selectCluster(t, searchClusters, store)

	shard, err := c.RandomHost()
	require.NoError(t, err)

	owner, err := c.GetOwner(ctx, "github")
	require.Nil(t, owner)
	require.Nil(t, err)
	require.Equal(t, 1, helpers.FakeShardClient(t, shard).SearchSnapshotsCallCount())
}

func Test_GetOwnerError(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersN(t, 1)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	tErr := errors.New("failure")
	host := routes.RandomHost()
	helpers.FakeShardClient(t, host).SearchSnapshotsReturns(nil, tErr)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)
	c := getCluster(t, searchClusters, store, corpus)

	owner, err := c.GetOwner(ctx, "github")
	require.Nil(t, owner)
	require.EqualError(t, err, tErr.Error())
	require.Equal(t, 1, helpers.FakeShardClient(t, host).SearchSnapshotsCallCount())
}

func Test_GetOwnerInvalidLogin(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersN(t, 1)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)
	c := selectCluster(t, searchClusters, store)

	shard, err := c.RandomHost()
	require.NoError(t, err)

	owner, err := c.GetOwner(ctx, "")
	require.Nil(t, owner)
	require.Nil(t, err)
	require.Equal(t, 1, helpers.FakeShardClient(t, shard).SearchSnapshotsCallCount())
}

func Test_GetRepositoryWithNilActor(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersN(t, 1)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)
	c := getCluster(t, searchClusters, store, corpus)

	shard, err := c.RandomHost()
	require.NoError(t, err)
	helpers.FakeShardClient(t, shard).SearchSnapshotsReturns(
		&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{{Nwo: "github/blackbird", RepoId: 3, OwnerId: 9919}}}},
		},
		nil)

	repo, err := c.GetRepositoryByNWO(ctx, nil, types.NWOFromString("github/blackbird"))
	require.Nil(t, err)
	require.Nil(t, repo)
	require.Equal(t, 1, helpers.FakeShardClient(t, shard).SearchSnapshotsCallCount())
}

func Test_GetRepositoryPrivateWithAccess(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersN(t, 1)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)
	c := getCluster(t, searchClusters, store, corpus)

	shard, err := c.RandomHost() // NB: There is only one host
	require.NoError(t, err)
	helpers.FakeShardClient(t, shard).SearchSnapshotsReturns(
		&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{{Nwo: "github/github", RepoId: 3, OwnerId: 9919}}}},
		},
		nil)

	repo, err := c.GetRepositoryByNWO(ctx, &models.Actor{AccessiblePrivateRepoIDs: types.RepoIDSet{3: true}}, types.NWOFromString("github/github"))
	require.NoError(t, err)
	require.NotNil(t, repo)
	require.Equal(t, 1, helpers.FakeShardClient(t, shard).SearchSnapshotsCallCount())
}

func Test_GetRepositoryPrivateNoAccess(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersN(t, 1)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)
	c := getCluster(t, searchClusters, store, corpus)

	shard, err := c.RandomHost()
	require.NoError(t, err)
	helpers.FakeShardClient(t, shard).SearchSnapshotsReturns(
		&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{{Nwo: "github/github", RepoId: 3, OwnerId: 9919}}}},
		},
		nil)

	repo, err := c.GetRepositoryByNWO(ctx, &models.Actor{}, types.NWOFromString("github/github"))
	require.Nil(t, err)
	require.Nil(t, repo)
	require.Equal(t, 1, helpers.FakeShardClient(t, shard).SearchSnapshotsCallCount())
}

func Test_GetRepositoryPublic(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersN(t, 1)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)
	c := selectCluster(t, searchClusters, store)

	shard, err := c.RandomHost()
	require.NoError(t, err)
	helpers.FakeShardClient(t, shard).SearchSnapshotsReturns(
		&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{{Nwo: "github/styleguide", RepoId: 4, OwnerId: 9919, IsRepoPublic: true}}}},
		},
		nil)

	repo, err := c.GetRepositoryByNWO(ctx, &models.Actor{}, types.NWOFromString("github/styleguide"))
	require.NoError(t, err)
	require.NotNil(t, repo)
	require.Equal(t, "github/styleguide", repo.NWO())
	require.Equal(t, 1, helpers.FakeShardClient(t, shard).SearchSnapshotsCallCount())
}

func Test_ParseServingStatusOnError(t *testing.T) {
	clusters := helpers.SearchClusters(t)
	routes := clusters.GetServingRoutes(context.Background(), routing.Blue)
	shard := routes.ServingHosts[0]
	twerr := twirp.InvalidArgumentError("", "invalid epoch_id 0/shard_id 0 tuple")
	data, jsonErr := json.Marshal(&servingpb.ServingStatus{EpochId: 2})
	require.NoError(t, jsonErr)
	twerr = twerr.WithMeta(bbclient.ServingStatusKey, string(data))
	helpers.FakeShardClient(t, shard[0]).SearchReturns(nil, twerr)

	ctx := context.Background()
	res, err := shard[0].Search(ctx, &searchpb.SearchRequest{})
	require.EqualError(t, err, "twirp error invalid_argument:  invalid epoch_id 0/shard_id 0 tuple")
	require.Nil(t, res)
	require.Equal(t, 1, helpers.FakeShardClient(t, shard[0]).SearchCallCount())
}

func Test_HostsNotServing(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)

	tests := []struct {
		testName                 string
		numHosts                 int
		numHostsServing          int
		numCacheHosts            int
		maxPercentUnavailAllowed float32
		expectedError            string
	}{
		{
			testName:        "no hosts available to serve the query",
			numHosts:        2,
			numHostsServing: 0, // No host are serving
			numCacheHosts:   1,
			expectedError:   "not enough shards available to serve the query: 100% (2 of 2) of shards are unavailable, max allowed: 0%",
		},
		{
			testName:        "not enough hosts available to serve all shards",
			numHosts:        2,
			numHostsServing: 1, // Half the hosts are serving
			numCacheHosts:   1,
			expectedError:   "not enough shards available to serve the query: 50% (1 of 2) of shards are unavailable, max allowed: 0%",
		},
		{
			testName:                 "max allowed",
			numHosts:                 4,
			numHostsServing:          1,
			numCacheHosts:            1,
			maxPercentUnavailAllowed: .5,
			expectedError:            "not enough shards available to serve the query: 75% (3 of 4) of shards are unavailable, max allowed: 50%",
		},
		{
			testName:                 "user queries ok",
			numHosts:                 32,
			numHostsServing:          32,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.UserQueryUnavailableShardsPercent,
			expectedError:            "",
		},
		{
			testName:                 "user queries ok up to 6%",
			numHosts:                 32,
			numHostsServing:          31,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.UserQueryUnavailableShardsPercent,
			expectedError:            "",
		},
		{
			testName:                 "user queries fail over 6%",
			numHosts:                 32,
			numHostsServing:          30,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.UserQueryUnavailableShardsPercent,
			expectedError:            "not enough shards available to serve the query: 6% (2 of 32) of shards are unavailable, max allowed: 6%",
		},
		{
			testName:                 "suggest queries ok",
			numHosts:                 32,
			numHostsServing:          32,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.SuggestUnavailableShardsPercent,
			expectedError:            "",
		},
		{
			testName:                 "suggest queries ok up to 90%",
			numHosts:                 32,
			numHostsServing:          4,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.SuggestUnavailableShardsPercent,
			expectedError:            "",
		},
		{
			testName:                 "suggest queries fail over 90%",
			numHosts:                 32,
			numHostsServing:          3,
			numCacheHosts:            2,
			maxPercentUnavailAllowed: search.SuggestUnavailableShardsPercent,
			expectedError:            "not enough shards available to serve the query: 91% (29 of 32) of shards are unavailable, max allowed: 90%",
		},
		{
			testName:                 "count queries ok",
			numHosts:                 32,
			numHostsServing:          32,
			numCacheHosts:            2,
			maxPercentUnavailAllowed: search.CountUnavailableShardsPercent,
			expectedError:            "",
		},
		{
			testName:                 "count queries ok up to 50%",
			numHosts:                 32,
			numHostsServing:          16,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.CountUnavailableShardsPercent,
			expectedError:            "",
		},
		{
			testName:                 "count queries fail over 50%",
			numHosts:                 32,
			numHostsServing:          15,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.CountUnavailableShardsPercent,
			expectedError:            "not enough shards available to serve the query: 53% (17 of 32) of shards are unavailable, max allowed: 50%",
		},
		{
			testName:                 "prober queries ok",
			numHosts:                 32,
			numHostsServing:          32,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.ProbersUnavailableShardsPercent,
			expectedError:            "",
		},
		{
			testName:                 "prober queries fail if any shard is down",
			numHosts:                 32,
			numHostsServing:          31,
			numCacheHosts:            4,
			maxPercentUnavailAllowed: search.ProbersUnavailableShardsPercent,
			expectedError:            "not enough shards available to serve the query: 3% (1 of 32) of shards are unavailable, max allowed: 0%",
		},
	}
	for _, test := range tests {
		t.Run(test.expectedError, func(t *testing.T) {
			searchClusters := helpers.SearchClustersExt(t, epoch.EpochModeLexical, test.numHosts, test.numHostsServing, test.numCacheHosts, 10, time.Now().UnixMilli(), 1, routing.Blue, false)
			cluster := getCluster(t, searchClusters, store, corpus)

			_, err := cluster.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: test.maxPercentUnavailAllowed})
			if test.expectedError == "" {
				require.NoError(t, err)
			} else {
				require.EqualError(t, err, test.expectedError)
			}
		})
	}
}

func Test_SomeHostsNotServingShards(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)

	tests := []struct {
		testName                 string
		setup                    *helpers.HostShardSetup
		maxPercentUnavailAllowed float32
		expectedError            string
		expectedWarning          string
	}{
		{
			testName: "ok if at least one serving host per shard",
			setup: &helpers.HostShardSetup{
				Shards: [][]*helpers.HostShard{
					{&helpers.HostShard{IsAvail: false}, &helpers.HostShard{IsAvail: true}},
					{&helpers.HostShard{IsAvail: false}, &helpers.HostShard{IsAvail: true}},
				},
			},
			expectedError: "",
		},
		{
			testName: "ok if at least one serving host per shard alt",
			setup: &helpers.HostShardSetup{
				Shards: [][]*helpers.HostShard{
					{&helpers.HostShard{IsAvail: true}, &helpers.HostShard{IsAvail: true}},
					{&helpers.HostShard{IsAvail: false}, &helpers.HostShard{IsAvail: true}},
				},
			},
			expectedError: "",
		},
		{
			testName: "fails if all hosts for all shards fail",
			setup: &helpers.HostShardSetup{
				Shards: [][]*helpers.HostShard{
					{&helpers.HostShard{IsAvail: false}, &helpers.HostShard{IsAvail: false}},
					{&helpers.HostShard{IsAvail: false}, &helpers.HostShard{IsAvail: false}},
				},
			},
			expectedError: "not enough shards responded to serve the query: 100% (2 of 2) of shards are unresponsive, max allowed: 0%: testing: host not available",
		},
		{
			testName: "warns if all hosts for one shard fail",
			setup: &helpers.HostShardSetup{
				Shards: [][]*helpers.HostShard{
					{&helpers.HostShard{IsAvail: false}, &helpers.HostShard{IsAvail: false}},
					{&helpers.HostShard{IsAvail: true}, &helpers.HostShard{IsAvail: true}},
					{&helpers.HostShard{IsAvail: true}, &helpers.HostShard{IsAvail: true}},
				},
			},
			maxPercentUnavailAllowed: .50,
			expectedError:            "",
			expectedWarning:          "Results are incomplete due to an internal error, please retry your query.",
		},
		{
			testName: "errors if all hosts for more than one shards fail",
			setup: &helpers.HostShardSetup{
				Shards: [][]*helpers.HostShard{
					{&helpers.HostShard{IsAvail: false}, &helpers.HostShard{IsAvail: false}},
					{&helpers.HostShard{IsAvail: false}, &helpers.HostShard{IsAvail: false}},
					{&helpers.HostShard{IsAvail: true}, &helpers.HostShard{IsAvail: true}},
				},
			},
			maxPercentUnavailAllowed: .50,
			expectedError:            "not enough shards responded to serve the query: 67% (2 of 3) of shards are unresponsive, max allowed: 50%: testing: host not available",
		},
	}
	for _, test := range tests {
		t.Run(test.testName, func(t *testing.T) {
			layout := helpers.CorpusLayoutExt(t, corpus, test.setup)
			cluster := getCluster(t, layout, store, corpus)

			res, err := cluster.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: test.maxPercentUnavailAllowed})
			if test.expectedError == "" {
				require.NoError(t, err)
				if test.expectedWarning != "" {
					require.NotNil(t, res)
					require.Len(t, res.QueryErrors, 1)
					require.Equal(t, test.expectedWarning, res.QueryErrors[0].Message)
				}
			} else {
				require.EqualError(t, err, test.expectedError, "%v", res)
			}
		})
	}
}

func TestCountFailure(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)

	numHosts := 2
	clients := map[routing.Corpus]bbclient.Client{}
	hosts := make([][]*bbclient.IndexHost, numHosts)
	for i := 0; i < numHosts; i++ {
		hostname := fmt.Sprintf("shard-%s-%d", corpus.String(), i)
		client := &mocks.FakeSearchAPI{}
		client.SearchReturns(nil, twirp.InternalError("error"))
		hosts[i] = []*bbclient.IndexHost{{Hostname: hostname, SearchClient: client}}
	}
	client := &mocks.FakeBlackbirdClient{}
	client.RoutesReturns(bbclient.Routes{Hosts: hosts})
	clients[corpus] = client
	clusterLayout := routing.NewSearchClusters(clients)

	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus}, nil)
	c := getCluster(t, clusterLayout, store, corpus)

	res, err := c.Count(ctx, &querypb.Query{}, search.BuildFECountQueryContext(models.NewAnonymousActor(), 1*time.Second, []types.RepoID{}, ""))
	require.NoError(t, err)
	require.NotNil(t, res.Metadata)
	require.Len(t, res.QueryErrors, 1)
	require.Equal(t, res.QueryErrors[0].Message, "Shards failed to respond to count request")
}

func Test_ClusterSelectionDotcomEmbeddings(t *testing.T) {
	const (
		servingOffset = 10
		epochID       = 1
		cacheHosts    = 2
		numHosts      = 1
	)
	servingTs := time.Now().UTC().UnixMilli()
	stamp := routing.Dotcom
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	for _, cap := range []epoch.EpochFeatures{epoch.EpochFeaturesEmbeddings} {
		store := &dbfakes.FakeStore{}
		store.GetCorpusStateStub = func(ctx context.Context, c routing.Corpus) (*db.CorpusState, error) {
			return &db.CorpusState{Corpus: c}, nil
		}
		// without any embeddings clusters, we can't serve these queries
		searchClusters := helpers.SearchClustersExt(t, epoch.EpochModeLexical, numHosts, numHosts, cacheHosts, servingOffset, servingTs, epochID, corpus, false /*no blob filtering*/)
		c, err := blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.EqualError(t, err, "could not find a serving corpus")
		require.Nil(t, c)

		// Everyone is in embeddings mode (required for this test, since we're doing embeddings queries)
		searchClusters = helpers.SearchClustersExt(t, epoch.EpochModeEmbeddings, numHosts, numHosts, cacheHosts, servingOffset, servingTs, epochID, corpus, false /*no blob filtering*/)
		c, err = blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.False(t, c.CanSendShadowTraffic())

		// Enable serving on the other corpora which allows shadow traffic to be directed at them.
		otherHosts := []*mocks.FakeSearchAPI{}
		otherClients := []*mocks.FakeBlackbirdClient{}
		for _, c := range routing.GetOtherCorpora(corpus, stamp) {
			client := searchClusters.ClientForCorpus(c).(*mocks.FakeBlackbirdClient)
			client.IsServingReturns(true)
			client.HealthScoreReturns(10.0) // Relatively low health score
			otherClients = append(otherClients, client)
			host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
			otherHosts = append(otherHosts, host)
		}
		// Give this cluster a high health score
		client := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
		client.HealthScoreReturns(95.0)
		c, err = blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.True(t, c.CanSendShadowTraffic())
		require.Equal(t, c.ClusterName(), corpus.ClusterName()) // NB: Should select the one with the highest score.

		// Issue a search (zero percent shadow traffic)
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
		require.Equal(t, 1, host.SearchCallCount())
		for _, h := range otherHosts {
			require.Equal(t, 0, h.SearchCallCount()) // NB: not really a valid assert b/c if it did get called it would be on a go routine.
		}

		// Issue a search (100% shadow traffic to the other clusters)
		for _, c := range otherClients {
			c.ShadowTrafficPercentReturns(1.0)
		}
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		require.Equal(t, 2, host.SearchCallCount()) // One more call to the primarty
		for _, h := range otherHosts {
			// One call to each secondary (but on a go routine)
			require.Eventually(t, func() bool { return h.SearchCallCount() == 1 }, 20*time.Millisecond, 2*time.Millisecond)
		}

		// Now give a different cluster a higher score (and it should be selected)
		other := routing.GetOtherCorpora(corpus, stamp)[0]
		otherClient := searchClusters.ClientForCorpus(other).(*mocks.FakeBlackbirdClient)
		otherClient.HealthScoreReturns(96.0)
		c, err = blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.Equal(t, c.ClusterName(), other.ClusterName())

		// Now search again (traffic goes to this new primary cluster)
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		host = otherClient.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
		require.Equal(t, 2, host.SearchCallCount()) // one more call to the new primary
	}
}

func Test_ClusterSelectionDotcom(t *testing.T) {
	stamp := routing.Dotcom
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	for _, cap := range []epoch.EpochFeatures{epoch.EpochFeaturesLexical, epoch.EpochFeaturesBM25 /*, epoch.EpochFeaturesEmbeddings*/} {
		searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)
		store := &dbfakes.FakeStore{}
		store.GetCorpusStateStub = func(ctx context.Context, c routing.Corpus) (*db.CorpusState, error) {
			return &db.CorpusState{Corpus: c}, nil
		}
		c, err := blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.False(t, c.CanSendShadowTraffic())

		// Enable serving on the other corpora which allows shadow traffic to be directed at them.
		otherHosts := []*mocks.FakeSearchAPI{}
		otherClients := []*mocks.FakeBlackbirdClient{}
		for _, c := range routing.GetOtherCorpora(corpus, stamp) {
			client := searchClusters.ClientForCorpus(c).(*mocks.FakeBlackbirdClient)
			client.IsServingReturns(true)
			// client.EpochModeReturns(entities.EpochMode_HYBRID)
			client.HealthScoreReturns(10.0) // Relatively low health score
			otherClients = append(otherClients, client)
			host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
			otherHosts = append(otherHosts, host)
		}
		// Give this cluster a high health score
		client := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
		client.HealthScoreReturns(95.0)
		c, err = blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.True(t, c.CanSendShadowTraffic())
		require.Equal(t, c.ClusterName(), corpus.ClusterName()) // NB: Should select the one with the highest score.

		// Issue a search (zero percent shadow traffic)
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
		require.Equal(t, 1, host.SearchCallCount())
		for _, h := range otherHosts {
			require.Equal(t, 0, h.SearchCallCount()) // NB: not really a valid assert b/c if it did get called it would be on a go routine.
		}

		// Issue a search (100% shadow traffic to the other clusters)
		for _, c := range otherClients {
			c.ShadowTrafficPercentReturns(1.0)
		}
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		require.Equal(t, 2, host.SearchCallCount()) // One more call to the primarty
		for _, h := range otherHosts {
			// One call to each secondary (but on a go routine)
			require.Eventually(t, func() bool { return h.SearchCallCount() == 1 }, 20*time.Millisecond, 2*time.Millisecond)
		}

		// Now give a different cluster a higher score (and it should be selected)
		other := routing.GetOtherCorpora(corpus, stamp)[0]
		otherClient := searchClusters.ClientForCorpus(other).(*mocks.FakeBlackbirdClient)
		otherClient.HealthScoreReturns(96.0)
		c, err = blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.Equal(t, c.ClusterName(), other.ClusterName())

		// Now search again (traffic goes to this new primary cluster)
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		host = otherClient.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
		require.Equal(t, 2, host.SearchCallCount()) // one more call to the new primary
	}
}

func Test_ClusterSelectionProxima(t *testing.T) {
	stamp := routing.StaffWUS201
	ctx := context.Background()
	corpus := helpers.ProximaCorpus(t)

	for _, cap := range []epoch.EpochFeatures{epoch.EpochFeaturesLexical, epoch.EpochFeaturesBM25, epoch.EpochFeaturesEmbeddings} {
		searchClusters := helpers.SearchClustersExt(t, epoch.EpochModeHybrid, 1, 1, 2, 10, time.Now().UTC().UnixMilli(), 1, corpus, false /*no blob filtering*/)
		for _, c := range routing.GetOtherCorpora(corpus, stamp) {
			client := searchClusters.ClientForCorpus(c).(*mocks.FakeBlackbirdClient)
			// we only run hybrid in proxima
			client.EpochInfoReturns(bbclient.EpochInfo{EpochID: 1, EpochMode: bbclient.EpochMode(epoch.EpochModeLegacyHybrid), NumShards: 1})
		}
		store := &dbfakes.FakeStore{}
		store.GetCorpusStateStub = func(ctx context.Context, c routing.Corpus) (*db.CorpusState, error) {
			return &db.CorpusState{Corpus: c}, nil
		}
		c, err := blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.False(t, c.CanSendShadowTraffic())

		// Enable serving on the other corpora which allows shadow traffic to be directed at them.
		otherHosts := []*mocks.FakeSearchAPI{}
		otherClients := []*mocks.FakeBlackbirdClient{}
		for _, c := range routing.GetOtherCorpora(corpus, stamp) {
			client := searchClusters.ClientForCorpus(c).(*mocks.FakeBlackbirdClient)
			client.IsServingReturns(true)
			client.HealthScoreReturns(10.0) // Relatively low health score
			otherClients = append(otherClients, client)
			host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
			otherHosts = append(otherHosts, host)
		}
		// Give this cluster a high health score
		client := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
		client.HealthScoreReturns(95.0)
		c, err = blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.True(t, c.CanSendShadowTraffic())
		require.Equal(t, c.ClusterName(), corpus.ClusterName()) // NB: Should select the one with the highest score.

		// Issue a search (zero percent shadow traffic)
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
		require.Equal(t, 1, host.SearchCallCount())
		for _, h := range otherHosts {
			require.Equal(t, 0, h.SearchCallCount()) // NB: not really a valid assert b/c if it did get called it would be on a go routine.
		}

		// Issue a search (100% shadow traffic to the other clusters)
		for _, c := range otherClients {
			c.ShadowTrafficPercentReturns(1.0)
		}
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		require.Equal(t, 2, host.SearchCallCount()) // One more call to the primarty
		for _, h := range otherHosts {
			// One call to each secondary (but on a go routine)
			require.Eventually(t, func() bool { return h.SearchCallCount() == 1 }, 20*time.Millisecond, 2*time.Millisecond)
		}

		// Now give a different cluster a higher score (and it should be selected)
		other := routing.GetOtherCorpora(corpus, stamp)[0]
		otherClient := searchClusters.ClientForCorpus(other).(*mocks.FakeBlackbirdClient)
		otherClient.HealthScoreReturns(96.0)
		c, err = blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, cap, stamp)
		require.NoError(t, err)
		require.Equal(t, c.ClusterName(), other.ClusterName())

		// Now search again (traffic goes to this new primary cluster)
		_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
		require.NoError(t, err)
		host = otherClient.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
		require.Equal(t, 2, host.SearchCallCount()) // one more call to the new primary
	}
}

func Test_NonServingShadowTraffic(t *testing.T) {
	// todo: test the other stamps
	stamp := routing.Dotcom

	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(ctx context.Context, c routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c}, nil
	}
	c, err := blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, epoch.EpochFeaturesLexical, stamp)
	require.NoError(t, err)
	require.False(t, c.CanSendShadowTraffic())

	// The other clusters do not have serving enabled, but have shadow traffic configured.
	otherHosts := []*mocks.FakeSearchAPI{}
	for _, c := range routing.GetOtherCorpora(corpus, stamp) {
		client := searchClusters.ClientForCorpus(c).(*mocks.FakeBlackbirdClient)
		client.HealthScoreReturns(10.0)         // Relatively low health score
		client.ShadowTrafficPercentReturns(1.0) // 100% shadow traffic
		host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
		otherHosts = append(otherHosts, host)
	}
	// Give the primary cluster a high health score
	client := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	client.HealthScoreReturns(95.0)
	c, err = blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, epoch.EpochFeaturesLexical, stamp)
	require.NoError(t, err)
	require.Equal(t, c.ClusterName(), corpus.ClusterName()) // NB: Should select the one with the highest score.

	// Issue a search
	_, err = c.Search(ctx, &querypb.Query{}, &search.QueryContext{MaxPercentUnavailableShards: 0.0, Actor: models.NewAnonymousActor()})
	require.NoError(t, err)
	host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
	require.Equal(t, 1, host.SearchCallCount())
	for _, h := range otherHosts {
		// One call to each (but on a go routine)
		require.Eventually(t, func() bool { return h.SearchCallCount() == 1 }, 20*time.Millisecond, 2*time.Millisecond)
	}
}

func Test_Capabilities(t *testing.T) {
	tests := []struct {
		feature    epoch.EpochFeatures
		embeddings bool
		lexical    bool
		hybrid     bool
	}{
		{feature: epoch.EpochFeaturesLexical, embeddings: false, lexical: true, hybrid: true},
		{feature: epoch.EpochFeaturesBM25, embeddings: false, lexical: true, hybrid: true},
		{feature: epoch.EpochFeaturesEmbeddings, embeddings: true, lexical: false, hybrid: true},
	}
	for _, test := range tests {
		t.Run(fmt.Sprintf("%s supported by", test.feature), func(t *testing.T) {
			require.Equal(t, test.feature.SupportedBy(epoch.EpochModeEmbeddings), test.embeddings, "EMBEDDINGS unexpected result: feature=%s", test.feature)
			require.Equal(t, test.feature.SupportedBy(epoch.EpochModeLexical), test.lexical, "LEXICAL unexpected result: feature=%s", test.feature)
			require.Equal(t, test.feature.SupportedBy(epoch.EpochModeLegacyHybrid), test.hybrid, "LEGACY_HYBRID unexpected result: feature=%s", test.feature)
			require.Equal(t, test.feature.SupportedBy(epoch.EpochModeHybrid), test.hybrid, "HYBRID unexpected result: feature=%s", test.feature)
		})
	}
}

func getCluster(t *testing.T, searchClusters *routing.SearchClusters, store db.Store, corpus routing.Corpus) *blackbird.Cluster {
	t.Helper()
	ctx := context.Background()
	c, err := blackbird.GetCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, corpus)
	require.NoError(t, err)
	return c
}

func selectCluster(t *testing.T, searchClusters *routing.SearchClusters, store db.Store) *blackbird.Cluster {
	t.Helper()
	ctx := context.Background()
	c, err := blackbird.AutoSelectCluster(ctx, searchClusters, store, nil /*TODO: pager cache*/, nil, types.AnyEpoch, epoch.EpochFeaturesLexical, routing.Dotcom)
	require.NoError(t, err)
	return c
}
