package main

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mysql_dual"
	"golang.org/x/sync/errgroup"
)

// deleteStaleData deletes any data that is older than a week and not connected to any other records
func deleteStaleData(ctx context.Context, db *mysql_dual.Connection) error {
	// clean up stale data in order so that each set of data deleted then causes the next set of data to be
	// correctly identified as stale.

	if err := deleteRows(ctx, db, "tg_contributions", func(start, end uint64) (sql.Result, error) {
		return db.Primary.ExecContext(ctx, `DELETE FROM tg_contributions
WHERE pushed_at < DATE(NOW() - INTERVAL 100 DAY)
  AND id BETWEEN ? AND ?`, start, end)
	}, 100_000); err != nil {
		return err
	}

	if err := deleteRows(ctx, db, "tg_repositories", func(start, end uint64) (sql.Result, error) {
		return db.Primary.ExecContext(ctx, `DELETE FROM tg_repositories
WHERE repository_id NOT IN (SELECT repository_id FROM tg_contributions)
  AND id BETWEEN ? AND ?`, start, end)
	},
		100_000); err != nil {
		return err
	}

	if err := deleteRows(ctx, db, "tg_purchasers", func(start, end uint64) (sql.Result, error) {
		return db.Primary.ExecContext(ctx, `DELETE FROM tg_purchasers
WHERE owner_id NOT IN (SELECT owner_id FROM tg_repositories)
  AND id BETWEEN ? AND ?`, start, end)
	},
		100_000); err != nil {
		return err
	}

	// we can run these deletes in parallel as they do not depend on the same data
	{
		g, ctx := errgroup.WithContext(ctx)

		if fromctx.Env.Value(ctx).IsTest() {
			// restrict concurrency when running in tests
			// when using transaction connections we can get deadlocks that do not happen in production
			g.SetLimit(1)
		}

		g.Go(func() error {
			return deleteRows(ctx, db, "tg_users", func(start, end uint64) (sql.Result, error) {
				return db.Primary.ExecContext(ctx, `DELETE FROM tg_users
WHERE user_id NOT IN (SELECT  user_id FROM tg_contributions)
  AND user_id NOT IN (SELECT owner_id FROM tg_repositories)
  AND user_id NOT IN (SELECT owner_id FROM tg_purchasers)
  AND id BETWEEN ? AND ?`, start, end)
			},
				100_000)
		})

		g.Go(func() error {
			return deleteRows(ctx, db, "tg_entities", func(start, end uint64) (sql.Result, error) {
				return db.Primary.ExecContext(ctx, `DELETE FROM tg_entities
WHERE NOT EXISTS (SELECT 1 FROM tg_purchasers WHERE tg_purchasers.entity_id = tg_entities.entity_id AND tg_purchasers.entity_type = tg_entities.entity_type)
  AND id BETWEEN ? AND ?`, start, end)
			},
				100_000)
		})

		if err := g.Wait(); err != nil {
			return err
		}
	}

	return nil
}

func deleteRows(ctx context.Context, db *mysql_dual.Connection, table string, fn func(start, end uint64) (sql.Result, error), step uint64) error {
	statter := fromctx.Statter.Value(ctx)

	started := time.Now()

	defer func() {
		statter.Timing("sync.delete", stats.Tags{"table": table}, time.Since(started))
	}()

	return retryInBatches(ctx, db, table, step, func(ctx context.Context, start, end uint64) error {
		res, err := fn(start, end)
		if err != nil {
			return err
		}
		rows, err := res.RowsAffected()
		if err != nil {
			return err
		}

		statter.Counter("sync.deleted", stats.Tags{"table": table}, rows)

		if rows > 0 {
			fromctx.Logger.Value(ctx).Info("deleted stale data", kvp.String("table", table), kvp.Int64("rows_affected", rows))
		}

		return nil
	})
}
