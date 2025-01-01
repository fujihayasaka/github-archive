package transition20220516161326

import (
	"context"
	"database/sql"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-kvp"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/cmd/migratorctl/transitions/shared"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/dbmigrator"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/appcontext"
)

type Config struct {
	TransitionConfig shared.TransitionCfg

	IsDryRun bool  `config:",env=IS_DRY_RUN"`
	Min      int64 `config:"0,env=TRANSITION_MIN_ID"`
	Max      int64 `config:"0,env=TRANSITION_MAX_ID"`
}

type WorkflowBuildExecutionsQueryResult struct {
	ID                    int64
	TriggeringActorID     *types.GlobalID
	TriggeringActorNextID *types.GlobalID
}

const (
	NumWorkers = 10
)

func GetTransition(cfg *Config, db *sql.DB, getDeps shared.DependencyFunc, allowExternalCalls bool) dbmigrator.MigrationFunc {
	return func(rootCtx context.Context) error {
		// Skip running this transition if we can't make external service calls
		if !allowExternalCalls {
			return nil
		}

		deps, err := getDeps(rootCtx)
		if err != nil {
			return err
		}

		obs := deps.Obs
		defer deps.StopObs()
		dbThrottler := deps.DBThrottler
		ghTwirpClient := deps.GhTwirpClient

		min, err := getMinRow(cfg, db)
		if err != nil {
			return err
		}
		max, err := getMaxRow(cfg, db)
		if err != nil {
			return err
		}
		if !min.Valid || !max.Valid {
			obs.Log(rootCtx, "workflow build executions gid backfill: no rows found")
			return nil
		}

		g, ctx := errgroup.WithContext(rootCtx)

		// Create workers
		for i := 0; i < NumWorkers; i++ {
			workerID := i
			g.Go(
				func() error {
					delay := backoff.NewExponentialBackOff()
					b := backoff.WithMaxRetries(delay, 5)
					rowsProcessed := 0
					r := min.Int64 + int64(workerID)
					if r > max.Int64 {
						return nil
					}
					obs.Log(ctx, "wfbe gid backfill: start", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))

					for r <= max.Int64 {
						select {
						case <-ctx.Done():
							obs.Log(ctx, "workflow build executions gid backfill: context cancelled", kvp.Int("worker_id", workerID))
							return ctx.Err()

						default:
							requestID := uuid.New().String()
							ctx := appcontext.SetRequestID(ctx, requestID)

							err = shared.WaitOnThrottler(ctx, dbThrottler, rowsProcessed, 100)
							if err != nil {
								obs.Counter(ctx, "workflow_build_executions_gid_backfill", statter.Tags{"status": "error"}, 1)
								obs.Report(ctx, errors.New("workflow build executions gid backfill: got WaitOnThrottler error"), kvp.Int("worker_id", workerID), kvp.Err(err))

								return err
							}

							err = processRowWithRetries(ctx, obs, cfg, db, ghTwirpClient, b, r)
							if err != nil {
								obs.Counter(ctx, "workflow_build_executions_gid_backfill", statter.Tags{"status": "error"}, 1)
								obs.Report(ctx, errors.New("workflow build executions gid backfill: got processRowWithRetries error"), kvp.Int("worker_id", workerID), kvp.Err(err))
								return err
							}

							if rowsProcessed%10000 == 0 {
								obs.Log(ctx, "workflow build executions gid backfill: progress", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r), kvp.Int("rowsProcessed", rowsProcessed))
							}

							rowsProcessed++
							r += NumWorkers
							obs.Counter(ctx, "workflow_build_executions_gid_backfill", statter.Tags{"status": "success"}, 1)
						}
					}
					obs.Log(ctx, "wfbe gid backfill: reached end of table", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))
					return nil
				})
		}
		return g.Wait()
	}
}

func getMaxRow(cfg *Config, db *sql.DB) (sql.NullInt64, error) {
	var max sql.NullInt64
	if cfg.Max > 0 {
		max.Int64 = cfg.Max
		max.Valid = true
	} else {
		row := db.QueryRow("SELECT max(id) FROM workflow_build_executions")
		err := row.Scan(&max)
		if err != nil {
			return max, err
		}
	}
	return max, nil
}

