package transition20220401225312

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
	"github.com/github/launch/db/stores/schedules"
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

type WorkflowSchedulesQueryResult struct {
	ID                 int64
	WorkflowIdentifier string
	WorkflowFilePath   string
	Schedule           string
	ScheduleHash       string
	ScheduleNextHash   *string
	RepositoryNodeID   types.GlobalID
	RepositoryNextID   *types.GlobalID
	ActorNodeID        types.GlobalID
	ActorNextID        *types.GlobalID
}

const (
	NumWorkers = 20
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
			obs.Log(rootCtx, "wfs gid backfill: no rows found")
			return nil
		}

		g, ctx := errgroup.WithContext(rootCtx)
		span := getSpan(min.Int64, max.Int64)

		// Create workers
		for i := 0; i < NumWorkers; i++ {
			workerID := i
			g.Go(
				func() error {
					delay := backoff.NewExponentialBackOff()
					b := backoff.WithMaxRetries(delay, 5)
					rowsProcessed := 0
					r := getStartingRow(workerID, min.Int64, span)
					if r > max.Int64 {
						return nil
					}
					obs.Log(ctx, "wfs gid backfill: start", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))

					spanEnd := spanEnd(workerID, min.Int64, max.Int64, span)
					for r < spanEnd && r <= max.Int64 {
						select {
						case <-ctx.Done():
							obs.Log(ctx, "wfs gid backfill: context cancelled", kvp.Int("worker_id", workerID))
							return ctx.Err()

						default:
							requestID := uuid.New().String()
							ctx := appcontext.SetRequestID(ctx, requestID)

							err = shared.WaitOnThrottler(ctx, dbThrottler, rowsProcessed, 100)
							if err != nil {
								obs.Counter(ctx, "workflow_schedules_gid_backfill", statter.Tags{"status": "error"}, 1)
								obs.Report(ctx, errors.New("wfs gid backfill: got WaitOnThrottler error"), kvp.Int("worker_id", workerID), kvp.Err(err))
								return err
							}

							err = processRowWithRetries(ctx, obs, cfg, db, ghTwirpClient, b, r)
							if err != nil {
								obs.Counter(ctx, "workflow_schedules_gid_backfill", statter.Tags{"status": "error"}, 1)
								obs.Report(ctx, errors.New("wfs gid backfill: got processRowWithRetries error"), kvp.Int("worker_id", workerID), kvp.Err(err))
								return err
							}

							if r%10000 == 0 {
								obs.Log(ctx, "wfs gid backfill: progress", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))
							}

							rowsProcessed++
							obs.Counter(ctx, "workflow_schedules_gid_backfill", statter.Tags{"status": "success"}, 1)
							nextRow, err := getNextRow(ctx, db, obs, b, r)
							if err != nil {
								if err == sql.ErrNoRows {
									obs.Log(ctx, "wfs gid backfill: reached max id", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))
									return nil
								}
								obs.Counter(ctx, "workflow_schedules_gid_backfill", statter.Tags{"status": "error"}, 1)
								obs.Report(ctx, errors.New("wfs gid backfill: got getNextRow error"), kvp.Int("worker_id", workerID), kvp.Err(err))
								return err
							}
							r = nextRow.Int64
						}
					}
					obs.Log(ctx, "wfs gid backfill: reached end of span", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))
					return nil
				})
		}

		return g.Wait()
	}
}

func getNextRow(ctx context.Context, db *sql.DB, obs *observability.Observability, b backoff.BackOff, floor int64) (sql.NullInt64, error) {
	var nextRow sql.NullInt64
	nextRowQuery := `SELECT id
	FROM workflow_schedules
	WHERE id > ?
	ORDER BY id
	ASC LIMIT 1
	`
	getNextRowOperation := func() error {
		row := db.QueryRowContext(ctx, nextRowQuery, floor)
		err := row.Scan(&nextRow)
		return err
	}

	err := backoff.Retry(getNextRowOperation, b)
	if err != nil {
		obs.Log(ctx, "wfs gid backfill: error getting next row", kvp.Int64("floor", floor), kvp.Err(err))
		return nextRow, err
	}

	if !nextRow.Valid {
		obs.Log(ctx, "wfs gid backfill: no next row found")
		return nextRow, errors.New("no next row found in workflow_schedules")
	}

	return nextRow, nil
}

func getMaxRow(cfg *Config, db *sql.DB) (sql.NullInt64, error) {
	var max sql.NullInt64
	if cfg.Max > 0 {
		max.Int64 = cfg.Max
		max.Valid = true
	} else {
		row := db.QueryRow("SELECT max(id) FROM workflow_schedules")
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
		row := db.QueryRow("SELECT min(id) FROM workflow_schedules")
		err := row.Scan(&min)
		if err != nil {
			return min, err
		}
	}
	return min, nil
}

