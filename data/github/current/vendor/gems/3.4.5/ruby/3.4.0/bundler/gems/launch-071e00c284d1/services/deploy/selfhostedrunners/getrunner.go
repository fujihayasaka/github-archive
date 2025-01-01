package selfhostedrunners

import (
	"context"

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

// GetRunner returns a single runner for a given ID
func (s *service) GetRunner(ctx context.Context, req *GetRunnerRequest) (*GetRunnerResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "getrunner")

	oid := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	runnerID := req.GetRunnerId()

	ctx = ctxstash.WithFields(
		ctx,
		kvp.String("gh.launch.owner.global_id", oid.String()),
		kvp.Int64("gh.launch.runner.id", runnerID),
	)

	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for GetRunner lookup")
			return &GetRunnerResponse{}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	azpRunner, err := arc.GetRunner(ctx, runnerID)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	r := ConvertDetailedRunnerFromAzp(azpRunner)
	if azpRunner.AssignedRequest != nil {
		workflowJob, err := s.jobsRepository.GetWorkflowJobFromJobID(ctx, azpRunner.AssignedRequest.PlanID, azpRunner.AssignedRequest.JobID)
		if err != nil {
			obs.Report(ctx, err)
			return nil, svcerr.NewInternalError(err.Error())
		}

		if workflowJob != nil {
			r.AssignedRequest.CheckRunId = workflowJob.CheckRunID.String()
		}
	}
	return &GetRunnerResponse{Runner: r}, nil
}
