package transition20220322142609

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

type WorkflowBuildQueryResult struct {
	ID               int64
	RepositoryID     types.GlobalID
	RepositoryNextID *types.GlobalID
	CheckSuiteID     *types.GlobalID
	CheckSuiteNextID *types.GlobalID
	ActorID          *types.GlobalID
	ActorNextID      *types.GlobalID
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
			obs.Log(rootCtx, "workflow builds gid backfill: no rows found")
			return nil
		}

		currentSearchRow := min.Int64

		g, ctx := errgroup.WithContext(rootCtx)
		rows := make(chan int64, 1)

		// Create workers
		for i := 0; i < NumWorkers; i++ {
			workerID := i
			g.Go(
				func() error {
					delay := backoff.NewExponentialBackOff()
					b := backoff.WithMaxRetries(delay, 5)
					rowsProcessed := 0
					for {
						select {
						case <-ctx.Done():
							obs.Log(ctx, "workflow builds gid backfill: context cancelled", kvp.Int("worker_id", workerID))
							return ctx.Err()

						case r, ok := <-rows:
							if !ok {
								obs.Log(ctx, "workflow builds gid backfill: no more rows to process", kvp.Int("worker_id", workerID))
								return nil
							}
							requestID := uuid.New().String()
							ctx := appcontext.SetRequestID(ctx, requestID)

							err = shared.WaitOnThrottler(ctx, dbThrottler, rowsProcessed, 100)
							if err != nil {
								obs.Counter(ctx, "workflow_builds_gid_backfill", statter.Tags{"status": "error"}, 1)
								obs.Report(ctx, errors.Wrap(err, "workflow builds gid backfill: got WaitOnThrottler error"), kvp.Int("worker_id", workerID))
								return err
							}

							err = processRowWithRetries(ctx, obs, cfg, db, ghTwirpClient, b, r)
							if err != nil {
								obs.Counter(ctx, "workflow_builds_gid_backfill", statter.Tags{"status": "error"}, 1)
								obs.Report(ctx, errors.Wrap(err, "workflow builds gid backfill: got processRowWithRetries error"), kvp.Int("worker_id", workerID))
								return err
							}

							if r%10000 == 0 {
								obs.Log(ctx, "workflow builds gid backfill: progress", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))
							}

							rowsProcessed++
							obs.Counter(ctx, "workflow_builds_gid_backfill", statter.Tags{"status": "success"}, 1)
						}
					}
				})
		}

		// Start a goroutine to send rows to the workers
		go func() {
			defer close(rows)
			for currentSearchRow <= max.Int64 {
				select {
				case <-rootCtx.Done():
					return
				default:
					rows <- currentSearchRow
					currentSearchRow++
				}
			}
		}()

		return g.Wait()
	}
}

func getMaxRow(cfg *Config, db *sql.DB) (sql.NullInt64, error) {
	var max sql.NullInt64

	if cfg.Max > 0 {
		max.Int64 = cfg.Max
		max.Valid = true
	} else {
		row := db.QueryRow("SELECT max(id) FROM workflow_builds")
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
		row := db.QueryRow("SELECT min(id) FROM workflow_builds")
		err := row.Scan(&min)
		if err != nil {
			return min, err
		}
	}
	return min, nil
}

func processRowWithRetries(ctx context.Context, obs *observability.Observability, cfg *Config, db *sql.DB, ghTwirpClient ghtwirp.Client, b backoff.BackOff, currentSearchRow int64) error {
	var err error
	processWorkflowBuildsRowOperation := func() error {
		err = mysqldb.WithTransaction(ctx, db, obs.Statter, "backfill-wfb-next-global-id", func(tx *sql.Tx) error {
			err := processRow(ctx, cfg, tx, obs, ghTwirpClient, currentSearchRow)
			if err != nil {
				return err
			}
			return nil
		})
		if err != nil {
			obs.Error(ctx, "workflow builds gid backfill: attempt to process row failed", kvp.Err(err))
			return err
		}
		return nil
	}
	return backoff.Retry(processWorkflowBuildsRowOperation, b)
}

func processRow(ctx context.Context, cfg *Config, tx *sql.Tx, obs *observability.Observability, ghTwirpClient ghtwirp.Client, currentSearchRow int64) error {
	query := `SELECT id, repository_id, repository_next_id, check_suite_id, check_suite_next_id, executing_actor_id, executing_actor_next_id
	FROM workflow_builds
	WHERE id >= ?
	ORDER BY id
	LIMIT 1
	LOCK IN SHARE MODE`

	wfb := &WorkflowBuildQueryResult{}
	row := tx.QueryRowContext(ctx, query, currentSearchRow)
	err := row.Scan(&wfb.ID, &wfb.RepositoryID, &wfb.RepositoryNextID, &wfb.CheckSuiteID, &wfb.CheckSuiteNextID, &wfb.ActorID, &wfb.ActorNextID)
	if err != nil {
		return err
	}

	if skipRow(wfb) {
		return nil
	}

	repoNextID, err := shared.GetNextGlobalID(ctx, wfb.RepositoryID.String(), wfb.RepositoryNextID, ghTwirpClient)
	if err != nil {
		obs.Error(ctx, "workflow builds gid backfill: retrieving repository next ID", kvp.Err(err),
			kvp.Int64("row_id", wfb.ID), kvp.String("repository_id", wfb.RepositoryID.String()))
		return err
	}

	var checkSuiteNextID *types.GlobalID
	if wfb.CheckSuiteID != nil {
		nextID, err := shared.GetNextGlobalID(ctx, wfb.CheckSuiteID.String(), wfb.CheckSuiteNextID, ghTwirpClient)
		if err != nil {
			obs.Error(ctx, "workflow builds gid backfill: retrieving check suite next ID", kvp.Err(err),
				kvp.Int64("row_id", wfb.ID), kvp.String("check_suite_id", wfb.CheckSuiteID.String()))
			return err
		}

		checkSuiteNextID = &nextID
	}

	var actorNextID *types.GlobalID
	if wfb.ActorID != nil {
		nextID, err := shared.GetNextGlobalID(ctx, wfb.ActorID.String(), wfb.ActorNextID, ghTwirpClient)
		if err != nil {
			obs.Error(ctx, "workflow builds gid backfill: retrieving actor next ID", kvp.Err(err),
				kvp.Int64("row_id", wfb.ID), kvp.String("actor_id", wfb.ActorID.String()))
			return err
		}

		actorNextID = &nextID
	}

	updateQuery := `UPDATE workflow_builds
	SET repository_next_id = ?,
	check_suite_next_id = ?,
	executing_actor_next_id = ?
	WHERE id = ?`

	if !cfg.IsDryRun {
		_, err = tx.ExecContext(ctx, updateQuery, repoNextID, checkSuiteNextID, actorNextID, wfb.ID)
		if err != nil {
			obs.Error(ctx, "workflow builds gid backfill: failure updating row", kvp.Int64("row_id", wfb.ID), kvp.Err(err))
			return err
		}
	}

	return nil
}

func skipRow(queryResult *WorkflowBuildQueryResult) bool {
	if queryResult.RepositoryNextID == nil {
		return false
	}

	// Check suite and executing actor columns can be NULL
	if queryResult.CheckSuiteID != nil && queryResult.CheckSuiteNextID == nil {
		return false
	}

	if queryResult.ActorID != nil && queryResult.ActorNextID == nil {
		return false
	}

	return true
}
