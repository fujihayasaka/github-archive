package largerrunners

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/deploy/selfhostedrunners"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
)

func (s *service) ListPoolAgents(ctx context.Context, req *ListPoolAgentsRequest) (*ListPoolAgentsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "listpoolagents")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for ListPoolAgents lookup")
			return &ListPoolAgentsResponse{Agents: make([]*selfhostedrunners.Runner, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	azpRunners, err := arc.ListPoolAgents(ctx, req.PoolId)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	rs := selfhostedrunners.MapDetailedAzpRunners(azpRunners)

	uniqueJobs := map[string]*selfhostedrunners.Runner{}
	externalIDs := []string{}

	for _, r := range rs {
		if r.AssignedRequest != nil {
			externalIDs = append(externalIDs, r.AssignedRequest.ExternalBuildId)
			uniqueJobs[r.AssignedRequest.ExternalBuildId] = r
		}
	}

	workflowJobsIds, err := s.jobsRepository.GetWorkflowJobsFromJobIds(ctx, externalIDs)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	for ei, wj := range workflowJobsIds {
		uniqueJobs[ei].AssignedRequest.CheckRunId = wj
	}

	return &ListPoolAgentsResponse{Agents: rs}, nil
}
