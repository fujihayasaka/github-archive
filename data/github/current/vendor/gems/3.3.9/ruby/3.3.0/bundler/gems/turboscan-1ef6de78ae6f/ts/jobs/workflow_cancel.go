package jobs

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/pkg/errors"
)

// CancelObsoleteRuns cancels pending older runs that have been superseded by the given newRun
func CancelObsoleteRuns(ctx context.Context, ma *maservice.ManagedAnalyses, newRun *ts.CodeqlRun) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// Check if we need to cancel any older runs that are now obsolete
	runs, err := ma.DataService.GetPendingRunsForRef(ctx, newRun.RepositoryID, newRun.Ref, newRun.CreatedAt.Add(-10*time.Minute))
	if err != nil {
		return err
	}
	return CancelQueuedRuns(ctx, ma, runs)
}

// CancelQueuedRuns cancels those of the given runs that are still queued and
// syncs the status of the remaining runs with the database.
func CancelQueuedRuns(ctx context.Context, ma *maservice.ManagedAnalyses, runs []ts.CodeqlRun) error {
	// Return early if there are no runs to cancel
	if len(runs) == 0 {
		return nil
	}

	runsByRepo := map[ts.RepositoryEID][]ts.CodeqlRun{}
	for _, run := range runs {
		if _, ok := runsByRepo[run.RepositoryID]; !ok {
			runsByRepo[run.RepositoryID] = []ts.CodeqlRun{run}
		} else {
			runsByRepo[run.RepositoryID] = append(runsByRepo[run.RepositoryID], run)
		}
	}

	for repoID, runs := range runsByRepo {
		stateByRun, err := ma.GitHubTwirpApiClient.CancelQueuedRuns(ctx, repoID, transforms.Map(runs, func(r ts.CodeqlRun) ts.WorkflowRunEID { return r.WorkflowRunID }))
		if err != nil {
			return err
		}

		for _, r := range runs {
			state, ok := stateByRun[r.WorkflowRunID]
			if !ok {
				appctx.Logger(ctx).Error("Missing state for run", r.WorkflowRunID.AsKVP())
				continue
			}
			runStatus, err := runStatusForStateFromAPI(state)
			if err != nil {
				return err
			}
			if r.Status == runStatus {
				continue
			}
			if runStatus != ts.CodeQlRunStatus_CANCELLED {
				appctx.Logger(ctx).Error("Observed run status mismatch between TS and gh/gh",
					r.WorkflowRunID.AsKVP(),
					kvp.String("gh.turboscan.codeql_run_status.local", r.Status.String()),
					kvp.String("gh.turboscan.codeql_run_status.remote", runStatus.String()),
				)
			}
			_, err = UpsertCodeqlRunStatus(ctx, ma.DataService, ma.UpdateRepoMetadata, ma.EnabledStatusService, repoID, r.WorkflowRunID, r.Sha, runStatus)
			if err != nil && !errors.Is(err, ts.ErrWorkflowRunAlreadyCompleted) {
				return err
			}
		}
	}
	return nil
}

func runStatusForStateFromAPI(s ghgh.WorkflowRunState) (ts.CodeqlRunStatus, error) {
	switch s.Status {
	case "requested", "pending":
		return ts.CodeqlRunStatus_PENDING, nil
	case "in_progress", "waiting", "queued":
		return ts.CodeqlRunStatus_INPROGRESS, nil
	case "completed":
		switch s.Conclusion {
		case "neutral", "success", "skipped":
			return ts.CodeqlRunStatus_COMPLETED, nil
		case "failure", "action_required", "timed_out", "stale", "startup_failure":
			return ts.CodeqlRunStatus_FAILED, nil
		case "cancelled":
			return ts.CodeQlRunStatus_CANCELLED, nil
		}
	}

	return ts.CodeqlRunStatus_PENDING, errors.Errorf("unable to determine run status for status=%s and conclusion=%s", s.Status, s.Conclusion)
}
