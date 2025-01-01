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
)

// BulkUpdateRunnerLabels updates labels for a set of runners.
func (s *service) BulkUpdateRunnerLabels(ctx context.Context, req *BulkUpdateRunnerLabelsRequest) (*ListRunnersResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "bulkupdaterunnerlabels")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for bulk-updating labels")
			return &ListRunnersResponse{Runners: make([]*Runner, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	var operations []*azp.RunnerOp

	for _, ops := range req.GetUpdates() {
		runnerID := ops.GetRunnerId()
		labelsToAdd := ops.GetAdditions()
		labelsToRemove := ops.GetRemovals()

		operations = append(operations, s.createRunnerOps(runnerID, labelsToAdd, labelsToRemove)...)
	}

	azpRunners, err := arc.UpdateRunners(ctx, operations)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	rs := MapDetailedAzpRunners(azpRunners)
	return &ListRunnersResponse{Runners: rs, TotalRunners: int64(len(rs))}, nil
}
