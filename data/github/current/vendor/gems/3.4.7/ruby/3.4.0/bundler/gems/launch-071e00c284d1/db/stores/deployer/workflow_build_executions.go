package deployer

import (
	"context"
	"database/sql"
	"time"

	"github.com/facebookgo/clock"
	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/workflowbuild/build"
)

type WorkflowBuildExecutionState struct {
	DatabaseID        int64
	PlanID            types.WorkflowExecutionID
	WebhookDeliveryID *string
	ExternalBuildID   string
	WorkflowBuildID   int64
	QueuedAt          *time.Time
	StartedAt         *time.Time
	CompletedAt       *time.Time
	CreatedAt         *time.Time
	State             build.WorkflowState
	WasDelayed        bool
	TriggeringActorID types.GlobalID
	Attempt           int
	WorkflowMetadata  *metadata.WorkflowMetadata
	Backend           types.WorkflowBackend
}

// WorkflowBuildExecutionsRepository holds methods for loading/saving from the workflow_build_executions DB table.
type WorkflowBuildExecutionsRepository interface {
	Persist(
		ctx context.Context,
		b *build.WorkflowBuild,
		wfbID int64,
		actorID types.GlobalID,
		attempt int64,
		workflowMetadata *metadata.WorkflowMetadata,
	) (int64, error)
	PersistError(
		ctx context.Context,
		planID types.WorkflowExecutionID,
		wfbID int64,
		actorID types.GlobalID,
		attempt int64,
		completedAt time.Time,
	) (int64, error)
	Complete(ctx context.Context, workflowBuildDatabaseID int64, completedAt time.Time, azpCompletedAt time.Time, conclusion build.WorkflowState) error
	TransitionToQueued(ctx context.Context, workflowBuildDatabaseID int64, externalBuildID string, queuedAt time.Time) error
	SetWasDelayed(ctx context.Context, workflowBuildDatabaseID int64) error
	TransitionTo(ctx context.Context, workflowBuildDatabaseID int64, state build.WorkflowState, startedAt time.Time) error
	TransitionToError(ctx context.Context, workflowBuildDatabaseID int64, completedAt time.Time) error

	// test helper method
	GetByPlanIDForTests(ctx context.Context, planID types.WorkflowExecutionID) (*WorkflowBuildExecutionState, error)
}

type workflowBuildExecutionsRepository struct {
	db          *asql.SQL
	obs         *observability.Observability
	clock       clock.Clock
	gidMigrator GlobalIDMigrator
}

func NewWorkflowBuildExecutionsRepository(db *asql.SQL, obs *observability.Observability, clock clock.Clock, gidMigrator GlobalIDMigrator) *workflowBuildExecutionsRepository {
	return &workflowBuildExecutionsRepository{
		db:          db,
		obs:         obs,
		clock:       clock,
		gidMigrator: gidMigrator,
	}
}

