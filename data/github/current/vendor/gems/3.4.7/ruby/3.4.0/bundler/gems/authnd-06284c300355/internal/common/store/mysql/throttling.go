package mysql

import (
	"context"
	"database/sql"

	"github.com/github/authnd/internal/common"
	freno "github.com/github/go-freno-client"
	"github.com/jmoiron/sqlx"
)

type throttlingExecutor struct {
	ex        Executor
	throttler freno.Throttler
}

// NewThrottlingExecutor executor implementation with automatic throttling of writes
// based on the status provided by the given freno.Throttler. Additionally, transactions
// are throttled at the time they are initiated, not when they are committed.  Reads
// are not throttled.
func NewThrottlingExecutor(executor Executor, throttler freno.Throttler) Executor {
	return &throttlingExecutor{
		ex:        executor,
		throttler: throttler,
	}
}

func (e *throttlingExecutor) ConnectionName() string {
	return e.ex.ConnectionName()
}

func (e *throttlingExecutor) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	// read requests aren't throttled
	return e.ex.GetContext(ctx, dest, query, args...)
}

func (e *throttlingExecutor) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	// read requests aren't throttled
	return e.ex.SelectContext(ctx, dest, query, args...)
}

func (e *throttlingExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	// read requests aren't throttled
	return e.ex.QueryRowxContext(ctx, query, args...)
}

func (e *throttlingExecutor) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	var result sql.Result
	var err error
	err = common.WithThrottling(ctx, e.throttler, func() error {
		result, err = e.ex.ExecContext(ctx, query, args...)
		return err
	})
	return result, err
}

func (e *throttlingExecutor) unwrap() (*sqlx.DB, error) {
	db, err := e.ex.unwrap()
	if err != nil {
		return nil, err
	}

	err = common.WithThrottling(context.Background(), e.throttler, func() error {
		// do nothing.  we're using this as a way to check whether writes are throttled
		// before unwrapping the DB for usage in a new transaction.  the new transaction
		// gets an unthrottled executor instance, so we need to check before returning
		// the unprotected DB.
		return nil
	})
	if err != nil {
		return nil, err
	}
	return db, nil
}
