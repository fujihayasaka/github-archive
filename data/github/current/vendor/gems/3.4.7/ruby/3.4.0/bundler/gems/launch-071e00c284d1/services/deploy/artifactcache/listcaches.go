package artifactcache

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"

	"github.com/github/launch/observability"
	"github.com/github/launch/types"
)

func (s *service) ListCaches(ctx context.Context, req *ListCachesRequest) (*ListCachesResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "listcaches")

	rid := types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
	if rid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("repo id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", rid.String()),
		kvp.String("gh.launch.cache.key", req.GetKey()),
		kvp.String("gh.launch.cache.scope", req.GetScope()),
		kvp.String("gh.launch.cache.sort", req.GetSort()),
		kvp.String("gh.launch.cache.direction", req.GetDirection()),
		kvp.Int64("gh.launch.cache.page", req.GetPage()),
		kvp.Int64("gh.launch.cache.per_page", req.GetPerPage()))

	arc, err := s.getAzureRepositoryClient(ctx, rid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for ListCaches lookup")
			return &ListCachesResponse{Caches: make([]*CacheEntry, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	caches, total, err := arc.ListCaches(ctx, req.GetKey(), req.GetScope(), req.GetSort(), req.GetDirection(), req.GetPage(), req.GetPerPage())
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	cl := mapCacheEntries(caches)
	return &ListCachesResponse{Caches: cl, TotalCaches: total}, nil
}
