package mysql

import (
	"context"
	"time"

	"github.com/XSAM/otelsql"
	"github.com/go-sql-driver/mysql"
	"github.com/hashicorp/go-multierror"
	"github.com/jmoiron/sqlx"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"

	"github.com/github/notifyd/internal/pkg/errors"
)

// DB contains connections for both reading and writing
type DB struct {
	Write *sqlx.DB
	Read  *sqlx.DB
}

// Config represents the configuration for the database.
type Config struct {
	PrimaryDatabaseURL string `config:",env=PRIMARY_DB_URL,required"`
	ReplicaDatabaseURL string `config:",env=REPLICA_DB_URL,required"`
	TestDatabaseURL    string `config:",env=TEST_DB_URL"`
}

// New builds a new DB with read and write database connections.
func New(ctx context.Context, cfg Config, env string) (DB, func() error, error) {
	driverName := "mysql"

	if env == "test" {
		url, err := DatabaseURL(cfg.TestDatabaseURL)
		if err != nil {
			return DB{}, nil, errors.Wrap(err, "parsing testing database URL")
		}

		db, err := dbConnection(ctx, driverName, url)
		if err != nil {
			return DB{}, nil, errors.Wrap(err, "connecting to testing database")
		}
		return DB{Write: db, Read: db}, db.Close, nil
	}

	instrumentedDriverName, err := instrumentDBDriver(driverName)
	if err != nil {
		return DB{}, nil, errors.Wrap(err, "instrumenting database driver")
	}

	url, err := DatabaseURL(cfg.PrimaryDatabaseURL)
	if err != nil {
		return DB{}, nil, errors.Wrap(err, "parsing primary database URL")
	}
	write, err := dbConnection(ctx, instrumentedDriverName, url)
	if err != nil {
		return DB{}, nil, errors.Wrap(err, "connecting to primary database")
	}

	url, err = DatabaseURL(cfg.ReplicaDatabaseURL)
	if err != nil {
		return DB{}, nil, errors.Wrap(err, "parsing replica database URL")
	}
	read, err := dbConnection(ctx, instrumentedDriverName, url)
	if err != nil {
		return DB{}, nil, errors.Wrap(err, "connecting to replica database")
	}

	cleanup := func() error {
		var errs error
		if err := write.Close(); err != nil {
			errs = multierror.Append(errs, err)
		}
		if err := read.Close(); err != nil {
			errs = multierror.Append(errs, err)
		}
		return errs
	}

	return DB{Write: write, Read: read}, cleanup, nil
}

// DatabaseURL returns a DSN with additional parameters configured.
func DatabaseURL(dsn string) (string, error) {
	cfg, err := mysql.ParseDSN(dsn)
	if err != nil {
		return "", err
	}

	cfg.ParseTime = true
	cfg.InterpolateParams = true
	cfg.AllowNativePasswords = true
	cfg.MultiStatements = true
	cfg.Params = map[string]string{
		"charset":  "utf8mb4",
		"sql_mode": "'STRICT_ALL_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,NO_AUTO_VALUE_ON_ZERO,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'",
	}

	dsn = cfg.FormatDSN()
	return dsn, nil
}

func dbConnection(ctx context.Context, driverName, url string) (*sqlx.DB, error) {
	db, err := sqlx.ConnectContext(ctx, driverName, url)
	if err != nil {
		return nil, errors.Wrap(err, "error connecting to the database").With(errors.MarkTransient())
	}

	// As per https://github.com/github/go/blob/main/docs/database_access.md#setting-max-connection-lifetime
	// We set 4min 30sec because:
	// - GLB will close connections after 5 minutes
	// - Our longest requests are the ones from the Notify consumer that can take up to 30sec on the +p99 cases
	//
	// By setting this instead of 5min we reduce the possibility that a connection is closed in flight
	// by the GLB since they will be removed from the pool before GLB closes them.
	db.SetConnMaxLifetime(4*time.Minute + 30*time.Second)

	return db, nil
}

func instrumentDBDriver(driverName string) (string, error) {
	instrumentedDriverName, err := otelsql.Register(driverName,
		otelsql.WithAttributes(semconv.DBSystemMySQL),
		otelsql.WithSpanOptions(otelsql.SpanOptions{DisableErrSkip: true}),
	)
	if err != nil {
		return "", errors.Wrap(err, "error registering OTel wrapped database driver").With(errors.MarkTransient())
	}

	return instrumentedDriverName, nil
}
