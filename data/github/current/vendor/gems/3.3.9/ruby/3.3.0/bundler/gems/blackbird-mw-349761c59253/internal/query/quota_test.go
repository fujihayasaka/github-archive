package query

import (
	"context"
	"sync"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/experiments"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/treelights"

	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
)

const (
	// Maximum elapsed wall-clock time for a single query
	queryTimeoutSeconds float64 = 60.0

	// Any very high cost for a single query. The maximum cost we expect to
	// see is (nShards * queryTimeoutSeconds * 1000); as of this writing
	// we've never seen an actual query cost more than 50% of that.
	// This number is 20%.
	maxCost float32 = float32(32*queryTimeoutSeconds*1000) * 0.20

	// A high but reasonable cost for a query. We rarely see user queries
	// that cost this much, but expensive regexes come close.
	highCost float32 = 4_000.0
)

func quotaTestSetup(t *testing.T, cost float32, cacheActor bool) (context.Context, pb.QueryAPI, [][]*routing.SearchHost, *quota.MemoryRateEstimator) {
	corpus := helpers.Corpus(t)
	ctx := context.Background()
	nshards := 2
	searchClusters, bbDocs := generator.SearchClustersWithDocuments(t, nshards, cost, corpus)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	shards := routes.ServingHosts

	est := quota.NewMemoryRateEstimator()
	repos := reposForDocs(bbDocs)
	store := fakeStoreWithReposForCorpus(t, corpus, repos...)

	authClient := newTestAuthClient(t, generator.TestActorID, []int64{})
	if cacheActor {
		actor, err := authClient.BuildActor(context.Background(), auth.BuildActorRequest{ActorID: uint32(generator.TestActorID)})
		require.NoError(t, err)
		err = authClient.SetActor(context.Background(), actor, constants.UserACLCacheTTL)
		require.NoError(t, err)
	}

	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		authClient,
		est,
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	return ctx, service, shards, est
}

// Test that the short-term quota draws the line somewhere between a reasonable
// and an unreasonable period of expensive activity.
func Test_QuotaShortTermLimit(t *testing.T) {
	// Simulate very-long-running queries, run immediately back-to-back,
	// but not concurrently.
	ctx, service, shards, est := quotaTestSetup(t, maxCost, true /* cache the actor */)
	request := generator.QueryServiceRequest(t, "ponies", 50, 5)
	for i := 0; i < 33; i++ {
		est.SetAutoAdvance(queryTimeoutSeconds)
		response, err := service.Query(ctx, request)
		if i < 3 {
			// Three queries back-to-back that time out is
			// reasonable. Check that the first three are allowed.
			successCheck(t, shards, 6, response, response.Metadata.Shards, err)
		} else if i < 30 {
			// Allow either success or failure in this range -- we
			// just mean to test that the threshold is somewhere
			// between 3 and 30 queries in a row.
		} else {
			// Eventually the user is rate-limited.
			require.EqualError(t, err, "twirp error resource_exhausted: query rejected because the user is out of quota")
		}
	}
}

// The short-term rate limit is strict enough to stop a denial-of-service attack.
func Test_CodeQueryQuotaDenialOfService(t *testing.T) {
	// Simulate many pathological queries arriving concurrently.
	ctx, service, _, _ := quotaTestSetup(t, maxCost, true /* cache the actor */)
	request := generator.QueryServiceRequest(t, "ponies", 50, 5)

	ch := make(chan error)
	wg := sync.WaitGroup{}
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := service.Query(ctx, request)
			ch <- err
		}()
	}
	go func() {
		wg.Wait()
		close(ch)
	}()

	success := 0
	for err := range ch {
		if err == nil {
			success++
		} else {
			require.EqualError(t, err, "twirp error resource_exhausted: query rejected because the user is out of quota")
		}
	}
	require.Less(t, success, 10)
}

