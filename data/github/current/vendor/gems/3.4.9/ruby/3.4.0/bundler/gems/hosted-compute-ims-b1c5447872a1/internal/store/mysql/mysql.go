// Provides methods for connecting to a database

package mysql

import (
	"database/sql"
	"fmt"

	"github.com/jmoiron/sqlx"

	entsql "entgo.io/ent/dialect/sql"

	"github.com/github/hosted-compute-ims/gen/ent"
	_ "github.com/go-sql-driver/mysql"
)

type DB struct {
	Write *sqlx.DB
	Read  *sqlx.DB
}

// Returns an active read-write connection to the DB
func NewWriteEntClient(cfg *Config) (*ent.Client, error) {
	dbURL, err := cfg.DatabaseWriteURL()
	if err != nil {
		return nil, fmt.Errorf("failed to construct db read-write url %s, error occurred: %w", dbURL, err)
	}

	c, err := NewConnection(cfg, dbURL)
	if err != nil {
		return nil, err
	}

	drv := entsql.OpenDB("mysql", c)

	return ent.NewClient(ent.Driver(drv)), nil
}

// Returns an active read-only connection to the DB
func NewReadEntClient(cfg *Config) (*ent.Client, error) {
	dbURL, err := cfg.DatabaseReadURL()
	if err != nil {
		return nil, fmt.Errorf("failed to construct db read-only url %s, error occurred: %w", dbURL, err)
	}

	c, err := NewConnection(cfg, dbURL)
	if err != nil {
		return nil, err
	}

	drv := entsql.OpenDB("mysql", c)

	return ent.NewClient(ent.Driver(drv)), nil
}

// Returns an unopened connection to the DB
// Connection parameters must be set before the connection is opened.
func NewConnection(cfg *Config, connectionUrl string) (*sql.DB, error) {
	dbConn, err := sql.Open("mysql", connectionUrl)
	if err != nil {
		return nil, fmt.Errorf("failed to open db connection with url %s, error occurred: %w", connectionUrl, err)
	}

	err = dbConn.Ping()
	if err != nil {
		return nil, fmt.Errorf("failed to validate db connection. Ping request failed: %w", err)
	}

	dbConn.SetMaxOpenConns(cfg.MaxOpenConnections)
	dbConn.SetMaxIdleConns(cfg.ConnectionsMaxIdleTime)
	dbConn.SetConnMaxLifetime(cfg.ConnectionMaxLifetime)

	return dbConn, nil
}
