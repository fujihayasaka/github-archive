package databasebackfills

import (
	"context"
	"database/sql"
	"fmt"

	throttler "github.com/github/go-freno-client"
	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
)

type Runner struct {
	obs         *observability.Observability
	conn        *sql.DB
	dbThrottler throttler.Throttler
}

type queryResult struct {
	Count int64
}

func New(obs *observability.Observability, conn *sql.DB, dbThrottler throttler.Throttler) *Runner {
	return &Runner{
		obs:         obs,
		conn:        conn,
		dbThrottler: dbThrottler,
	}
}

func (r *Runner) RunDeleteWorkflowSchedulesWithoutActor(ctx context.Context) error {
	result, err := r.deleteWorkflowSchedulesWithoutActor(ctx)
	if err != nil {
		r.obs.Error(ctx, "error deleting workflow schedule rows", kvp.Err(err))
		return err
	}

	r.obs.Log(ctx, "successfully deleted missing actor ids", kvp.Int64("count", result.Count))
	return nil
}

func (r *Runner) deleteWorkflowSchedulesWithoutActor(ctx context.Context) (*queryResult, error) {
	query := `DELETE FROM workflow_schedules WHERE actor_node_id="" LIMIT 100;`
	return r.runQuery(ctx, query)
}

func (r *Runner) RunBackfillWorkflowBuildsCreatedAt(ctx context.Context) error {
	result, err := r.backfillWorkflowBuildsCreatedAt(ctx)
	if err != nil {
		r.obs.Error(ctx, "error backfilling created at", kvp.Err(err))
		return err
	}

	r.obs.Log(ctx, "successfully backfilled created_at", kvp.Int64("count", result.Count))
	return nil
}

func (r *Runner) backfillWorkflowBuildsCreatedAt(ctx context.Context) (*queryResult, error) {
	query := `UPDATE workflow_builds
	SET created_at=queued_at
	WHERE created_at IS NULL
	AND provider="azp"
	AND queued_at IS NOT NULL
	LIMIT 100`

	return r.runQuery(ctx, query)
}

func (r *Runner) RunAzpResourcesBackfill(ctx context.Context, newColumn string, sourceColumn string) error {
	query := fmt.Sprintf(
		"UPDATE azp_resources SET %s=%s WHERE %s is NULL AND %s IS NOT NULL LIMIT 100",
		newColumn,
		sourceColumn,
		newColumn,
		sourceColumn,
	)

	if sourceColumn != "locked_at" {
		query = fmt.Sprintf(
			"UPDATE azp_resources SET %s=%s WHERE %s is NULL AND %s IS NOT NULL AND locked_at IS NULL LIMIT 100",
			newColumn,
			sourceColumn,
			newColumn,
			sourceColumn,
		)
	}

	result, err := r.runQuery(ctx, query)
	if err != nil {
		r.obs.Error(ctx, fmt.Sprintf("error backfilling %s in azp_resources", newColumn), kvp.Err(err))
		return err
	}

	r.obs.Log(
		ctx,
		fmt.Sprintf("successfully backfilled %s in azp_resources", newColumn),
		kvp.Int64("count", result.Count),
	)
	return nil
}

func (r *Runner) RunAzpResourcesDeleteBlank(ctx context.Context, targetColumn string) error {
	query := fmt.Sprintf("DELETE FROM azp_resources WHERE %s = ''", targetColumn)

	result, err := r.runQuery(ctx, query)
	if err != nil {
		r.obs.Error(
			ctx,
			fmt.Sprintf("error deleting rows with blank `%s` in azp_resources", targetColumn),
			kvp.Err(err),
		)
		return err
	}

	r.obs.Log(
		ctx,
		fmt.Sprintf("successfully deleted rows with blank `%s` in azp_resources", targetColumn),
		kvp.Int64("count", result.Count),
	)
	return nil
}

func (r *Runner) runQuery(ctx context.Context, query string) (*queryResult, error) {
	resultCount := &queryResult{
		Count: 0,
	}

	for {
		canWrite, err := r.dbThrottler.CanWrite(ctx)
		if err != nil {
			return resultCount, err
		}

		if !canWrite {
			r.obs.Log(ctx, "cannot write, waiting on throttler...")
			err := throttler.WaitOnThrottler(ctx, r.dbThrottler)
			if err != nil {
				return resultCount, err
			}
			r.obs.Log(ctx, "done waiting on throtttler")
		} else {
			result, err := r.conn.ExecContext(ctx, query)
			if err != nil {
				return resultCount, err
			}

			rowsAffected, err := result.RowsAffected()
			if err != nil {
				return resultCount, err
			}

			if rowsAffected == 0 {
				break
			}

			resultCount.Count += rowsAffected
		}
	}

	return resultCount, nil
}
