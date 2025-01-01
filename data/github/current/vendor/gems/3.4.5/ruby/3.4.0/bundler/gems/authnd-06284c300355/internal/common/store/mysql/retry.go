package mysql

import (
	"context"
	"database/sql"
	"database/sql/driver"

	"github.com/github/authnd/internal/common"
	"github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
)

const maxRetries = 5

// NewRetryableExecutor executor implementation which automatic retries read requests.
func NewRetryableExecutor(executor Executor) Executor {
	return &retryableExecutor{
		ex: executor,
	}
}

type retryableExecutor struct {
	ex Executor
}

func (e *retryableExecutor) ConnectionName() string {
	return e.ex.ConnectionName()
}

func (e *retryableExecutor) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return withRetries(ctx,
		func(ctx context.Context) error {
			return e.ex.GetContext(ctx, dest, query, args...)
		},
	)
}

func (e *retryableExecutor) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return withRetries(ctx,
		func(ctx context.Context) error {
			return e.ex.SelectContext(ctx, dest, query, args...)
		},
	)
}

func (e *retryableExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	var row Row
	if err := withRetries(ctx,
		func(ctx context.Context) error {
			row = e.ex.QueryRowxContext(ctx, query, args...)
			return row.Err()
		},
	); err != nil {
		row = &errorRow{err: err}
	}
	return row
}

func (e *retryableExecutor) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	// We _do not_ want to retry arbitrary Execs, as we don't know if they're idempotent.
	// We just pass them straight through.
	return e.ex.ExecContext(ctx, query, args...)
}

func (e *retryableExecutor) unwrap() (*sqlx.DB, error) {
	return e.ex.unwrap()
}

func withRetries(ctx context.Context, operation func(context.Context) error) error {
	return common.WithRetries(ctx, "api_store_lookup", operation, maxRetries, mysql.ErrInvalidConn, driver.ErrBadConn)
}
