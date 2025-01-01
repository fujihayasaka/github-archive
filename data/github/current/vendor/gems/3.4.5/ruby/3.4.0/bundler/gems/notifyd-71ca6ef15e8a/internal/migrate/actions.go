// Package migrate implements the migration of database schema transitions.
package migrate

// Copied from: https://github.com/github/hookshot-go/blob/master/internal/schema/actions.go

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	migratorpkg "github.com/github/go-dbmigrator/mysql"
	"github.com/go-sql-driver/mysql"

	"github.com/github/notifyd/internal/pkg/errors"
	database "github.com/github/notifyd/internal/pkg/mysql"
)

const schemaMigrationsTable = "notifyd_schema_migrations"
const driver = "mysql"

// RunMigrationsAndTransitions runs migrations and transitions together, for use in Enterprise and development.
func RunMigrationsAndTransitions(ctx context.Context, telem *telemetry.Provider, env string, cfg database.Config, migrationsPath string) error {
	dbURL, err := database.DatabaseURL(cfg.PrimaryDatabaseURL)
	if err != nil {
		return errors.Wrap(err, "getting database config")
	}

	if env == "development" || env == "test" {
		if err := createDatabaseIfNeeded(ctx, telem, dbURL); err != nil {
			return errors.Wrap(err, "creating the database")
		}
	}

	db, err := sql.Open(driver, dbURL)
	defer func() {
		err = db.Close()
		if err != nil {
			telem.Logger.WithError(err).Error("closing database connection")
		}
	}()
	if err != nil {
		return errors.Wrap(err, "opening database connection")
	}
	if err := db.Ping(); err != nil {
		return errors.Wrap(err, "pinging database connection")
	}

	transitions, err := GetTransitions(db, driver)
	if err != nil {
		return errors.Wrap(err, "getting enterprise transitions")
	}

	migratorOpts := migratorpkg.MigratorOpts{}

	migrator, err := migratorpkg.NewWithDatabaseInstance(&migratorOpts, db, fmt.Sprintf("file://%s", migrationsPath), schemaMigrationsTable)
	if err != nil {
		return errors.Wrap(err, "creating migrator")
	}
	defer migrator.Close()

	// TODO(abeaumont): Consider adding an eventFileName for GHES once it's supported.
	if err := migrator.Migrate(ctx, transitions, ""); err != nil {
		return errors.Wrap(err, "running migrations")
	}

	return logFinalMigrationVersion(ctx, telem, db)
}

func createDatabaseIfNeeded(ctx context.Context, telem *telemetry.Provider, dbURL string) error {
	dbCfg, err := mysql.ParseDSN(dbURL)
	if err != nil {
		return err
	}
	cfgClone := *dbCfg
	dbName := cfgClone.DBName
	cfgClone.DBName = ""

	db, err := sql.Open("mysql", cfgClone.FormatDSN())
	if err != nil {
		return err
	}
	defer db.Close()

	telem.Logger.Info("creating database if it does not exist", kvp.String("db_name", dbName))
	_, err = db.ExecContext(ctx, fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s DEFAULT CHARSET=utf8 COLLATE utf8_general_ci", dbName))
	if err != nil {
		return err
	}

	return nil
}

func logFinalMigrationVersion(ctx context.Context, telem *telemetry.Provider, db *sql.DB) error {
	row := db.QueryRowContext(ctx, fmt.Sprintf("SELECT version FROM `%s`", schemaMigrationsTable))
	var finalVersion uint64
	err := row.Scan(&finalVersion)
	if err != nil {
		return errors.Wrap(err, "querying latest schema version")
	}
	telem.Logger.Info("final migration", kvp.Uint64("version", finalVersion))
	return nil
}
