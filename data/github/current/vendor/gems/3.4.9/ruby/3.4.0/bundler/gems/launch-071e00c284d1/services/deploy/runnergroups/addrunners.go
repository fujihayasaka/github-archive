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

// AddRunners adds runners to a group.
func (s *service) AddRunners(ctx context.Context, req *AddRunnersRequest) (*AddRunnersResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "addrunners")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*db.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for AddRunners call")
			return &AddRunnersResponse{RunnerGroup: nil}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	runtimeRunnerGroup, err := arc.AddRunners(ctx, req.GroupId, req.RunnerIds)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	rg := s.mapRunnerGroup(runtimeRunnerGroup)
	return &AddRunnersResponse{RunnerGroup: rg}, nil
}
