// Package transaction simplifies the lifetime control of database transactions.
package transaction

import (
	"context"
	"database/sql"

	"github.com/hashicorp/go-multierror"
	"github.com/jmoiron/sqlx"

	"github.com/github/notifyd/internal/pkg/errors"
)

/*
Transaction simplifies the lifetime control of database transactions so that their usage is simpler
and safer.

Their usage is based on a callback that either succeeds or fail, in case of success the transaction
is committed, otherwise it is rolled back.

Example:

	transaction := New()
	err := transaction.Run(func (txx *sqlx.Tx) error {
		if err := repo.insert(ctx, txx, listOfElements); err != nil {
			return err
		}

		if err := repo.delete(ctx, txx, listOfOldElements); err != nil {
			return err
		}

		return nil
	})

In case `repo.insert()` or `repo.delete` fail, the transaction is rolled back, if both succeed, then
the transaction is committed.

See `rollback` to get details on the possible errors.
*/
type Transaction struct{}

// New creates a new transaction.
func New() Transaction {
	return Transaction{}
}

// Run executes the transaction.
func (t Transaction) Run(ctx context.Context, store *sqlx.DB, fn func(txx *sqlx.Tx) error) error {
	txx, err := store.BeginTxx(ctx, &sql.TxOptions{})
	if err != nil {
		return errors.Wrap(err, "can't begin transaction")
	}

	if err := fn(txx); err != nil {
		return rollback(txx, err)
	}

	if err := txx.Commit(); err != nil {
		return errors.Wrap(err, "can't commit transaction")
	}

	return nil
}

// rollback issues a `ROLLBACK` to the database. In case it fails it returns a multierror
// containing:
//
// - The error that caused the rollback.
// - The error that the rollback operation returned.
//
// In case the rollback operation succeeds it returns the error that caused the rollback.
func rollback(txx *sqlx.Tx, reason error) error {
	if err := txx.Rollback(); err != nil {
		err = errors.Wrap(err, "rolling transaction back")

		return multierror.Append(reason, err)
	}

	return errors.Wrap(reason, "rolled transaction back")
}