// Persist writes a new workflow_build_execution row
func (r *workflowBuildExecutionsRepository) Persist(
	ctx context.Context,
	b *build.WorkflowBuild,
	wfbID int64,
	triggeringActorID types.GlobalID,
	attempt int64,
	workflowMetadata *metadata.WorkflowMetadata,
) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	now := r.clock.Now().UTC()

	triggeringActorNextID, err := r.gidMigrator.GetNextGlobalID(ctx, triggeringActorID.String())
	if err != nil {
		return -1, tracing.RecordError(span, errors.Wrap(err, "Failed to get next triggering actor id for workflowBuildExecutionsRepository"))
	}

	if triggeringActorID != triggeringActorNextID {
		r.logGlobalIDReplacement(ctx, "Persist", triggeringActorID, triggeringActorNextID)
	}

	// Not setting queued_at, started_at, completed_at, was_delayed.
	//
	// If this is being called due to a failed job, we'll get the same
	// webhook_delivery_id and workflow_build_id, but need to update
	// the other fields, except attempt because if we do then the `MAX(attempt)`
	// query currently in workflowbuilds.ResetWorkflowBuildState will
	// increase it unnecessarily

	const query = `
		INSERT INTO
			workflow_build_executions
		SET
			webhook_delivery_id=?,
			workflow_build_id=?,
			plan_id=?,
			external_build_id=?,
			triggering_actor_id=?,
			triggering_actor_next_id=?,
			attempt=?,
			created_at=?,
			reporting_metadata=CONVERT(? USING utf8),
			backend=?
		ON DUPLICATE KEY UPDATE
			plan_id=?,
			external_build_id=?,
			triggering_actor_id=?,
			triggering_actor_next_id=?
		`

	res, err := r.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("WorkflowBuildExecution-Persist"),
		b.WebhookDeliveryID,
		wfbID,
		b.ExecutionID,
		b.ExternalID,
		triggeringActorNextID,
		triggeringActorNextID,
		attempt,
		now,
		workflowMetadata,
		b.Backend,
		b.ExecutionID,
		b.ExternalID,
		triggeringActorNextID,
		triggeringActorNextID,
	)

	if err != nil {
		return 0, tracing.RecordError(span, err)
	}

	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return 0, tracing.RecordError(span, err)
	}

	var workflowDatabaseID int64
	switch rowsAffected {
	case 1:
		{
			workflowDatabaseID, err = res.LastInsertId()
			if err != nil {
				return 0, tracing.RecordError(span, err)
			}
		}

	// AffectedRows is 2 when a row was updated based on a ON UNIQUE KEY UPDATE statement
	// or 0 if that update didn't change the row. We generally would expect a 2 here.
	case 0, 2:
		{
			// An existing row was set to its current values. Vitess doesn't support LAST_INSERT_ID()
			// So we need to look up the DB ID that we hit with our duplicate key
			if err := r.db.QueryScanWith(
				ctx,
				"SELECT id FROM workflow_build_executions WHERE workflow_build_id=? AND webhook_delivery_id=?",
				asql.WithName("WorkflowBuildExecution-Persist-GetDBID"),
				asql.Params(wfbID, b.WebhookDeliveryID),
				&workflowDatabaseID,
			); err != nil {
				return 0, tracing.RecordError(span, errors.Wrap(err, "Could not read plan_id when persisting build execution"))
			}
		}
	}

	return workflowDatabaseID, nil
}

func (r *workflowBuildExecutionsRepository) PersistError(
	ctx context.Context,
	planID types.WorkflowExecutionID,
	wfbID int64,
	actorID types.GlobalID,
	attempt int64,
	completedAt time.Time,
) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	now := r.clock.Now().UTC()

	triggeringActorNextID, err := r.gidMigrator.GetNextGlobalID(ctx, actorID.String())
	if err != nil {
		return -1, tracing.RecordError(span, errors.Wrap(err, "Failed to get next triggering actor id for workflowBuildExecutionsRepository"))
	}

	if actorID != triggeringActorNextID {
		r.logGlobalIDReplacement(ctx, "PersistError", actorID, triggeringActorNextID)
	}

	const query = `INSERT INTO workflow_build_executions
		SET
			plan_id=?,
			workflow_build_id=?,
			triggering_actor_id=?,
			triggering_actor_next_id=?,
			attempt=?,
			state=?,
			completed_at=?,
			created_at=?`

	res, err := r.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("WorkflowBuildExecution-PersistError"),
		planID,
		wfbID,
		triggeringActorNextID,
		triggeringActorNextID,
		attempt,
		build.WorkflowStateFailed,
		completedAt,
		now,
	)
	if err != nil {
		return 0, tracing.RecordError(span, err)
	}
	id, err := res.LastInsertId()
	if err != nil {
		return 0, tracing.RecordError(span, err)
	}
	return id, nil
}

func (r *workflowBuildExecutionsRepository) Complete(
	ctx context.Context,
	workflowBuildDatabaseID int64,
	completedAt time.Time,
	azpCompletedAt time.Time,
	conclusion build.WorkflowState,
) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	stateSet := stateInList(conclusion)
	query := `UPDATE workflow_build_executions
		SET
			completed_at = ?,
			azp_completed_at = ?,
			state = ?
		WHERE
			workflow_build_id = ?
			AND completed_at IS NULL
			AND state IN (` + mysqldb.Placeholders(len(stateSet)) + `)
		ORDER BY id DESC
		LIMIT 1`
	args := []any{completedAt, azpCompletedAt, conclusion, workflowBuildDatabaseID}
	args = append(args, stateSet...)
	_, err := r.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("WorkflowBuildExecutions-Complete"),
		args...,
	)

	return tracing.RecordError(span, err)
}

