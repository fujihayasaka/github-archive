package runnergroups

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	db "github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

var allowPublicFromCreateReq = map[bool]azp.AllowPublic{
	true:  azp.AllowPublicAllow,
	false: azp.AllowPublicDeny,
}

var restrictedToWorkflowsFromCreateReq = map[bool]azp.RestrictedToWorkflows{
	true:  azp.RestrictedToWorkflowsRestricted,
	false: azp.RestrictedToWorkflowsUnrestricted,
}

// CreateGroup creates a runner group.
func (s *service) CreateGroup(ctx context.Context, req *CreateGroupRequest) (*CreateGroupResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "creategroup")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*db.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for CreateGroup lookup")
			return &CreateGroupResponse{RunnerGroup: nil}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	allowPublic := allowPublicFromCreateReq[req.AllowPublic]
	restrictedToWorkflows := restrictedToWorkflowsFromCreateReq[req.RestrictedToWorkflows]
	runtimeRunnerGroup, err := arc.CreateGroup(ctx, req.RunnerIds, req.Name, req.SelectedTargets, req.Visibility.String(), allowPublic, req.SelectedWorkflowRefs, restrictedToWorkflows)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	rg := s.mapRunnerGroup(runtimeRunnerGroup)
	return &CreateGroupResponse{RunnerGroup: rg}, nil
}
