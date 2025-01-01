package utils

import (
	"database/sql"
	"time"

	"github.com/pkg/errors"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/dsn"
)

// DatabaseOptions represents the options we can use for connecting to a
// database.
type DatabaseOptions struct {
	EmulatePreparedStatements bool
	UseUTCForMySQL            bool
	ForceCharsetForMySQL      bool
	MySQLMaxOpenConns         int
	MySQLMaxIdleConns         int
	MySQLMaxIdleTime          time.Duration
	MySQLMaxLifetime          time.Duration
}

// GetDttabaseConnection returns a connection to a database instance
func GetDatabaseConnection(databaseURL string, stats statter.Statter, opts *DatabaseOptions) (*sql.DB, error) {
	dbDSN := databaseURL

	var err error
	if opts.EmulatePreparedStatements {
		dbDSN, err = dsn.WithInterpolateParams(dbDSN, "true")
		if err != nil {
			return nil, errors.Wrap(err, "unable to set interpolateParams attribute")
		}
	}

	if opts.UseUTCForMySQL {
		dbDSN, err = dsn.WithTimezone(dbDSN, "UTC")
		if err != nil {
			return nil, errors.Wrap(err, "unable to set timezone attribute")
		}
	}

	if opts.ForceCharsetForMySQL {
		dbDSN, err = dsn.WithCharset(dbDSN, "utf8mb4")
		if err != nil {
			return nil, errors.Wrap(err, "unable to set charset attribute")
		}
	}

	dbConn, err := mysqldb.NewDB(stats, dbDSN)
	if err != nil {
		return nil, errors.Wrap(err, "error connecting to mysql")
	}

	if opts.MySQLMaxIdleConns <= 0 {
		return nil, errors.New("MySQLMaxIdleConns must be greater than 0")
	}

	dbConn.SetMaxOpenConns(opts.MySQLMaxOpenConns)
	dbConn.SetMaxIdleConns(opts.MySQLMaxIdleConns)

	// Set max idle time before max lifetime to avoid https://github.com/golang/go/pull/58490
	dbConn.SetConnMaxIdleTime(opts.MySQLMaxIdleTime)
	dbConn.SetConnMaxLifetime(opts.MySQLMaxLifetime)

	return dbConn, nil
}
