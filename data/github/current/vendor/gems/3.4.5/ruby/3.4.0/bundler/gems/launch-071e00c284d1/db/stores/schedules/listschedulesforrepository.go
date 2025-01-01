package schedules

import (
	"context"
	"fmt"

	"github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	launchconfig "github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

// ListSchedulesForRepository lists up to 100 scheduled workflows for the given repository in the given environment
func (r *dbStore) ListSchedulesForRepository(ctx context.Context, env launchconfig.AppEnv, id types.GlobalID) ([]WorkflowSchedule, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repositoryNextID, repositoryNodeNextColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, id.String(), repositoryNodeColumnName)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to get next repository id and column for dbStore")
	}

	query := fmt.Sprintf(`
		SELECT
			id,
			schedule_hash,
			schedule_next_hash,
			repository_node_id,
			repository_next_id,
			workflow_identifier,
			workflow_file_path,
			environment,
			schedule,
			scatter_offset,
			next_run_at,
			commit_sha,
			actor_node_id,
			actor_next_id,
			actor_login,
			created_at,
			tier,
			tier_updated_at,
			owner_id
		FROM workflow_schedules
		WHERE %s = ? AND environment = ?
		LIMIT 100`, repositoryNodeNextColumn)

	rows, err := r.DB.QueryContextWith(ctx, query, asql.WithName("ListSchedulesForRepository"), repositoryNextID, env)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	defer rows.Close()

	workflowSchedules := make([]WorkflowSchedule, 0, 100)
	for rows.Next() {
		workflowSchedule := WorkflowSchedule{}
		err := rows.Scan(
			&workflowSchedule.ID,
			&workflowSchedule.ScheduleHash,
			&workflowSchedule.ScheduleNextHash,
			&workflowSchedule.RepositoryNodeID,
			&workflowSchedule.RepositoryNextID,
			&workflowSchedule.WorkflowIdentifier,
			&workflowSchedule.WorkflowFilePath,
			&workflowSchedule.Environment,
			&workflowSchedule.Schedule,
			&workflowSchedule.ScatterOffset,
			&workflowSchedule.NextRunAt,
			&workflowSchedule.CommitSHA,
			&workflowSchedule.ActorNodeID,
			&workflowSchedule.ActorNextID,
			&workflowSchedule.ActorLogin,
			&workflowSchedule.CreatedAt,
			&workflowSchedule.Tier,
			&workflowSchedule.TierUpdatedAt,
			&workflowSchedule.OwnerID)
		if err != nil {
			return nil, tracing.RecordError(span, err)
		}

		workflowSchedules = append(workflowSchedules, workflowSchedule)
	}

	if rows.Err() != nil {
		return nil, tracing.RecordError(span, rows.Err())
	}

	return workflowSchedules, nil
}
