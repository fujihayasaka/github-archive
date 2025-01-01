package artifactcache

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

func (s *service) DeleteCachesByKey(ctx context.Context, req *DeleteCachesByKeyRequest) (*DeleteCachesByKeyResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "deletecachesbykey")

	rid := types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
	if rid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("repo id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", rid.String()),
		kvp.String("gh.launch.cache.key", req.GetKey()),
		kvp.String("gh.launch.cache.scope", req.GetScope()))

	arc, err := s.getAzureRepositoryClient(ctx, rid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for DeleteCacheByKey lookup")
			return nil, svcerr.NewNotFoundError(err.Error())
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	caches, total, err := arc.DeleteCachesByKey(ctx, req.GetKey(), req.GetScope())
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, tracing.RecordError(span, svcerr)
	}

	cl := mapCacheEntries(caches)
	return &DeleteCachesByKeyResponse{Caches: cl, TotalCaches: total}, nil
}

func (s *service) DeleteCacheByID(ctx context.Context, req *DeleteCacheByIDRequest) (*DeleteCacheByIDResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "deletecachebyid")

	rid := types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
	if rid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("repo id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", rid.String()),
		kvp.Int64("gh.launch.cache_id", req.GetCacheId()))

	arc, err := s.getAzureRepositoryClient(ctx, rid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for DeleteCacheByKey lookup")
			return nil, svcerr.NewNotFoundError(err.Error())
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	err = arc.DeleteCacheByID(ctx, req.GetCacheId())
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, tracing.RecordError(span, svcerr)
	}

	return &DeleteCacheByIDResponse{Status: "deleted"}, nil
}
