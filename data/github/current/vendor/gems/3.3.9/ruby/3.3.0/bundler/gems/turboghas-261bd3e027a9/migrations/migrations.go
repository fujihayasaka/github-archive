// Package migrations provides migrations and transitions.
package migrations

import (
	"context"
	"database/sql"
	"embed"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database"
	"github.com/golang-migrate/migrate/v4/database/mysql"
	"github.com/golang-migrate/migrate/v4/source"
	"github.com/golang-migrate/migrate/v4/source/iofs"
)

const Table = "tg_migrations"

//go:embed *.up.sql
var fs embed.FS

type migrateLogger struct {
	log.Logger
}

var _ migrate.Logger = &migrateLogger{}

func (m *migrateLogger) Printf(format string, v ...interface{}) {
	m.Logger.Info(fmt.Sprintf(format, v...))
}

func (m *migrateLogger) Verbose() bool {
	return true
}

func Driver(db *sql.DB) (database.Driver, error) {
	return mysql.WithInstance(db, &mysql.Config{
		MigrationsTable: Table,
	})
}

func Source() (source.Driver, error) {
	return iofs.New(fs, ".")
}

func New(ctx context.Context, db database.Driver, src source.Driver) (m *migrate.Migrate, err error) {
	m, err = migrate.NewWithInstance("file", src, "mysql", db)
	if err != nil {
		return nil, err
	}
	m.Log = &migrateLogger{Logger: fromctx.Logger.Value(ctx)}

	return m, nil
}
