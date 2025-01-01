package mysql

import (
	"context"
	"database/sql"

	"github.com/github/authnd/internal/common"
	"github.com/jmoiron/sqlx"
)

type hedgedExecutor struct {
	ex Executor
	hm common.HedgeManager
}

// NewHedgedExecutor executor implementation which automatic hedged read requests.
func NewHedgedExecutor(executor Executor) Executor {
	return &hedgedExecutor{
		ex: executor,
		hm: NewHedgeManager(),
	}
}

func (e *hedgedExecutor) ConnectionName() string {
	return e.ex.ConnectionName()
}

func (e *hedgedExecutor) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return withHedging(ctx,
		func(ctx context.Context) error {
			return e.ex.GetContext(ctx, dest, query, args...)
		},
		e.hm,
	)
}

func (e *hedgedExecutor) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return withHedging(ctx,
		func(ctx context.Context) error {
			return e.ex.SelectContext(ctx, dest, query, args...)
		},
		e.hm,
	)
}

func (e *hedgedExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	var row Row
	if err := withHedging(ctx,
		func(ctx context.Context) error {
			row = e.ex.QueryRowxContext(ctx, query, args...)
			return row.Err()
		},
		e.hm,
	); err != nil {
		row = &errorRow{err: err}
	}
	return row
}

func (e *hedgedExecutor) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	// We _do not_ want to hedge arbitrary Execs, as we don't know if they're idempotent.
	// We just pass them straight through.
	return e.ex.ExecContext(ctx, query, args...)
}

func (e *hedgedExecutor) unwrap() (*sqlx.DB, error) {
	return e.ex.unwrap()
}

func withHedging(ctx context.Context, operation func(context.Context) error, hedgeManager common.HedgeManager) error {
	return common.WithHedging(ctx, "api_store_lookup", operation, hedgeManager)
}