func processRowWithRetries(ctx context.Context, obs *observability.Observability, cfg *Config, db *sql.DB, ghTwirpClient ghtwirp.Client, b backoff.BackOff, currentSearchRow int64) error {
	var err error
	processWorkflowSchedulesRowOperation := func() error {
		err = mysqldb.WithTransaction(ctx, db, obs.Statter, "backfill-wfs-next-global-id", func(tx *sql.Tx) error {
			err := processRow(ctx, cfg, tx, obs, ghTwirpClient, currentSearchRow)
			if err != nil {
				return err
			}
			return nil
		})
		if err != nil {
			obs.Error(ctx, "wfs backfill: attempt to process row failed", kvp.Err(err))
			return err
		}
		return nil
	}
	return backoff.Retry(processWorkflowSchedulesRowOperation, b)
}

func processRow(ctx context.Context, cfg *Config, tx *sql.Tx, obs *observability.Observability, ghTwirpClient ghtwirp.Client, currentSearchRow int64) error {
	query := `SELECT id, schedule_hash, schedule_next_hash, repository_node_id, repository_next_id, actor_node_id, actor_next_id, workflow_identifier, workflow_file_path, schedule
	FROM workflow_schedules
	WHERE id = ?
	LIMIT 1
	LOCK IN SHARE MODE`

	wfs := &WorkflowSchedulesQueryResult{}
	row := tx.QueryRowContext(ctx, query, currentSearchRow)
	err := row.Scan(&wfs.ID, &wfs.ScheduleHash, &wfs.ScheduleNextHash, &wfs.RepositoryNodeID, &wfs.RepositoryNextID, &wfs.ActorNodeID, &wfs.ActorNextID, &wfs.WorkflowIdentifier, &wfs.WorkflowFilePath, &wfs.Schedule)
	if err != nil {
		// workflow_schedules has gaps, so this is expected
		if err == sql.ErrNoRows {
			obs.Log(ctx, "wfs gid backfill: processed non-existent row", kvp.Int64("row_id", currentSearchRow))
			return nil
		}
		return err
	}
	if skipRow(wfs) {
		return nil
	}

	repositoryNextID, err := shared.GetNextGlobalID(ctx, wfs.RepositoryNodeID.String(), wfs.RepositoryNextID, ghTwirpClient)
	if err != nil {
		obs.Logger.Error(ctx, "retrieving workflow schedules check run next ID", kvp.Err(err),
			kvp.Int64("row_id", wfs.ID), kvp.String("check_run_id", wfs.RepositoryNextID.String()))
		return err
	}

	actorNextID, err := shared.GetNextGlobalID(ctx, wfs.ActorNodeID.String(), wfs.ActorNextID, ghTwirpClient)
	if err != nil {
		obs.Logger.Error(ctx, "retrieving workflow schedules check run next ID", kvp.Err(err),
			kvp.Int64("row_id", wfs.ID), kvp.String("check_run_id", wfs.RepositoryNextID.String()))
		return err
	}

	scheduleHashNext := schedules.NewScheduleHash(repositoryNextID, wfs.WorkflowIdentifier, wfs.WorkflowFilePath, wfs.Schedule)

	updateQuery := `UPDATE workflow_schedules
	SET schedule_next_hash = ?,
		repository_next_id = ?,
		actor_next_id = ?
	WHERE id = ?`

	if !cfg.IsDryRun {
		_, err = tx.ExecContext(ctx, updateQuery, scheduleHashNext, repositoryNextID, actorNextID, wfs.ID)
		if err != nil {
			obs.Logger.Error(ctx, "failure updating row in workflow schedules", kvp.Int64("row_id", wfs.ID), kvp.Err(err))
			return err
		}
	}

	return nil
}

func skipRow(queryResult *WorkflowSchedulesQueryResult) bool {
	if queryResult.RepositoryNextID == nil || queryResult.ActorNextID == nil || queryResult.ScheduleNextHash == nil {
		return false
	}

	return true
}

func getSpan(min int64, max int64) int64 {
	return (max - min) / NumWorkers
}

func getStartingRow(workerID int, min int64, span int64) int64 {
	return int64(workerID)*span + min
}

func spanEnd(workerID int, min int64, max int64, span int64) int64 {
	if workerID == NumWorkers-1 {
		return max + 1
	}
	return getStartingRow(workerID+1, min, span)
}
