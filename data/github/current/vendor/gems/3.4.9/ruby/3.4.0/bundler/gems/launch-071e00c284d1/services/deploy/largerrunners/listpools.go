package largerrunners

import (
	"context"
	"reflect"

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

func (s *service) ListPools(ctx context.Context, req *ListPoolsRequest) (*ListPoolsResponse, error) {
	var entityID types.GlobalID
	var planOwnerID types.GlobalID
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "listpools")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	// backward compatibility with dotcom when parameter is not passed
	entityIDPassed := req.GetEntityId()
	if reflect.ValueOf(entityIDPassed).IsNil() {
		entityID = ownerID
	} else {
		entityID = types.NewGlobalID(ctx, entityIDPassed.GetGlobalId())

		if entityID.IsZeroValue() {
			return nil, svcerr.NewInvalidArgumentError("entity id cannot be nil")
		}
	}

	planOwnerIDPassed := req.GetPlanOwnerId()
	if reflect.ValueOf(planOwnerIDPassed).IsNil() {
		planOwnerID = ownerID
	} else {
		planOwnerID = types.NewGlobalID(ctx, planOwnerIDPassed.GetGlobalId())

		if planOwnerID.IsZeroValue() {
			return nil, svcerr.NewInvalidArgumentError("plan owner id cannot be nil")
		}
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.entity.global_id", entityID.String()), kvp.String("gh.launch.owner.global_id", ownerID.String()), kvp.String("gh.launch.plan_owner.global_id", planOwnerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for ListPools lookup")
			return &ListPoolsResponse{Pools: make([]*Pool, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	organizationName, organizationID, err := s.getPlanOwnerOrganizationInfo(ctx, planOwnerID)
	if err != nil {
		obs.Log(ctx, "could not get tenant for plan owner")
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	ipFilterParameter := req.GetIsPublicIpEnabled()

	runnerPools, err := arc.ListRunnerPools(ctx, entityID, ownerID, planOwnerID, organizationName, organizationID, req.GetEntityIsPrivate(), ipFilterParameter)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	rps := s.mapRunnerPools(runnerPools)
	return &ListPoolsResponse{Pools: rps}, nil
}
