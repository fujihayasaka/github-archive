package upgrades

import (
	"context"
	"database/sql"
	"sync/atomic"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
)

// DB exposes functions that we are happy for transitions to use (the ones that take a context).
// This also allows us to pass in wrappers for the underlying database driver that count the rows that were
// modified and throttle the database use between writes.
type DB interface {
	ExecContext(ctx context.Context, stmt string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

type rowsAffectedDB struct {
	*throttleDB
	totalRowsAffected int64
}

func (r *rowsAffectedDB) ExecContext(ctx context.Context, stmt string, args ...any) (sql.Result, error) {
	res, err := r.throttleDB.ExecContext(ctx, stmt, args...)
	if err != nil {
		return res, err
	}
	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return res, err
	}

	atomic.AddInt64(&r.totalRowsAffected, rowsAffected)

	return res, nil
}

// Function runs fn repeatedly for ranges of IDs in turn.
// The table described by tableName must have a primary key named 'id' to calculate these ranges.
// fn is given methods to query and update the database.
// The function you write should try to avoid any N+1 queries, doing the work in bulk wherever possible.
// It will be throttled each time it executes a query and will automatically retry when an error is returned.
func (t *transitions) Function(tableName string, fn func(ctx context.Context, db DB, start, end uint64) error) Builder {
	defaultStep := t.step

	return t.add(func(env *Env, opts *Opts) (func(ctx context.Context) error, error) {
		return withTimeout(opts.Timeout, func(ctx context.Context, heartbeatFn heartbeatFunc) error {
			idRange, err := getIDRange(ctx, env, opts, tableName)
			if err != nil {
				return err
			}

			step := defaultStep
			if opts.Step > 0 {
				step = opts.Step
			}

			return withBatchedLoop(ctx, heartbeatFn, idRange, step, func(ctx context.Context, minId, maxId uint64) error {
				return withDynamicRetry(ctx, opts.Delay, minId, maxId, func(start, end uint64) error {
					db := &rowsAffectedDB{
						throttleDB: env.db,
					}

					err := fn(ctx, db, start, end)

					appctx.Logger(ctx).WithError(err).Info("Updated rows", kvp.Int64("gh.turboscan.rows_affected", db.totalRowsAffected))

					return err
				})
			})
		}), nil
	})
}
