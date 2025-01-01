package mysql

import (
	"context"
	"database/sql"

	"github.com/github/authnd/internal/common/db"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

type transactionExecutor struct {
	ex Executor
}

// NewTransactionExecutor executor implementation which can handle mysql transactions.
func NewTransactionExecutor(executor Executor) TransactionExecutor {
	return &transactionExecutor{
		ex: executor,
	}
}

func (e *transactionExecutor) ConnectionName() string {
	return e.ex.ConnectionName()
}

func (e *transactionExecutor) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return e.ex.GetContext(ctx, dest, query, args...)
}

func (e *transactionExecutor) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return e.ex.SelectContext(ctx, dest, query, args...)
}

func (e *transactionExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	return e.ex.QueryRowxContext(ctx, query, args...)
}

func (e *transactionExecutor) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	return e.ex.ExecContext(ctx, query, args...)
}

func (e *transactionExecutor) unwrap() (*sqlx.DB, error) {
	return e.ex.unwrap()
}

func (e *transactionExecutor) WithTransaction(ctx context.Context, fn func(Executor) error) error {
	unwrappedDB, err := e.ex.unwrap()
	if err != nil {
		return errors.Wrap(err, "unable to start transaction")
	}

	return db.WithTransaction(ctx, unwrappedDB,
		func(t *sqlx.Tx) error {
			// wrap the provided *sqlx.Tx so it can be used as an Executor w/ automatic tracing
			// we DON'T want to include automatic hedging (or retries) because we're working within a transaction
			// which means our requests live within one open connection.
			ex := NewTracingExecutor(baseTransactionExecutor{e.ConnectionName(), t})
			return fn(ex)
		},
	)
}

type baseTransactionExecutor struct {
	name string
	*sqlx.Tx
}

func (e baseTransactionExecutor) ConnectionName() string {
	return e.name
}

func (e baseTransactionExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	return e.Tx.QueryRowxContext(ctx, query, args...)
}

// there's no way to unwrap the sqlx.DB object because this is a transaction.  This is fine because
// unwrapping is only used for adapting the WithTransaction call in the TransactionExecutor.
// That should never happen because shouldn't be attempting nested transactions.
// The only way we can get there is:
// - initiate a transaction with TransactionExecutor.WithTransaction
// - interface upgrade the Executor to a TransactionExecutor in the passed transaction function
// - call WithTransaction again
func (e baseTransactionExecutor) unwrap() (*sqlx.DB, error) {
	return nil, errors.New("attempting to unwrap transaction executor from within an existing transaction: not allowed!")
}
