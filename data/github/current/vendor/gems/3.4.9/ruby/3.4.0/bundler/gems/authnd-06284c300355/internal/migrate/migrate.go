// inspired by turboscan https://github.com/github/turboscan/blob/main/ts/mysql/upgrades/migrator.go
package migrate

import (
	"context"
	"net/url"

	"github.com/github/authnd/internal/common/db"
	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-dbmigrator"
	"github.com/github/go-dbmigrator/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// MigrationsTable is a table managed by the underlying golang-migrate library.
// Only used on GHES, it stores the current schema version and whether the most
// recent migration was successful or not.
const MigrationsTable = "authnd_schema_migrations"

func RunMigrations(
	ctx context.Context,
	cfg *Config,
	migrationsPath string,
) error {
	logger := diagnostics.Logger(ctx)

	authndConfig, err := cfg.DatabaseConfigFor(schemas.AuthndRW)
	if err != nil {
		return err
	}

	authnd, err := db.Open(logger, authndConfig)
	if err != nil {
		return err
	}

	migrationsURL := &url.URL{
		Scheme: "file",
		Path:   migrationsPath,
	}

	migratorOpts := mysql.MigratorOpts{}

	migrator, err := mysql.NewWithDatabaseInstance(&migratorOpts, authnd.DB, migrationsURL.String(), MigrationsTable)
	if err != nil {
		return errors.Errorf("creating migrator: %v", err)
	}

	defer migrator.Close()

	transitions := dbmigrator.NewTransitioner()

	err = migrator.Migrate(ctx, transitions, "")
	if err != nil {
		return err
	}

	return logFinalMigrationVersion(ctx, authnd)
}

func logFinalMigrationVersion(ctx context.Context, db *sqlx.DB) error {
	logger := diagnostics.Logger(ctx)

	var finalMigrationVersion int64
	err := db.QueryRowxContext(ctx, "SELECT version FROM "+MigrationsTable+"").Scan(&finalMigrationVersion)
	if err != nil {
		return errors.Wrapf(err, "error getting finalMigrationVersion value")
	}
	logger.Info("Final migration version", kvp.Int64("gh.authnd.db.migration.version", finalMigrationVersion))
	return nil
}
