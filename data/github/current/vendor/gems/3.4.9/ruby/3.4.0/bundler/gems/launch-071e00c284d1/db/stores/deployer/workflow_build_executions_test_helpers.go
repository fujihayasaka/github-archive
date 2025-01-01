package deployer

import (
	"context"
	"database/sql"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

// GetByPlanIDForTests returns the workflow_build_execution for the passed in plan_id.
func (r *workflowBuildExecutionsRepository) GetByPlanIDForTests(ctx context.Context, planID types.WorkflowExecutionID) (*WorkflowBuildExecutionState, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `SELECT
			id,
			plan_id,
			webhook_delivery_id,
			external_build_id,
			workflow_build_id,
			created_at,
			queued_at,
			started_at,
			completed_at,
			state,
			was_delayed,
			triggering_actor_id,
			attempt,
			reporting_metadata,
			backend
		FROM workflow_build_executions
		WHERE plan_id = ?
		LIMIT 1`

	wbx := &WorkflowBuildExecutionState{}
	err := r.db.QueryScanWith(ctx, query,
		asql.WithName("WorkflowBuildExecution-GetByPlanIDForTests"),
		asql.Params(planID),
		&wbx.DatabaseID,
		&wbx.PlanID,
		&wbx.WebhookDeliveryID,
		&wbx.ExternalBuildID,
		&wbx.WorkflowBuildID,
		&wbx.CreatedAt,
		&wbx.QueuedAt,
		&wbx.StartedAt,
		&wbx.CompletedAt,
		&wbx.State,
		&wbx.WasDelayed,
		&wbx.TriggeringActorID,
		&wbx.Attempt,
		&wbx.WorkflowMetadata,
		&wbx.Backend,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}

		return nil, tracing.RecordError(span, err)
	}
	return wbx, nil
}
