package query

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/noop"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_QuerySuccess(t *testing.T) {
	fixtures := []struct {
		Name          string
		AuthClient    *auth.Client
		Success       bool
		ExpectedError string
		ReposInBB     []generator.RepoSpec
		ReposReturned []types.RepoID
	}{
		{
			Name:       "success: public repos visible, private repos hidden",
			AuthClient: newTestAuthClient(t, generator.TestActorID, []int64{}),
			Success:    true,
			ReposInBB: []generator.RepoSpec{
				{RepoID: 1, Public: true, DocsToReturn: 1, DocsWithContent: 1, NumLocsPerDoc: 1},
				{RepoID: 2, Public: false, DocsToReturn: 1, DocsWithContent: 1, NumLocsPerDoc: 1},
			},
			ReposReturned: []types.RepoID{1},
		},
		{
			Name:       "success: public repos visible, private repos visible",
			AuthClient: newTestAuthClient(t, generator.TestActorID, []int64{2}),
			Success:    true,
			ReposInBB: []generator.RepoSpec{
				{RepoID: 1, Public: true, DocsToReturn: 1, DocsWithContent: 1, NumLocsPerDoc: 1},
				{RepoID: 2, Public: false, DocsToReturn: 1, DocsWithContent: 1, NumLocsPerDoc: 1},
			},
			ReposReturned: []types.RepoID{1, 2},
		},
		{
			Name:          "401 from github",
			AuthClient:    newFailingTestAuthClient(t, auth.ErrUnauthorized),
			Success:       false,
			ExpectedError: "twirp error unauthenticated: cannot auth actor",
			ReposInBB:     []generator.RepoSpec{{RepoID: 1, Public: true, DocsToReturn: 1, DocsWithContent: 1, NumLocsPerDoc: 1}},
		},
		{
			Name:          "any other error from auth client",
			AuthClient:    newFailingTestAuthClient(t, errors.New("failed to fetch accessible repos")),
			Success:       false,
			ExpectedError: "twirp error internal: failed to fetch accessible repos",
			ReposInBB:     []generator.RepoSpec{{RepoID: 1, Public: true, DocsToReturn: 1, DocsWithContent: 1, NumLocsPerDoc: 1}},
		},
	}

	quotaRateEstimator := quota.NewMemoryRateEstimator()

	for _, fixture := range fixtures {
		t.Run(fixture.Name, func(t *testing.T) {
			ctx := context.Background()
			corpus := helpers.Corpus(t)
			searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
			routes := searchClusters.GetServingRoutes(ctx, corpus)
			repos := []*db.Repository{}
			for _, r := range fixture.ReposInBB {
				repos = append(repos, &db.Repository{RepoID: r.RepoID, IsPublic: r.Public})
			}
			store := noop.New(repos...)
			service := NewService(
				routing.Dotcom,
				helpers.IndexerClusters(t),
				searchClusters,
				store,
				cache.NewInMemory(),
				fixture.AuthClient,
				quotaRateEstimator,
				treelights.NewNoopClient(),
				fakeGitClient(),
				helpers.CopilotClient(t),
			)
			shards := routes.ServingHosts

			for _, shard := range shards {
				bbResp := generator.BlackbirdResponseFromSpec(t, fixture.ReposInBB...)
				helpers.FakeShardClient(t, shard[0]).SearchReturns(bbResp, nil)
			}

			// Hit the query endpoint
			response, err := service.Query(ctx, generator.QueryServiceRequest(t, "test", 50, 5))
			if fixture.Success {
				require.NoError(t, err)

				repos := map[types.RepoID]struct{}{}
				for _, d := range response.Documents {
					for _, l := range d.Locations {
						repos[types.RepoID(l.RepoId)] = struct{}{}
					}
				}
				ids := []types.RepoID{}
				for id := range repos {
					ids = append(ids, id)
				}

				require.ElementsMatch(t, ids, fixture.ReposReturned)
			} else {
				require.EqualError(t, err, fixture.ExpectedError)
			}

			// Hit the suggest endpoint
			_, err = service.Suggest(ctx, generator.SuggestServiceRequest(t, "test", 50, 5))
			if fixture.Success {
				require.NoError(t, err)
			} else {
				require.EqualError(t, err, fixture.ExpectedError)
			}
		})
	}
}

