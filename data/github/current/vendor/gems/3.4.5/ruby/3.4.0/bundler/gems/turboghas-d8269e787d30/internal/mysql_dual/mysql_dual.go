// Package mysql_dual contains database connections to the primary and replica.
package mysql_dual

import (
	"context"
	"database/sql"
	stderrors "errors"
	"io"
	"time"

	"github.com/github/turboghas/internal/fromctx"
	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"
)

type QueryDB interface {
	io.Closer
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

var _ QueryDB = &sql.DB{}

type ExecDB interface {
	QueryDB
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

type Connection struct {
	Primary ExecDB
	Replica QueryDB
}

func (c *Connection) Close() error {
	return stderrors.Join(
		c.Primary.Close(),
		c.Replica.Close(),
	)
}

var _ ExecDB = &sql.DB{}

type ThrottleDB struct {
	ExecDB
}

func NewThrottleDB(db ExecDB) ExecDB {
	return &ThrottleDB{ExecDB: db}
}

func (t *ThrottleDB) ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error) {
	if err := fromctx.Throttler.Wait(ctx); err != nil {
		return nil, errors.Wrap(err, "freno wait failed")
	}

	return t.ExecDB.ExecContext(ctx, query, args...)
}

type RetryDB struct {
	*sql.DB
}

func NewRetryDB(db *sql.DB) ExecDB {
	return &RetryDB{DB: db}
}

const MaxRetries = 3

func MySQLErrorNumber(err error, oneOf ...uint16) (uint16, bool) {
	var mysqlErr *mysql.MySQLError

	if errors.As(err, &mysqlErr) {
		for _, code := range oneOf {
			if mysqlErr.Number == code {
				return mysqlErr.Number, true
			}
		}
	}

	return 0, false
}

// AnyMySQLErrorNumber returns true if the error is a MySQLError with a number that matches any of the oneOf
// arguments.
func AnyMySQLErrorNumber(err error, oneOf ...uint16) bool {
	_, found := MySQLErrorNumber(err, oneOf...)
	return found
}

func IsTransientError(err error) bool {
	return errors.Is(err, mysql.ErrInvalidConn) || errors.Is(err, mysql.ErrPktSync) || // replica being drained
		AnyMySQLErrorNumber(
			err,
			1053, // server shutdown in progress
		)
}

func (rdb *RetryDB) QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error) {
	rows, err := rdb.DB.QueryContext(ctx, query, args...)
	if !IsTransientError(err) {
		return rows, err
	}
	for i := 1; i <= MaxRetries; i++ {
		time.Sleep(time.Duration(i*50) * time.Millisecond)
		rows, err = rdb.DB.QueryContext(ctx, query, args...)

		if IsTransientError(err) {
			continue
		}
		return rows, err
	}
	return rows, err
}
func (rdb *RetryDB) QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row {
	row := rdb.DB.QueryRowContext(ctx, query, args...)
	if !IsTransientError(row.Err()) {
		return row
	}
	for i := 1; i <= MaxRetries; i++ {
		time.Sleep(time.Duration(i*50) * time.Millisecond)
		row = rdb.DB.QueryRowContext(ctx, query, args...)
		if IsTransientError(row.Err()) {
			continue
		}
		return row
	}
	return row
}

func NewConnection(primaryConfig *mysql.Config, replicaConfig *mysql.Config, opts ...func(db *sql.DB)) (*Connection, error) {
	primaryDSN := primaryConfig.FormatDSN()

	primary, err := sql.Open("mysql", primaryDSN)
	if err != nil {
		return nil, err
	}

	if err := primary.Ping(); err != nil {
		return nil, err
	}

	for _, opt := range opts {
		opt(primary)
	}

	replica := primary
	if replicaConfig != nil {
		if replicaDSN := replicaConfig.FormatDSN(); replicaDSN != primaryDSN {
			replica, err = sql.Open("mysql", replicaDSN)
			if err != nil {
				return nil, err
			}

			if err := replica.Ping(); err != nil {
				return nil, err
			}

			for _, opt := range opts {
				opt(replica)
			}
		}
	}

	return &Connection{
		Primary: NewThrottleDB(NewRetryDB(primary)),
		Replica: NewRetryDB(replica),
	}, nil
}
