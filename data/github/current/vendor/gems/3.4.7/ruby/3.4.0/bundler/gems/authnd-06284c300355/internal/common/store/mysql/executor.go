package mysql

import (
	"context"
	"database/sql"

	"github.com/jmoiron/sqlx"
)

// Executor an executor can execute mysql queries.  "database/sqlx.DB" and "sqlx.Tx" implement this interface.
type Executor interface {
	ConnectionName() string
	GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error
	SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error
	QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row
	ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error)
	unwrap() (*sqlx.DB, error)
}

// Row minimal representation of a row returned by a Query. "sqlx.Row" implements this interface.
type Row interface {
	Scan(dest ...interface{}) error
	Err() error
}

// TransactionExecutor an executor can execute mysql queries and initiate transactions.  "database/sqlx.DB" implements this interface.
type TransactionExecutor interface {
	Executor
	WithTransaction(ctx context.Context, fn func(Executor) error) error
}

// NewDefaultExecutor default executor implementation which contains spans for tracing and automatic retries for read requests, in
// addition to any options provided by the user.
func NewDefaultExecutor(name string, db *sqlx.DB, opts ...ExecutorOption) Executor {
	// apply default options in addition to user provided options
	opts = append(opts,
		WithHedging(),
		WithRetries(),
		WithTracing(),
		WithDetachedContext(),
	)

	return NewExecutor(name, db, opts...)
}

// NewExecutor construct an executor with the provided options
func NewExecutor(name string, db *sqlx.DB, opts ...ExecutorOption) Executor {
	var eo executorOptions
	for _, apply := range opts {
		apply(&eo)
	}

	// options are applied to the base executor in a specific order for correctness. Layers are executed
	// in the reverse order of application.
	var e Executor = baseExecutor{name, db}
	if eo.detachedContext {
		e = NewDetachedContextExecutor(e)
	}
	if eo.throttler != nil {
		e = NewThrottlingExecutor(e, eo.throttler)
	}
	if eo.tracing {
		e = NewTracingExecutor(e)
	}
	if eo.retries {
		e = NewRetryableExecutor(e)
	}
	if eo.hedging {
		e = NewHedgedExecutor(e)
	}
	return e
}

// NewDefaultTransactionExecutor default executor implementation which contains spans for tracing and automatic retries for read requests,
// but can also wrap requests in a transaction.
func NewDefaultTransactionExecutor(name string, db *sqlx.DB, opts ...ExecutorOption) TransactionExecutor {
	return NewTransactionExecutor(
		NewDefaultExecutor(name, db, opts...),
	)
}

type baseExecutor struct {
	name string
	*sqlx.DB
}

func (e baseExecutor) ConnectionName() string {
	return e.name
}

func (e baseExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	return e.DB.QueryRowxContext(ctx, query, args...)
}

func (e baseExecutor) unwrap() (*sqlx.DB, error) {
	return e.DB, nil
}

type errorRow struct {
	err error
}

func (r errorRow) Scan(dest ...interface{}) error {
	return r.err
}

func (r errorRow) Err() error {
	return r.err
}
