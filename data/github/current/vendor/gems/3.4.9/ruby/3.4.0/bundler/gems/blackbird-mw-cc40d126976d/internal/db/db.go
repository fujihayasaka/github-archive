package db

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"

	"github.com/github/blackbird-mw/internal/db/mysqlerrors"
)

// Interface for a db connection that retries a small number of invalid connection errors. Be
// careful to only issue idempotent db queries/commands.
type RetryableDB interface {
	SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error
	GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error
	BeginTxx(ctx context.Context, opts *sql.TxOptions) (*sqlx.Tx, error)
	Close() error

	sqlx.ExecerContext
	sqlx.QueryerContext
}

// Wraps a sqlx.DB with retries. The following errors will be immediately retried up to 3 times:
// - invalid connection
// - 1053: Server shutdown in progress
type RetryableMySQL struct {
	db *sqlx.DB
}

func NewRetryableMySQL(db *sqlx.DB) *RetryableMySQL {
	return &RetryableMySQL{db}
}

func (s *RetryableMySQL) DB() *sqlx.DB {
	return s.db
}

func (s *RetryableMySQL) Close() error {
	return s.db.Close()
}

func (s *RetryableMySQL) BeginTxx(ctx context.Context, opts *sql.TxOptions) (*sqlx.Tx, error) {
	var tx *sqlx.Tx
	err := withRetries(ctx, func() error {
		var err error
		tx, err = s.db.BeginTxx(ctx, opts)
		return err
	})
	return tx, err
}

func (s *RetryableMySQL) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	var res sql.Result
	err := withRetries(ctx, func() error {
		var err error
		res, err = s.db.ExecContext(ctx, query, args...)
		return err
	})
	return res, err
}

func (s *RetryableMySQL) QueryContext(ctx context.Context, query string, args ...interface{}) (*sql.Rows, error) {
	var rows *sql.Rows
	err := withRetries(ctx, func() error {
		var err error
		rows, err = s.db.QueryContext(ctx, query, args...)
		return err
	})
	return rows, err
}

func (s *RetryableMySQL) QueryRowx(query string, args ...interface{}) *sqlx.Row {
	return s.db.QueryRowx(query, args...)
}

func (s *RetryableMySQL) QueryRowxContext(ctx context.Context, query string, args ...interface{}) *sqlx.Row {
	return s.db.QueryRowxContext(ctx, query, args...)
}

func (s *RetryableMySQL) Queryx(query string, args ...interface{}) (*sqlx.Rows, error) {
	return s.db.Queryx(query, args...)
}

func (s *RetryableMySQL) QueryxContext(ctx context.Context, query string, args ...interface{}) (*sqlx.Rows, error) {
	var rows *sqlx.Rows
	err := withRetries(ctx, func() error {
		var err error
		rows, err = s.db.QueryxContext(ctx, query, args...)
		return err
	})
	return rows, err
}

func (s *RetryableMySQL) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return withRetries(ctx, func() error {
		return s.db.GetContext(ctx, dest, query, args...)
	})
}

func (s *RetryableMySQL) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return withRetries(ctx, func() error {
		return s.db.SelectContext(ctx, dest, query, args...)
	})
}

func withRetries(ctx context.Context, f func() error) error {
	return backoff.Retry(func() error {
		err := f()
		if !isRetryable(err) {
			return backoff.Permanent(err)
		}
		return err
	}, backoff.WithContext(backoff.WithMaxRetries(backoff.NewConstantBackOff(1*time.Millisecond), 3), ctx))
}

func isRetryable(err error) bool {
	return errors.Is(err, mysql.ErrInvalidConn) || errors.Is(err, mysqlerrors.ServerShutdownError())
}

var _ RetryableDB = &RetryableMySQL{}
