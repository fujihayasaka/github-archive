package runnerscalesets

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

func (s *service) GetRunnerScaleSet(ctx context.Context, req *GetRunnerScaleSetRequest) (*GetRunnerScaleSetResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "get_runner_scale_set")

	err := req.Validate()
	if err != nil {
		return nil, err
	}

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Error(ctx, "no backing resources for GetRunnerScaleSet lookup")
			return &GetRunnerScaleSetResponse{}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	rss, err := arc.GetRunnerScaleSet(ctx, req.GetScaleSetId())
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	if rss == nil {
		return nil, svcerr.NewNotFoundError("no runner scale set found for id: %d", req.GetScaleSetId())
	}

	return &GetRunnerScaleSetResponse{
		RunnerScaleSet: ConvertDetailedRunnerScaleSetFromAzp(rss),
	}, nil
}