func getMinRow(cfg *Config, db *sql.DB) (sql.NullInt64, error) {
	var min sql.NullInt64
	if cfg.Min > 0 {
		min.Int64 = cfg.Min
		min.Valid = true
	} else {
		row := db.QueryRow("SELECT min(id) FROM workflow_build_executions")
		err := row.Scan(&min)
		if err != nil {
			return min, err
		}
	}
	return min, nil
}

func processRowWithRetries(ctx context.Context, obs *observability.Observability, cfg *Config, db *sql.DB, ghTwirpClient ghtwirp.Client, b backoff.BackOff, currentSearchRow int64) error {
	processWorkflowBuildExecutionsRowOperation := func() error {
		err := processRow(ctx, cfg, db, obs, ghTwirpClient, currentSearchRow)
		if err != nil {
			obs.Error(ctx, "workflow builds gid backfill: attempt to process row failed", kvp.Err(err))
			return err
		}
		return nil
	}
	return backoff.Retry(processWorkflowBuildExecutionsRowOperation, b)
}

func processRow(ctx context.Context, cfg *Config, db *sql.DB, obs *observability.Observability, ghTwirpClient ghtwirp.Client, currentSearchRow int64) error {

	query := `SELECT id, triggering_actor_id, triggering_actor_next_id
	FROM workflow_build_executions
	WHERE id = ?`

	wfbe := &WorkflowBuildExecutionsQueryResult{}
	row := db.QueryRowContext(ctx, query, currentSearchRow)
	err := row.Scan(&wfbe.ID, &wfbe.TriggeringActorID, &wfbe.TriggeringActorNextID)
	if err != nil {
		// ignore gaps in the table
		if err == sql.ErrNoRows {
			obs.Log(ctx, "wfbe gid backfill: processed non-existent row", kvp.Int64("row_id", currentSearchRow))
			return nil
		}
		return err
	}

	if skipRow(wfbe) {
		return nil
	}

	triggeringActorNextID, err := shared.GetNextGlobalID(ctx, wfbe.TriggeringActorID.String(), wfbe.TriggeringActorNextID, ghTwirpClient)
	if err != nil {
		obs.Logger.Error(ctx, "retrieving workflow build executions triggering actor next ID", kvp.Err(err),
			kvp.Int64("row_id", wfbe.ID), kvp.String("triggering_actor_id", wfbe.TriggeringActorID.String()))
		return err
	}

	updateQuery := `UPDATE workflow_build_executions
	SET triggering_actor_next_id = ?
	WHERE id = ? AND triggering_actor_id = ? AND triggering_actor_next_id IS NULL`

	if !cfg.IsDryRun {
		const operation = "WorkflowBuildExecutionsGIDBackfill"
		result, err := mysqldb.WithDeadlockRetry(ctx, operation, obs.Statter, func() (sql.Result, error) {
			return db.ExecContext(ctx, updateQuery, triggeringActorNextID, wfbe.ID, wfbe.TriggeringActorID)
		})
		if err != nil {
			obs.Logger.Error(ctx, "failure updating row in workflow build executions", kvp.Int64("row_id", wfbe.ID), kvp.Err(err))
			return err
		}

		rowsAffected, err := result.RowsAffected()
		if err != nil {
			obs.Logger.Error(ctx, "error fetching rows affected in workflow build executions", kvp.Int64("row_id", wfbe.ID), kvp.Err(err))
			return err
		}
		if rowsAffected != 1 {
			obs.Logger.Error(ctx, "unexpected number of rows affected in workflow build executions", kvp.Int64("row_id", wfbe.ID), kvp.Int64("rows_affected", rowsAffected))
		}
	}

	return nil
}

func skipRow(queryResult *WorkflowBuildExecutionsQueryResult) bool {
	return queryResult.TriggeringActorID == nil || queryResult.TriggeringActorNextID != nil
}