// The accessible resources short-term rate limit is strict enough to prevent more than 5 concurrent API calls.
func Test_AccessibleResourcesConcurrentAPICallLimit(t *testing.T) {
	var tests = []struct {
		name  string
		query func(pb.QueryAPI) error
	}{
		{
			name: "Query",
			query: func(service pb.QueryAPI) error {
				request := generator.QueryServiceRequest(t, "ponies", 50, 5)
				_, err := service.Query(context.Background(), request)
				return err
			},
		},
		{
			name: "Suggest",
			query: func(service pb.QueryAPI) error {
				request := generator.SuggestServiceRequest(t, "ponies", 50, 5)
				_, err := service.Suggest(context.Background(), request)
				return err
			},
		},
		{
			name: "FrontendQuery",
			query: func(service pb.QueryAPI) error {
				request := generator.FrontendQueryServiceRequest(t, "ponies", 50, 5)
				_, err := service.FrontendQuery(context.Background(), request)
				return err
			},
		},
		{
			name: "Count",
			query: func(service pb.QueryAPI) error {
				request := generator.CountServiceRequest(t, "ponies")
				_, err := service.Count(context.Background(), request)
				return err
			},
		},
		{
			name: "LegacyQuery",
			query: func(service pb.QueryAPI) error {
				request := generator.LegacyQueryServiceRequest(t, "ponies", 50, 5)
				_, err := service.LegacyQuery(context.Background(), request)
				return err
			},
		},
		{
			name: "RefreshAuthCaches",
			query: func(service pb.QueryAPI) error {
				request := generator.RefreshAuthCachesServiceRequest(t)
				_, err := service.RefreshAuthCaches(context.Background(), request)
				return err
			},
		},
		{
			name: "WarmCaches",
			query: func(service pb.QueryAPI) error {
				request := generator.WarmCachesServiceRequest(t)
				_, err := service.WarmCaches(context.Background(), request)
				return err
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			bucket := quota.AccessibleResources
			ctx, service, _, est := quotaTestSetup(t, maxCost, false /* don't cache the actor */)
			// Precharge five concurrent accessible resources API calls.
			for i := 0; i < 5; i++ {
				result, _, err := est.PreQueryCharge(ctx, bucket.KeyForActor(generator.TestActorID), bucket.Precharge())
				require.NoError(t, err)
				require.Equal(t, result, quota.QuotaOk)
			}
			// Attempt to make a third concurrent API call should error with resource exhausted.
			err := test.query(service)
			require.Error(t, err)
			require.EqualError(t, err, "twirp error resource_exhausted: query rejected because the user is out of quota")
		})
	}
}

func getLongTermRate(t *testing.T, ctx context.Context, est quota.RateEstimator, key quota.Key) float64 {
	t.Helper()
	_, rates, err := est.PreQueryCharge(ctx, key, 0)
	require.NoError(t, err)
	return rates.LongTermRate
}

// Test that the long-term quota permits a high, but reasonable, level of
// usage.
func Test_QuotaLong(t *testing.T) {
	// Simulate an actor issuing a moderately expensive query every 100
	// seconds for 24 hours.
	ctx, service, shards, est := quotaTestSetup(t, highCost, true /* cache the actor */)
	request := generator.QueryServiceRequest(t, "ponies", 50, 5)
	for i := 0; i < 864; i++ {
		est.SetAutoAdvance(4.0)
		response, err := service.Query(ctx, request)
		for _, shard := range response.Metadata.Shards {
			// successCheck() requires a nonzero value here.
			shard.ResponseMicros = 1
		}
		successCheck(t, shards, 6, response, response.Metadata.Shards, err)
		est.AdvanceClock(ctx, 96.0)
	}

	// The rate should have converged to something like the true rate.
	trueRate := highCost / (4.0 + 96.0)
	require.Greater(t, getLongTermRate(t, ctx, est, quota.Bucket("user-query").KeyForActor(1)), float64(0.9*trueRate))
}

func Test_PromptHasAdditionalCharges(t *testing.T) {
	ctx, service, shards, est := quotaTestSetup(t, maxCost, true /* cache the actor */)
	key := quota.Bucket("user-query").KeyForActor(1)

	for _, shard := range shards {
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{{Entries: []*snapshotpb.SnapshotEntry{
				{Nwo: "github/github", OwnerId: 9919, IsRepoPublic: true, Experiments: map[string]string{"blackbird_enable_code_embedding": "1"}},
			}}},
		}, nil)
	}

	// First call with a prompt qualifier that should be have additional charges
	request := generator.QueryServiceRequestWithExperiments(t, `prompt:"ponies" repo:github/github`, 50, 5, map[string]string{
		experiments.PromptQualifier: "1",
	})
	_, err := service.Query(ctx, request)
	require.NoError(t, err)
	promptTotalCost := est.GetTotalCostCharged(ctx, key)

	// Second call doesn't have a prompt qualifier and should be charged less.
	err = est.ResetRates(ctx, key)
	require.NoError(t, err)
	request = generator.QueryServiceRequestWithExperiments(t, `ponies repo:github/github`, 50, 5, map[string]string{
		experiments.PromptQualifier: "1",
	})
	_, err = service.Query(ctx, request)
	require.NoError(t, err)
	noPromptTotalCost := est.GetTotalCostCharged(ctx, key)

	require.Greater(t, promptTotalCost, noPromptTotalCost)
	require.Equal(t, promptTotalCost-quota.CAPIEmbeddingsCharge, noPromptTotalCost)

}
