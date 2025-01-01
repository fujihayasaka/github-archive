package selfhostedrunners

import (
	context "context"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

// DeleteRunner deletes a given runner on AZP
func (s *service) DeleteRunner(ctx context.Context, req *DeleteRunnerRequest) (*DeleteRunnerResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "deleterunner")

	rid := s.getRepositoryGlobalIDFromDeleteRequest(ctx, req)
	if rid.IsZeroValue() {
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("repository id cannot be nil"))
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", rid.String()),
		kvp.Int64("gh.launch.runner.id", req.GetRunnerId()))

	arc, err := s.getAzureRepositoryClient(ctx, rid)
	if err != nil {
		obs.Report(ctx, err)
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError(err.Error()))
	}

	err = arc.DeleteRunner(ctx, req.GetRunnerId())
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, tracing.RecordError(span, svcerr)
	}

	return &DeleteRunnerResponse{Status: "deleted"}, nil
}

func (s *service) getRepositoryGlobalIDFromDeleteRequest(ctx context.Context, req *DeleteRunnerRequest) types.GlobalID {
	return types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
}
