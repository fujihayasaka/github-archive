package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
)

type Executor interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
	PrepareContext(context.Context, string) (*sql.Stmt, error)
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	QueryRowContext(context.Context, string, ...any) *sql.Row
	BeginTx(context.Context, *sql.TxOptions) (*sql.Tx, error)
}

type DB struct {
	PrimaryExecutor Executor
	ReplicaExecutor Executor

	statter stats.Client
	logger  log.Logger
	primary *sql.DB
	replica *sql.DB
}

// NewComposite returns a new db.DB that shares an identical connection across it's primary and replica
// This is useful for an abstraction like vitess, where reads and writes are auto-magically sent to the right locations
// or in test, where there's a single connection to the DB, masquerading as a primary or replica connection
func NewComposite(db *sql.DB, logger log.Logger, statter stats.Client) *DB {
	return &DB{
		PrimaryExecutor: db,
		ReplicaExecutor: db,
		primary:         db,
		replica:         db,
		statter:         statter,
		logger:          logger,
	}
}

// Close closes the databases
func (db *DB) Close() error {

	primaryErr := db.primary.Close()
	replicaErr := db.replica.Close()

	return errors.Join(primaryErr, replicaErr)
}

func (db *DB) GetRawSQLDBPrimary() *sql.DB {
	return db.primary
}

func (db *DB) GetRawSQLDBReplica() *sql.DB {
	return db.replica
}

func NewSqlxDatabase(sqlDB *sql.DB) (*sqlx.DB, error) {
	otelDriverName, err := GetOtelMysqlDriverName()
	if err != nil {
		return nil, err
	}

	return sqlx.NewDb(sqlDB, otelDriverName), nil
}

// RunWithTx starts a transaction with the provided context and runs the input fn within the transaction,
// and ensures that the transaction is _always_ rolled back or committed.  Please see `sql.DB.BeginTx` for
// complete behaviors.  If options are nil, then the default transaction options are used.
func RunWithTx(ctx context.Context, exec Executor, options *sql.TxOptions, fn func(tx *sql.Tx) error) (err error) {
	tx, err := exec.BeginTx(ctx, options)
	if err != nil {
		return err
	}

	defer func() {
		// rollback only if we encountered an error; i.e. do not rollback if commit was successful
		if err != nil {
			if rollbackErr := tx.Rollback(); rollbackErr != nil {
				err = fmt.Errorf("failed to rollback transaction after err '%s': %w", err.Error(), rollbackErr)
			}
		}
	}()

	err = fn(tx)
	if err != nil {
		return err
	}

	err = tx.Commit()
	if err != nil {
		return err
	}

	return nil
}

// WaitForDatabase tries/retries to connect to the DB until it is successful, or the context is done.
// any connection passed to WaitForDatabase will be closed, so it is not usable after.
func WaitForDatabase(ctx context.Context, connect func() (*sql.DB, error)) error {
	var db *sql.DB
	var err error
	for ctx.Err() == nil {
		db, err = connect()
		if err == nil {
			if err := db.PingContext(ctx); err == nil {
				db.Close()
				return nil
			}
			var up bool
			if err := db.QueryRowContext(ctx, "SELECT EXISTS(SELECT VERSION());").Scan(&up); err == nil && up {
				db.Close()
				return nil
			}
		}
		if db != nil {
			db.Close()
		}
		time.Sleep(250 * time.Millisecond)
	}
	return ctx.Err()
}
