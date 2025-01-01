package checks

import (
	context "context"
	"sort"
	"strings"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/services/deploy/status"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
)

// StepsFromChangeID returns a list of steps after (exclusive) the changeID
// changeID of 0 means return all of the steps
func (s *service) StepsFromChangeID(ctx context.Context, req *StepsFromChangeIDRequest) (*StepsFromChangeIDResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "stepsfromchangeid")

	oid := types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("repo id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", oid.String()),
		kvp.Int64("gh.launch.change_id", req.GetChangeId()),
		kvp.String("gh.launch.job.id", req.GetJobId()),
		kvp.String("gh.launch.plan_id", req.GetPlanId()))

	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for StepsFromChangeID lookup")
			return &StepsFromChangeIDResponse{Steps: make([]*pbtypes.CheckStep, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	actionSteps, err := arc.StepsFromChangeID(ctx, req.GetChangeId(), req.GetJobId(), req.GetPlanId())
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	// the step information coming in has actions conclusions and results, we need
	// to convert them for dotcom's use
	// coderef from reciever: https://github.com/github/launch/blob/db1df765fdd367c157fdd2a285eb488cf654457c/services/receiver/status/marshal.go#L437-L488
	checkSteps := make([]*pbtypes.CheckStep, 0)
	for _, step := range actionSteps {
		checkSteps = append(checkSteps, actionStepToCheckStep(step))
	}

	sort.Slice(checkSteps, func(i, j int) bool {
		return checkSteps[i].Number < checkSteps[j].Number
	})

	return &StepsFromChangeIDResponse{Steps: checkSteps}, nil
}

func actionStepToCheckStep(actionStep *azp.ChangeIDResponseSteps) *pbtypes.CheckStep {
	newStep := &pbtypes.CheckStep{}

	newStep.Id = actionStep.ID
	newStep.Name = actionStep.Name

	if actionStep.IsStarted() && actionStep.Status != "" {
		ghStatus := string(status.AZPToCheckStatus(actionStep.Status))
		newStep.Status = strings.ToLower(ghStatus)
	} else {
		// https://github.com/github/launch/blob/db1df765fdd367c157fdd2a285eb488cf654457c/services/deploy/status/checkrunbuilder.go#L193-L194
		newStep.Status = "queued"
	}

	if actionStep.Conclusion != "" {
		ghConclusion := string(status.AZPToCheckResult(actionStep.Conclusion))
		newStep.Conclusion = strings.ToLower(ghConclusion)
	}

	if actionStep.StartedAt != nil {
		newStep.StartedAt = timestamppb.New(*actionStep.StartedAt)
	}

	if actionStep.CompletedAt != nil {
		newStep.CompletedAt = timestamppb.New(*actionStep.CompletedAt)
	}

	if actionStep.Log != nil {
		newStep.Log = &pbtypes.CheckStepLog{
			Id:        actionStep.Log.ID,
			Url:       actionStep.Log.URL,
			LineCount: actionStep.Log.LineCount,
		}
	}

	newStep.ChangeId = actionStep.ChangeID
	newStep.Number = actionStep.Number

	return newStep
}

// JobStepsFromChangeID returns a list of steps for jobs in a plan after (exclusive) the changeID
// changeID of 0 means return all of the steps
func (s *service) StepsFromChangeIDForRun(ctx context.Context, req *StepsFromChangeIDForRunRequest) (*StepsFromChangeIDForRunResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "jobstepsfromchangeid")

	oid := types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("repo id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", oid.String()),
		kvp.Int64("gh.launch.change_id", req.GetChangeId()),
		kvp.String("gh.launch.plan_id", req.GetPlanId()))

	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for JobStepsFromChangeID lookup")
			return &StepsFromChangeIDForRunResponse{JobSteps: make([]*JobSteps, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	actionJobSteps, err := arc.StepsFromChangeIDForRun(ctx, req.GetChangeId(), req.GetPlanId(), true)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	checkJobSteps := make([]*JobSteps, 0, len(actionJobSteps))
	for _, jobStep := range actionJobSteps {
		checkJobStep := &JobSteps{
			JobId: jobStep.ID,
		}

		checkSteps := make([]*pbtypes.CheckStep, 0, len(jobStep.Steps))
		for _, step := range jobStep.Steps {
			checkSteps = append(checkSteps, actionStepToCheckStep(step))
		}

		checkJobStep.Steps = checkSteps

		checkJobSteps = append(checkJobSteps, checkJobStep)
	}

	return &StepsFromChangeIDForRunResponse{JobSteps: checkJobSteps}, nil
}
