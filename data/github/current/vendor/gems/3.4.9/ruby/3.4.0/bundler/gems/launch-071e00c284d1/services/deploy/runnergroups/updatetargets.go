package runnergroups

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	db "github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

// UpdateTargets sets the targets for a group.
func (s *service) UpdateTargets(ctx context.Context, req *UpdateTargetsRequest) (*UpdateTargetsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "updatetargets")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*db.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for UpdateTargets call")
			return &UpdateTargetsResponse{}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	visibility, err := arc.UpdateGroupTargets(ctx, req.GroupId, req.TargetIds)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	return &UpdateTargetsResponse{
		TargetIds: types.IdentitiesFromGlobalIDs(visibility.SelectedTargets),
	}, nil
}
