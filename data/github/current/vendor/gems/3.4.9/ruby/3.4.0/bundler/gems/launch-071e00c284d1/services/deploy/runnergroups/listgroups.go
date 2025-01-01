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
)

// ListGroups returns a list of runner groups
func (s *service) ListGroups(ctx context.Context, req *ListGroupsRequest) (*ListGroupsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "listgroups")

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
			obs.Error(ctx, "no backing resources for ListGroups lookup")
			return &ListGroupsResponse{RunnerGroups: make([]*RunnerGroup, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	organizationName, err := s.getPlanOwnerOrganizationName(ctx, planOwnerID)

	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Error(ctx, "no backing resources for plan owner")
			return nil, svcerr.NewInternalError(err.Error())
		}
		obs.Report(ctx, errors.Wrap(err, "could not get tenant for plan owner"))
		return nil, svcerr.NewInternalError(err.Error())
	}

	runtimeRunnerGroups, err := arc.ListGroups(ctx, ownerID, planOwnerID, organizationName, req.GetIncludeRunners(), req.GetIsEnterpriseOwner(), !req.GetIncludeHostedRunnerGroups(), req.GetExcludeElasticRunners(), req.GetIncludeRunnerScaleSets())
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	rgs := s.mapRunnerGroups(runtimeRunnerGroups)
	return &ListGroupsResponse{RunnerGroups: rgs}, nil
}

func (s *service) getPlanOwnerOrganizationName(ctx context.Context, planOwnerID types.GlobalID) (string, error) {
	planOwnerResource, err := s.azpResourceRepo.TryGet(ctx, planOwnerID)

	if err != nil {
		return "", err
	}

	return planOwnerResource.TenantName, nil
}
