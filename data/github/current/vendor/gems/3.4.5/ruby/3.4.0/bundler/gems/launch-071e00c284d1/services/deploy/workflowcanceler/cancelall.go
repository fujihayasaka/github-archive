package workflowcanceler

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/github/go-kvp"
	"github.com/hashicorp/go-multierror"
	errs "github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/concurrency"
)

const workflowsToCancelPerBatch int64 = 500

func (c *canceler) CancelAllWorkflowsForActorIDExludeRepoIDs(ctx context.Context, actorID types.GlobalID, excludeRepoIDs []types.GlobalID) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	ctx = ctxstash.WithFields(ctx, kvp.String("gh.actor.global_id", actorID.String()))
	ctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()

	totalCancelledBuilds := int64(0)
	previousMaxID := int64(-1)

	for {
		select {
		case <-ctx.Done():
			c.obs.Report(ctx, errs.New("timed out while cancelling workflows"), kvp.Int64("gh.launch.cancelled_builds", totalCancelledBuilds))
			return totalCancelledBuilds, ctx.Err()
		default:
		}

		wfBuildStates, err := c.wbr.GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(ctx, actorID, excludeRepoIDs, workflowsToCancelPerBatch, previousMaxID)
		if err != nil {
			return totalCancelledBuilds, tracing.RecordError(span, errs.Wrap(err, "error while fetching the workflow builds"))
		}
		if len(wfBuildStates) == 0 {
			break
		}

		c.obs.Log(ctx, "attempting to batch wise cancel workflows for actor excluding owned repos",
			kvp.Any("gh.launch.previous_max_id", previousMaxID),
			kvp.Any("gh.launch.workflow_build.count", len(wfBuildStates)))

		canceledBuilds, err := c.cancelBuilds(ctx, wfBuildStates)
		totalCancelledBuilds += canceledBuilds
		if err != nil {
			c.obs.Report(ctx, errs.New("error in batch-wise cancelling all builds for actorID"),
				kvp.Int64("gh.launch.previous_max_id", previousMaxID),
				kvp.Int("gh.launch.builds.total", len(wfBuildStates)),
				kvp.Int64("gh.launch.cancelled_builds", canceledBuilds),
				kvp.Err(err))
			return totalCancelledBuilds, err
		}

		if int64(len(wfBuildStates)) < workflowsToCancelPerBatch {
			break
		}

		previousMaxID = wfBuildStates[len(wfBuildStates)-1].DatabaseID
	}

	c.obs.Distribution(ctx, metrickeys.WorkflowsCancelAll, nil, float64(totalCancelledBuilds))
	return totalCancelledBuilds, nil
}

func (c *canceler) cancelBuilds(ctx context.Context, builds []*deployer.WorkflowBuildState) (int64, error) {
	limit := concurrency.NewLimiter(5)
	wg := &sync.WaitGroup{}
	errMutex := sync.Mutex{}
	multiErrs := &multierror.Error{}
	canceledBuilds := int64(0)

	for _, build := range builds {
		wg.Add(1)
		limit.Check()

		go (func(b *deployer.WorkflowBuildState) {
			defer wg.Done()
			defer limit.Done()

			err := c.Cancel(appcontext.CopyRequestMetadata(ctx), b, nil)
			if err != nil {
				errMutex.Lock()
				multiErrs = multierror.Append(multiErrs, errs.Wrap(err, fmt.Sprintf("error cancelling build with id: %d", b.DatabaseID)))
				errMutex.Unlock()
			} else {
				// Build was successfully canceled
				atomic.AddInt64(&canceledBuilds, 1)
			}
		})(build)
	}

	wg.Wait()

	return canceledBuilds, multiErrs.ErrorOrNil()
}
