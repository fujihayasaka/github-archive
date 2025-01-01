package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts/appctx"
	ma_ "github.com/github/turboscan/ts/managedanalyses"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/pkg/errors"
)

// UpsertCodeqlRunStatus updates the status of a CodeqlRun and returns it.
// If the run is a validation run, it also updates the status of the associated CodeqlConfig,
// and the repository metadata.
func (ma *ManagedAnalyses) UpsertCodeqlRunStatus(ctx context.Context, repoID ts.RepositoryEID, workflowRunID ts.WorkflowRunEID, sha ts.Sha, newStatus ts.CodeqlRunStatus) (*ts.CodeqlRun, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	run, err := ma.DataService.GetCodeqlRun(ctx, repoID, workflowRunID)
	if err != nil {
		if errors.Is(err, ts.ErrCodeqlRunNotFound) {
			appctx.Logger(ctx).Info("Codeql run not found on Workflow completion.",
				workflowRunID.AsKVP(),
				sha.AsKVP(),
				kvp.Int8("newStatus", int8(newStatus)),
			)
		}
		return nil, err
	}

	// We care about this method being idempotent as it is mostly used by a job.
	// Therefore, we do not error if a "final" status has been set, unless it is inconsistent.
	if run.Status.IsFinal() && run.Status != newStatus {
		return nil, errors.WithStack(ts.ErrWorkflowRunAlreadyCompleted)
	}

	// Update run status
	if run.Status != newStatus {
		run.Status = newStatus
		err = ma.DataService.UpdateCodeqlRun(ctx, run)
		if err != nil {
			return nil, err
		}
	}

	// If this was a validation run, we want to update the configuration
	if run.Validation() {
		if run.Succeeded() {
			err = ma.DataService.PromoteCodeqlConfigToCurrent(ctx, run.Config, run.RepositoryID, &run.Status)
			if err != nil {
				return nil, err
			} else {
				err = ma.UpdateRepoMetadata(ctx, repoID)
				if err != nil {
					return nil, errors.Wrap(err, "could not update repository metadata")
				}
			}
		} else if run.Failed() {
			err = ma.DataService.WithTransaction(func(tx ma_.CodeqlDB) error {
				err = tx.DeprecateStagedCodeqlConfig(ctx, repoID, run.CodeqlConfigID, &run.Status)
				if err != nil {
					return err
				}

				return nil
			})
			if err != nil {
				return nil, err
			}
		}
	}

	return run, nil
}
