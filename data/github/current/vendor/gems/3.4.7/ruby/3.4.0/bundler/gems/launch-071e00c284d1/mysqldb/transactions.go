package mysqldb

import (
	"context"
	"database/sql"
	"time"

	"github.com/hashicorp/go-multierror"
	"github.com/pkg/errors"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
)

// Runs the supplied func with a new transaction and records timing metrics. If that func returns an error
// will attempt to rollback the transaction. If not, the transaction will be
// committed.
func WithTransaction(
	ctx context.Context,
	db *sql.DB,
	s statter.Statter,
	operationName string,
	runTransaction func(*sql.Tx) error,
) error {
	start := time.Now()
	tags := statter.Tags{
		metrickeys.OperationName: operationName,
	}

	defer func() {
		if p := recover(); p != nil {
			// Record timing, but still panic
			tags["error"] = "true"
			s.Timing(ctx, "act_transaction.time", tags, time.Since(start))
			panic(p)
		}
	}()

	err := withTransactionInteral(ctx, db, runTransaction)

	// Add error if any
	s.Timing(ctx, "act_transaction.time", observability.ErrorTag(tags, err), time.Since(start))

	return err
}

func withTransactionInteral(ctx context.Context, db *sql.DB, runTransaction func(*sql.Tx) error) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return errors.Wrap(err, "could not start transaction")
	}

	defer func() {
		if p := recover(); p != nil {
			// err doesn't matter as we're about to panic
			_ = tx.Rollback()
			panic(p)
		}
	}()

	if err = runTransaction(tx); err != nil {
		// if we get an additional error trying to clean up the transaction log it,
		// but still return the err that caused us to abort the transaction
		if rberr := tx.Rollback(); rberr != nil && rberr != sql.ErrTxDone {
			return errors.Wrap(multierror.Append(err, rberr), "error rolling back transaction")
		}
		return err
	}

	if err = tx.Commit(); err != nil {
		return errors.Wrap(err, "could not commit")
	}

	return nil
}
