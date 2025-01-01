package runnergroups

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

// GetGroup returns a runner group.
func (s *service) GetGroup(ctx context.Context, req *GetGroupRequest) (*GetGroupResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "getgroup")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	planOwnerID := types.NewGlobalID(ctx, req.GetPlanOwnerId().GetGlobalId())
	if planOwnerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("plan owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()), kvp.String("gh.launch.plan_owner.global_id", planOwnerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for GetGroup lookup")
			return &GetGroupResponse{RunnerGroup: nil}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	organizationName, err := s.getPlanOwnerOrganizationName(ctx, planOwnerID)
	if err != nil {
		obs.Log(ctx, "could not get tenant for plan owner")
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	runtimeRunnerGroup, err := arc.GetGroup(ctx, req.GetGroupId(), ownerID, planOwnerID, organizationName, req.GetIncludeRunners(), req.GetIsEnterpriseOwner(), !req.GetIncludeHostedRunnerGroups(), req.GetExcludeElasticRunners(), req.GetIncludeRunnerScaleSets())
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}
	if runtimeRunnerGroup == nil {
		return nil, svcerr.NewNotFoundError("Runner group not found")
	}

	rg := s.mapRunnerGroup(runtimeRunnerGroup)
	return &GetGroupResponse{RunnerGroup: rg}, nil
}
