// Package mysqldb provides methods for connecting & manipulating databases.
package mysqldb

import (
	"database/sql"
	"time"

	"github.com/go-sql-driver/mysql"
	"github.com/uptrace/opentelemetry-go-extra/otelsql"
	semconv "go.opentelemetry.io/otel/semconv/v1.22.0"

	"github.com/github/launch/observability/statter"
)

const (
	// ConnRetryAttempts defines the maximum attempts to create a connection
	ConnRetryAttempts = 1
	// ConnRetryDelay defines te delay between connection attempts
	ConnRetryDelay = 1 * time.Second
)

// NewDB returns a pointer to a sql.DB which provides a
// connection to the credential database.
//
// dataSourceName -- connection string using the DSN standard
//
// Returns an error if one is encountered, and *sql.DB.
func NewDB(statter statter.Statter, dataSourceName string) (*sql.DB, error) {

	cfg, err := mysql.ParseDSN(dataSourceName)
	if err != nil {
		return nil, err
	}

	connector, err := NewRetryingConnector(statter, cfg, ConnRetryAttempts, ConnRetryDelay)
	if err != nil {
		return nil, err
	}

	db := otelsql.OpenDB(connector, otelsql.WithAttributes(
		semconv.DBSystemMySQL,
	))

	return db, db.Ping()
}
