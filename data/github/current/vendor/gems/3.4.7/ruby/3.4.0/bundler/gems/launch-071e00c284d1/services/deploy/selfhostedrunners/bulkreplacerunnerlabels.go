package selfhostedrunners

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

// BulkReplaceRunnerLabels updates labels for a set of runners. It does a full
// replace of any existing labels.
func (s *service) BulkReplaceRunnerLabels(ctx context.Context, req *BulkReplaceRunnerLabelsRequest) (*ListRunnersResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "replacerunnerlables")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for bulk-replacing labels")
			return &ListRunnersResponse{Runners: make([]*Runner, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	var runners []*azp.RunnerV2
	// This is a temporary work-around.
	// ListRunnerV2 doesn't currently return runners outside of the default runner-group.
	// Fortunately in the runner-groups UI one can only update a single runner's labels at a time.
	if len(req.GetUpdates()) == 1 {
		update := req.GetUpdates()[0]
		runner, err := arc.GetRunner(ctx, update.GetRunnerId())
		if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
			if report {
				obs.Report(ctx, err)
			}
			return nil, svcerr
		}

		runners = []*azp.RunnerV2{runner}
	} else {
		// We need the existing list of runners + their labels, so we can diff them with the requested updates.
		runners, _, err = arc.ListRunnersV2(ctx, 0, 0, false, 0, "", false)
		if err != nil {
			obs.Report(ctx, err)
			return nil, svcerr.NewInternalError(err.Error())
		}
	}

	existingRunners := MapDetailedAzpRunners(runners)

	operations := s.createOpsPayload(req.GetUpdates(), existingRunners)
	azpRunners, err := arc.UpdateRunners(ctx, operations)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	rs := MapDetailedAzpRunners(azpRunners)
	return &ListRunnersResponse{Runners: rs, TotalRunners: int64(len(rs))}, nil
}

// Creates the "operations" we need to perform to update the labels.
// It looks at the labels that exist for runners and compares to what the user is requesting to change.
// Each difference is turned into an operation, to "add" or "remove" labels where needed. Those operations are then sent to the Service API
func (s *service) createOpsPayload(updates []*BulkReplaceRunnerLabelsRequest_RunnerLabelsUpdate, existingRunners []*Runner) []*azp.RunnerOp {
	var operations []*azp.RunnerOp

	for _, update := range updates {
		runnerID := update.GetRunnerId()
		existingRunner := s.findExistingRunner(runnerID, existingRunners)

		existingLabelIDs := convertLabelsToLabelIDs(existingRunner.GetLabels())
		labelsToAdd := differenceInLabels(update.GetLabelIds(), existingLabelIDs)
		labelsToRemove := differenceInLabels(existingLabelIDs, update.GetLabelIds())

		operations = append(operations, s.createRunnerOps(runnerID, labelsToAdd, labelsToRemove)...)
	}

	return operations
}

func (s *service) findExistingRunner(runnerID int64, existingRunners []*Runner) *Runner {
	for _, runner := range existingRunners {
		if runner.GetId() == runnerID {
			return runner
		}
	}
	return nil
}

func convertLabelsToLabelIDs(labels []*Label) []int64 {
	labelIDs := make([]int64, len(labels))
	for i, label := range labels {
		labelIDs[i] = label.GetId()
	}
	return labelIDs
}

// differenceInLabels returns the labelIds in `a` that aren't in `b`.
// This allows us to know which labels we need to update
func differenceInLabels(a, b []int64) []int64 {
	mb := make(map[int64]struct{}, len(b))
	for _, x := range b {
		mb[x] = struct{}{}
	}
	var diff []int64
	for _, x := range a {
		if _, found := mb[x]; !found {
			diff = append(diff, x)
		}
	}
	return diff
}