func Test_WarmCaches(t *testing.T) {
	ctx := context.Background()
	authClient := auth.NewClient(cache.NewInMemory(), &auth.Mockzd{
		RepoIDs:                   map[int64][]int64{generator.TestActorID: {int64(privateRepo.RepoID)}},
		AuthorizedOrganizationIDs: []int64{int64(publicRepo.OwnerID)},
		ProtectedOrganizationIDs:  []int64{},
	}, noop.New())
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		helpers.SearchClusters(t),
		noop.New(privateRepo),
		cache.NewInMemory(),
		authClient,
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	resp, err := service.WarmCaches(ctx, &pb.WarmCachesRequest{
		Actor: &pb.Actor{
			ActorId:     generator.TestActorID,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	})
	require.NoError(t, err)
	require.Equal(t, 10.0, math.Round(time.Until(resp.UserCacheExpiresAt.AsTime()).Minutes()))

	cacheExpiryTime := resp.UserCacheExpiresAt.AsTime()

	// Wait one second so that the expiry time would change if the cache is refreshed
	time.Sleep(1 * time.Second)

	// Second attempt at warm cache shouldn't refresh, just return the old cache time
	resp, err = service.WarmCaches(ctx, &pb.WarmCachesRequest{
		Actor: &pb.Actor{
			ActorId:     generator.TestActorID,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	})
	require.NoError(t, err)
	require.Equal(t, cacheExpiryTime.Unix(), resp.UserCacheExpiresAt.AsTime().Unix())

	// Third attempt hard refreshes the cache
	refreshResp, err := service.RefreshAuthCaches(ctx, &pb.RefreshAuthCachesRequest{
		Actor: &pb.Actor{
			ActorId:     generator.TestActorID,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	})
	require.NoError(t, err)
	require.NotEqual(t, cacheExpiryTime.Unix(), refreshResp.UserCacheExpiresAt.AsTime().Unix())
}

func Test_WarmCachesInvalidActor(t *testing.T) {
	ctx := context.Background()
	authClient := auth.NewClient(cache.NewInMemory(), &auth.Mockzd{
		RepoIDs:                   map[int64][]int64{generator.TestActorID: {int64(privateRepo.RepoID)}},
		AuthorizedOrganizationIDs: []int64{int64(publicRepo.OwnerID)},
		ProtectedOrganizationIDs:  []int64{},
	}, noop.New())
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		helpers.SearchClusters(t),
		noop.New(privateRepo),
		cache.NewInMemory(),
		authClient,
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	// NB: Actor is invalid because it lacks an access token.
	_, err := service.WarmCaches(ctx, &pb.WarmCachesRequest{
		Actor: &pb.Actor{
			ActorId:   generator.TestActorID,
			RequestIp: "127.0.0.1",
		},
	})
	require.Error(t, err)
	twirpErr, ok := err.(twirp.Error)
	require.True(t, ok)
	require.Equal(t, twirp.InvalidArgument, twirpErr.Code())
}

func Test_WarmCachesAnonActor(t *testing.T) {
	ctx := context.Background()
	authClient := auth.NewClient(cache.NewInMemory(), &auth.Mockzd{
		RepoIDs:                   map[int64][]int64{generator.TestActorID: {int64(privateRepo.RepoID)}},
		AuthorizedOrganizationIDs: []int64{int64(publicRepo.OwnerID)},
		ProtectedOrganizationIDs:  []int64{},
	}, noop.New())
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		helpers.SearchClusters(t),
		noop.New(privateRepo),
		cache.NewInMemory(),
		authClient,
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	// No actor is provided.
	_, err := service.WarmCaches(ctx, &pb.WarmCachesRequest{})
	require.Error(t, err)
	twirpErr, ok := err.(twirp.Error)
	require.True(t, ok)
	require.Equal(t, twirp.Unauthenticated, twirpErr.Code())
}

func Test_RefreshAuthCaches(t *testing.T) {
	ctx := context.Background()
	authClient := auth.NewClient(cache.NewInMemory(), &auth.Mockzd{
		RepoIDs:                   map[int64][]int64{generator.TestActorID: {int64(privateRepo.RepoID)}},
		AuthorizedOrganizationIDs: []int64{int64(publicRepo.OwnerID)},
		ProtectedOrganizationIDs:  []int64{},
	}, noop.New())
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		helpers.SearchClusters(t),
		noop.New(privateRepo),
		cache.NewInMemory(),
		authClient,
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	resp, err := service.RefreshAuthCaches(ctx, &pb.RefreshAuthCachesRequest{
		Actor: &pb.Actor{
			ActorId:     generator.TestActorID,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	})
	require.NoError(t, err)
	require.Equal(t, 10.0, math.Round(time.Until(resp.UserCacheExpiresAt.AsTime()).Minutes()))
}

func Test_RefreshAuthCachesInvalidActor(t *testing.T) {
	ctx := context.Background()
	authClient := auth.NewClient(cache.NewInMemory(), &auth.Mockzd{
		RepoIDs:                   map[int64][]int64{generator.TestActorID: {int64(privateRepo.RepoID)}},
		AuthorizedOrganizationIDs: []int64{int64(publicRepo.OwnerID)},
		ProtectedOrganizationIDs:  []int64{},
	}, noop.New())
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		helpers.SearchClusters(t),
		noop.New(privateRepo),
		cache.NewInMemory(),
		authClient,
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	// NB: Actor is invalid because it lacks an access token.
	_, err := service.RefreshAuthCaches(ctx, &pb.RefreshAuthCachesRequest{
		Actor: &pb.Actor{
			ActorId:   generator.TestActorID,
			RequestIp: "127.0.0.1",
		},
	})
	require.Error(t, err)
	twirpErr, ok := err.(twirp.Error)
	require.True(t, ok)
	require.Equal(t, twirp.InvalidArgument, twirpErr.Code())
}

func Test_RefreshAuthCachesAnonActor(t *testing.T) {
	ctx := context.Background()
	authClient := auth.NewClient(cache.NewInMemory(), &auth.Mockzd{
		RepoIDs:                   map[int64][]int64{generator.TestActorID: {int64(privateRepo.RepoID)}},
		AuthorizedOrganizationIDs: []int64{int64(publicRepo.OwnerID)},
		ProtectedOrganizationIDs:  []int64{},
	}, noop.New())
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		helpers.SearchClusters(t),
		noop.New(privateRepo),
		cache.NewInMemory(),
		authClient,
		quota.NewMemoryRateEstimator(),
		treelights.NewNoopClient(),
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	// No actor is provided.
	_, err := service.RefreshAuthCaches(ctx, &pb.RefreshAuthCachesRequest{})
	require.Error(t, err)
	twirpErr, ok := err.(twirp.Error)
	require.True(t, ok)
	require.Equal(t, twirp.Unauthenticated, twirpErr.Code())
}
