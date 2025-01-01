package transition20220425220556

import (
	"context"
	"database/sql"

	"github.com/cenkalti/backoff/v4"
	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/github/go-kvp"
	"github.com/google/uuid"

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

type AZPResourcesQueryResult struct {
	ID           int64
	EntityID     types.GlobalID
	EntityNextID *types.GlobalID
}

const (
	NumWorkers = 5
)

func GetTransition(cfg *Config, db *sql.DB, getDeps shared.DependencyFunc, allowExternalCalls, continueOnKnownError bool) dbmigrator.MigrationFunc {
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
			obs.Log(rootCtx, "azpr gid backfill: no rows found")
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
					obs.Log(ctx, "azpr gid backfill: start", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))

					spanEnd := spanEnd(workerID, min.Int64, max.Int64, span)
					for r < spanEnd && r <= max.Int64 {
						select {
						case <-ctx.Done():
							obs.Log(ctx, "azpr gid backfill: context cancelled", kvp.Int("worker_id", workerID))
							return ctx.Err()

						default:
							requestID := uuid.New().String()
							ctx := appcontext.SetRequestID(ctx, requestID)

							err = shared.WaitOnThrottler(ctx, dbThrottler, rowsProcessed, 100)
							if err != nil {
								obs.Counter(ctx, "azp_resources_gid_backfill", statter.Tags{"status": "error"}, 1)
								obs.Report(ctx, errors.New("azpr gid backfill: got WaitOnThrottler erro"), kvp.Int("worker_id", workerID), kvp.Err(err))

								return err
							}
							r, err = processRowWithRetries(ctx, obs, cfg, db, ghTwirpClient, b, r, spanEnd)
							if err != nil {
								if err == sql.ErrNoRows {
									obs.Log(ctx, "azpr gid backfill: reached max id", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))
									return nil
								}
								if continueOnKnownError && isDuplicateEntryError(err) {
									obs.Report(ctx, errors.New("azpr gid backfill: got duplicate entry error"), kvp.Int("worker_id", workerID), kvp.Err(err))
								} else {
									obs.Counter(ctx, "azp_resources_gid_backfill", statter.Tags{"status": "error"}, 1)
									obs.Report(ctx, errors.New("azpr gid backfill: got processRowWithRetries error"), kvp.Int("worker_id", workerID), kvp.Err(err))
									return err
								}
							}

							if rowsProcessed%10000 == 0 {
								obs.Log(ctx, "azpr gid backfill: progress", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r), kvp.Int("rowsProcessed", rowsProcessed))
							}
							rowsProcessed++
							obs.Counter(ctx, "azp_resources_gid_backfill", statter.Tags{"status": "success"}, 1)
						}
					}
					obs.Log(ctx, "azpr gid backfill: reached end of span", kvp.Int("worker_id", workerID), kvp.Int64("row_id", r))
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
		row := db.QueryRow("SELECT max(id) FROM azp_resources")
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
		row := db.QueryRow("SELECT min(id) FROM azp_resources")
		err := row.Scan(&min)
		if err != nil {
			return min, err
		}
	}
	return min, nil
}

func processRowWithRetries(ctx context.Context, obs *observability.Observability, cfg *Config, db *sql.DB, ghTwirpClient ghtwirp.Client, b backoff.BackOff, floor, spanEnd int64) (int64, error) {
	var err error
	var processedRow int64
	processAzpResourcesRowOperation := func() error {
		err = mysqldb.WithTransaction(ctx, db, obs.Statter, "backfill-azpr-next-global-id", func(tx *sql.Tx) error {
			processedRow, err = processRow(ctx, cfg, tx, obs, ghTwirpClient, floor, spanEnd)
			return err
		})
		if err != nil {
			obs.Error(ctx, "azpr gid backfill: attempt to process row failed", kvp.Err(err))
			return err
		}
		return err
	}
	err = backoff.Retry(processAzpResourcesRowOperation, b)
	return processedRow, err
}

func processRow(ctx context.Context, cfg *Config, tx *sql.Tx, obs *observability.Observability, ghTwirpClient ghtwirp.Client, floor, spanEnd int64) (int64, error) {
	query := `SELECT id, entity_id, entity_next_id
	FROM azp_resources
	WHERE id > ? AND id <= ?
	ORDER BY id ASC
	LIMIT 1
	LOCK IN SHARE MODE`

	azpr := &AZPResourcesQueryResult{}
	row := tx.QueryRowContext(ctx, query, floor, spanEnd)
	err := row.Scan(&azpr.ID, &azpr.EntityID, &azpr.EntityNextID)
	if err != nil {
		return 0, err
	}

	if skipRow(azpr) {
		return azpr.ID, nil
	}

	entityNextID, err := shared.GetNextGlobalID(ctx, azpr.EntityID.String(), azpr.EntityNextID, ghTwirpClient)
	if err != nil {
		obs.Logger.Error(ctx, "azpr gid backfill: retrieving azp resources entity next ID", kvp.Err(err),
			kvp.Int64("row_id", azpr.ID), kvp.String("entity_id", azpr.EntityID.String()))
		return 0, err
	}

	updateQuery := `UPDATE azp_resources
	SET entity_next_id = ?
	WHERE id = ?`

	if !cfg.IsDryRun {
		const operation = "AzpResourcesGIDBackfill"
		_, err = mysqldb.WithDeadlockRetry(ctx, operation, obs.Statter, func() (sql.Result, error) {
			return tx.ExecContext(ctx, updateQuery, entityNextID, azpr.ID)
		})
		if err != nil {
			obs.Logger.Error(ctx, "azpr gid backfill: failure updating row in azp resources", kvp.Int64("row_id", azpr.ID), kvp.Err(err))
			return azpr.ID, err
		}
	}

	return azpr.ID, nil
}

func isDuplicateEntryError(err error) bool {
	if driverErr, ok := err.(*mysql.MySQLError); ok {
		return driverErr.Number == 1062
	}
	return false
}

func skipRow(queryResult *AZPResourcesQueryResult) bool {
	return queryResult.EntityNextID != nil
}

func getSpan(min int64, max int64) int64 {
	return (max - min) / NumWorkers
}

func getStartingRow(workerID int, min int64, span int64) int64 {
	return int64(workerID)*span + min - 1
}

func spanEnd(workerID int, min int64, max int64, span int64) int64 {
	if workerID == NumWorkers-1 {
		return max + 1
	}
	return getStartingRow(workerID+1, min, span)
}
