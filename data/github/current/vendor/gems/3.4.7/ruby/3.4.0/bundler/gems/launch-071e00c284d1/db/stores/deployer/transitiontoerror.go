package deployer

import (
	"context"

	"github.com/pkg/errors"
	errs "github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/workflowbuild/build"
)

func (w *workflowBuildsRepository) TransitionToError(
	ctx context.Context,
	workflowBuildID int64,
	checkSuiteID types.GlobalID,
) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	checkSuiteNextID, err := w.gidMigrator.GetNextGlobalID(ctx, checkSuiteID.String())
	if err != nil {
		return tracing.RecordError(span, errors.Wrap(err, "Failed to get next check suite id for TransitionToError"))
	}

	// Check FF to see if we should use the next ID
	if checkSuiteNextID != checkSuiteID {
		w.logGlobalIDReplacement(ctx, "TransitionToError", "check_suite_id", checkSuiteID, checkSuiteNextID)
	}

	const updateSQL = `UPDATE workflow_builds
		SET
			state = ?,
			completed_at = ?,
			check_suite_id = ?,
			check_suite_next_id = ?
		WHERE
			id = ?
	`

	now := w.clock.Now().UTC()
	rows, err := w.db.ExecContextWith(
		ctx,
		updateSQL,
		asql.WithName("TransitionToError"),
		build.WorkflowStateFailed,
		now,
		// we set check suite here as it might have just been created
		wrapNullString(checkSuiteNextID.String()),
		wrapNullString(checkSuiteNextID.String()),
		workflowBuildID,
	)

	if err != nil {
		return errs.Wrap(err, "failed to update in TransitionToError")
	}
	c, err := rows.RowsAffected()
	if err != nil {
		return errs.Wrap(err, "failed to update in TransitionToError")
	}
	if c == 0 {
		return errs.Errorf("failed to update existing build row `%v' in TransitionToError", workflowBuildID)
	}

	err = w.executions.TransitionToError(ctx, workflowBuildID, now)
	if err != nil {
		return errs.Wrap(err, "failed to update workflow build execution TransitionToError")
	}

	return nil
}