func (r *workflowBuildExecutionsRepository) TransitionToQueued(
	ctx context.Context,
	workflowBuildDatabaseID int64,
	externalBuildID string,
	queuedAt time.Time,
) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `UPDATE workflow_build_executions
			SET
				state = ?,
				queued_at = ?,
				external_build_id = ?
			WHERE
				workflow_build_id = ?
				AND state = 0
			ORDER BY id DESC
			LIMIT 1`

	const operation = "WorkflowBuildExecutions-TransitionToQueued"
	_, err := mysqldb.WithDeadlockRetry(ctx, operation, r.obs.Statter, func() (sql.Result, error) {
		return r.db.ExecContextWith(
			ctx,
			query,
			asql.WithName(operation),
			build.WorkflowStateQueued,
			queuedAt,
			externalBuildID,
			workflowBuildDatabaseID,
		)
	})

	return tracing.RecordError(span, err)
}

func (r *workflowBuildExecutionsRepository) SetWasDelayed(
	ctx context.Context,
	workflowBuildDatabaseID int64,
) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `UPDATE workflow_build_executions
			SET was_delayed = true
			WHERE workflow_build_id = ?
			ORDER BY id DESC
			LIMIT 1`

	_, err := r.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("WorkflowBuildExecutions-SetWasDelayed"),
		workflowBuildDatabaseID,
	)

	return tracing.RecordError(span, err)
}

func (r *workflowBuildExecutionsRepository) TransitionTo(
	ctx context.Context,
	workflowBuildDatabaseID int64,
	state build.WorkflowState,
	startedAt time.Time,
) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var query, queryName string
	var queryVariables []any

	stateSet := stateInList(state)
	if state == build.WorkflowStateStarted {
		query = `UPDATE workflow_build_executions
			SET
				state = ?,
				started_at = ?
			WHERE
				workflow_build_id = ?
				AND state IN (` + mysqldb.Placeholders(len(stateSet)) + `)
			ORDER BY id DESC
			LIMIT 1`
		queryVariables = []any{state, startedAt, workflowBuildDatabaseID}
		queryName = "WorkflowBuildExecutions-TransitionToStarted"
	} else {
		query = `UPDATE workflow_build_executions
			SET
				state = ?
			WHERE
				workflow_build_id = ?
				AND state IN (` + mysqldb.Placeholders(len(stateSet)) + `)
			ORDER BY id DESC
			LIMIT 1`
		queryVariables = []any{state, workflowBuildDatabaseID}
		queryName = "WorkflowBuildExecutions-TransitionTo"
	}

	queryVariables = append(queryVariables, stateSet...)

	_, err := mysqldb.WithDeadlockRetry(ctx, queryName, r.obs.Statter, func() (sql.Result, error) {
		return r.db.ExecContextWith(ctx, query, asql.WithName(queryName), queryVariables...)
	})

	return tracing.RecordError(span, err)
}

func (r *workflowBuildExecutionsRepository) TransitionToError(ctx context.Context, workflowBuildDatabaseID int64, completedAt time.Time) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `UPDATE workflow_build_executions
		SET
			state = ?,
			completed_at = ?
		WHERE workflow_build_id = ?
		ORDER BY id DESC
		LIMIT 1`
	_, err := r.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("WorkflowBuildExecutions-TransitionToError"),
		build.WorkflowStateFailed,
		completedAt,
		workflowBuildDatabaseID,
	)

	return tracing.RecordError(span, err)
}

func stateInList(in build.WorkflowState) []any {
	out := make([]any, 0, int(in))
	for i := 0; i < int(in); i++ {
		out = append(out, i)
	}

	return out
}

func (r *workflowBuildExecutionsRepository) logGlobalIDReplacement(ctx context.Context, operation string, legacyGID, nextGID types.GlobalID) {
	r.obs.Counter(ctx, "global_ids.replace_wfbe_legacy_gid", statter.Tags{"operation": operation, "column": "triggering_actor_id"}, 1)
	r.obs.Debug(ctx, "Replacing legacy global id with next value for triggering_actor_id column",
		kvp.String("gh.launch.column", "triggering_actor_id"),
		kvp.String("gh.launch.legacy_global_id", legacyGID.String()),
		kvp.String("gh.launch.next_global_id", nextGID.String()))
}
