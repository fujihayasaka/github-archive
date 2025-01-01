// Package resilientdb provides a gorm-compatible connection which will retry SELECT statements on mysql connection errors.
package resilientdb

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"strconv"
	"strings"
	"unicode"

	"github.com/jinzhu/gorm"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/pkg/errors"

	"github.com/github/go-stats"

	"github.com/github/github-telemetry-go/log"

	"github.com/go-sql-driver/mysql"
)

const MaxRetries = 3

// Database combines the interfaces of gorm.SQLCommon, gorm.closer and gorm.sqlDb
type Database interface {
	gorm.SQLCommon
	Begin() (*sql.Tx, error)
	BeginTx(ctx context.Context, opts *sql.TxOptions) (*sql.Tx, error)
	Close() error
}

// DB is a resilient database connection.  It attempts to retry reads if they
// are unsuccessful due to a transient connection failure.
type DB struct {
	Database
	logger  log.Logger
	statter stats.Client
}

func (db *DB) DB() *sql.DB {
	if v, ok := db.Database.(*sql.DB); ok {
		return v
	}
	return nil
}

func (db *DB) Close() error {
	return db.Database.Close()
}

func (db *DB) Begin() (*sql.Tx, error) {
	tx, err := db.Database.Begin()
	if errors.Is(err, mysql.ErrInvalidConn) {
		db.error("BEGIN", "begin", 1)
	}
	return tx, err
}
func (db *DB) BeginTx(ctx context.Context, opts *sql.TxOptions) (*sql.Tx, error) {
	tx, err := db.Database.BeginTx(ctx, opts)
	if errors.Is(err, mysql.ErrInvalidConn) {
		db.error("BEGIN", "begintx", 1)
	}
	return tx, err
}

func (db *DB) Exec(query string, args ...interface{}) (sql.Result, error) {
	result, err := db.Database.Exec(query, args...)
	if errors.Is(err, mysql.ErrInvalidConn) {
		db.error(ParseSQLVerb(query), "exec", 1)
	}
	return result, err
}

func (db *DB) Prepare(query string) (*sql.Stmt, error) {
	stmt, err := db.Database.Prepare(query)
	if errors.Is(err, mysql.ErrInvalidConn) {
		db.error(ParseSQLVerb(query), "prepare", 1)
	}
	return stmt, err
}

// isConnectionLost returns true if an error indicates the MySQL connection was lost.
func isConnectionLost(err error) bool {
	if err == nil {
		return false
	}

	var mysqlErr *mysql.MySQLError
	return errors.Is(err, driver.ErrBadConn) ||
		// Driver error, possibly a bug in go-sql-driver/mysql.
		errors.Is(err, mysql.ErrInvalidConn) ||
		// Server shutdown in progress.
		(errors.As(err, &mysqlErr) && mysqlErr.Number == 1053)
}

func (db *DB) Query(query string, args ...interface{}) (*sql.Rows, error) {
	var rows *sql.Rows
	var err error
	for i := 0; i < MaxRetries; i++ {
		rows, err = db.Database.Query(query, args...)
		if isConnectionLost(err) {
			verb := ParseSQLVerb(query)
			db.error(verb, "query", i+1)
			// Try again with a different connection. database/sql
			// should do this automatically for us.
			if verb == "SELECT" {
				continue
			}
		}
		return rows, err
	}
	return rows, err
}

func (db *DB) QueryRow(query string, args ...interface{}) *sql.Row {
	var row *sql.Row
	for i := 0; i < MaxRetries; i++ {
		row = db.Database.QueryRow(query, args...)
		if isConnectionLost(row.Err()) {
			verb := ParseSQLVerb(query)
			db.error(verb, "queryrow", i+1)
			// Try again with a different connection. database/sql
			// should do this automatically for us.
			if verb == "SELECT" {
				continue
			}
		}
		return row
	}
	return row
}

func (db *DB) error(verb, name string, attempt int) {
	db.logger.Error("mysql.ErrInvalidConn", kvp.String("gh.turboscan.verb", verb), kvp.String("gh.turboscan.callbackname", name), kvp.Int("gh.turboscan.attempt", attempt))
	db.statter.Counter("mysql.errinvalidconn", stats.Tags{"verb": verb, "callbackname": name, "attempt": strconv.Itoa(attempt)}, 1)
}

// ParseSQLVerb extracts the verb (SELECT, UPDATE, DELETE etc) from an sql statement.
func ParseSQLVerb(stmt string) string {
	trimmed := strings.TrimSpace(stmt)
	if end := strings.IndexFunc(trimmed, unicode.IsSpace); end >= 0 {
		return strings.ToUpper(trimmed[:end])
	}
	return "UNKNOWN"
}

// NewDB produces a new database from the given database handle.
func NewDB(db Database, logger log.Logger, statter stats.Client) *DB {
	return &DB{Database: db, logger: logger, statter: statter}
}
