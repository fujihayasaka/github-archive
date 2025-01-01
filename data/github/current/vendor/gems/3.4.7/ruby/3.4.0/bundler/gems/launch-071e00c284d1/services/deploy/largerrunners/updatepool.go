package largerrunners

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

func (s *service) UpdatePool(ctx context.Context, req *UpdatePoolRequest) (*UpdatePoolResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "updatepool")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for UpdatePool lookup")
			return &UpdatePoolResponse{Pool: nil}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	platform := "linux-x64"
	if req.Platform != "" {
		platform = req.Platform
	}

	var imageKey *azp.ImageKey

	if req.Image != nil {
		imageKey = &azp.ImageKey{
			Source:  imageSourceToString[req.Image.Source],
			ID:      req.Image.Id,
			Version: req.Image.Version,
		}
	} else {
		imageKey = nil
	}

	poolUpdateDetails := azp.UpdatePoolRequest{
		Name:              req.Name,
		Platform:          platform,
		RunnerGroupID:     req.RunnerGroupId,
		Labels:            req.Labels,
		MachineSpecID:     req.MachineSpecId,
		IsPublicIPEnabled: req.IsPublicIpEnabled,
		MaximumRunners:    req.MaximumRunners,
		Image:             imageKey,
	}

	runnerPool, err := arc.UpdateRunnerPool(ctx, req.PoolId, poolUpdateDetails)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	rp := s.mapRunnerPool(runnerPool)
	return &UpdatePoolResponse{Pool: rp}, nil
}
