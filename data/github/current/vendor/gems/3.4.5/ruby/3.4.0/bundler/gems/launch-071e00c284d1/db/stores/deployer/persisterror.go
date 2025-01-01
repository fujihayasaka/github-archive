package deployer

import (
	"context"

	"github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/workflowbuild/build"
)

func (w *workflowBuildsRepository) PersistError(
	ctx context.Context,
	repoID types.GlobalID,
	uuid types.WorkflowExecutionID,
	eventName string,
	eventSHA types.CommitSha,
	eventRef types.GitRef,
	requestID string,
	checkSuiteID types.GlobalID,
	filePath string,
	executingActorID, triggeringActorID types.GlobalID,
) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repositoryNextID, err := w.gidMigrator.GetNextGlobalID(ctx, repoID.String())
	if err != nil {
		return -1, tracing.RecordError(span, errors.Wrap(err, "Failed to get next repository id for PersistError"))
	}

	checkSuiteNextID, err := w.gidMigrator.GetNextGlobalID(ctx, checkSuiteID.String())
	if err != nil {
		return -1, tracing.RecordError(span, errors.Wrap(err, "Failed to get next check suite id for PersistError"))
	}

	executingActorNextID, err := w.gidMigrator.GetNextGlobalID(ctx, executingActorID.String())
	if err != nil {
		return -1, tracing.RecordError(span, errors.Wrap(err, "Failed to get next executing actor id for PersistError"))
	}

	now := w.clock.Now().UTC()

	// Check FF to see if we should use the next ID
	if repositoryNextID != repoID {
		w.logGlobalIDReplacement(ctx, "PersistError", "repository_id", repoID, repositoryNextID)
	}
	if executingActorNextID != executingActorID {
		w.logGlobalIDReplacement(ctx, "PersistError", "executing_actor_id", executingActorID, executingActorNextID)
	}
	if checkSuiteNextID != checkSuiteID {
		w.logGlobalIDReplacement(ctx, "PersistError", "check_suite_id", checkSuiteID, checkSuiteNextID)
	}

	query := `INSERT INTO workflow_builds
		SET
			uuid=?,
			created_at=?,
			repository_id=?,
			repository_next_id=?,
			commit_sha=?,
			event_ref=?,
			check_suite_id=?,
			check_suite_next_id = ?,
			request_id=?,
			workflow_file_path=?,
			event=?,
			workflow_id=?,
			state=?,
			completed_at=?,
			checkout_sha="",
			checkout_ref="",
			executing_actor_id=?,
			executing_actor_next_id=?
	`

	res, err := w.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("PersistError"),
		uuid,
		now,
		repositoryNextID,
		repositoryNextID,
		eventSHA,
		eventRef,
		// If no check suite id is given, insert `NULL` instead of an empty string
		wrapNullString(checkSuiteNextID.String()),
		wrapNullString(checkSuiteNextID.String()),
		requestID,
		filePath,
		eventName,
		// file path used as identifier
		filePath,
		build.WorkflowStateFailed,
		now,
		wrapNullString(executingActorNextID.String()),
		wrapNullString(executingActorNextID.String()),
	)
	if err != nil {
		return -1, tracing.RecordError(span, err)
	}

	workflowDatabaseID, err := res.LastInsertId()
	if err != nil {
		return -1, tracing.RecordError(span, err)
	}

	_, err = w.executions.PersistError(ctx, uuid, workflowDatabaseID, triggeringActorID, 1, now)
	if err != nil {
		return -1, tracing.RecordError(span, err)
	}

	return workflowDatabaseID, nil
}
