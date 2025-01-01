package upgrades

import (
	"context"
	"database/sql"
	stderrors "errors" //lint:ignore faillint importing for errors.Join
	"os"

	"github.com/github/turboscan/ts/appctx"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/mysql"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/pkg/errors"
)

type Env struct {
	db              *throttleDB
	migrationsDir   string
	migrationsTable string
}

// NewEnv generates an Env struct for use with other functions in this
// package.
func NewEnv(migrationsDir string, db *sql.DB, migrationsTable string) *Env {
	return &Env{
		migrationsDir:   migrationsDir,
		migrationsTable: migrationsTable,
		db:              &throttleDB{DB: db},
	}
}

// RunMigrations brings the database schema at db up to date with the migrations
// as specified by the contents of the directory migrationsPath and the format
// of golang-migrate
// (https://github.com/golang-migrate/migrate/blob/53ef02da13fda00ecea7420bfd1fed325b93990a/MIGRATIONS.md).
// Which migrations have already been run, if any, is recorded in
// migrationsTable. This special table is a) created if it does not already
// exist, and b) is NOT mentioned by the migrations (it sits 'outside' the
// migration framework).
func (e *Env) RunMigrations(ctx context.Context, transitions map[uint]func(ctx context.Context) error) (err error) {
	db, err := mysql.WithInstance(e.db.DB, &mysql.Config{
		MigrationsTable: e.migrationsTable,
	})
	if err != nil {
		return errors.Wrap(err, "creating migrator")
	}

	if err := CheckOrdering(os.DirFS(e.migrationsDir)); err != nil {
		return err
	}

	src, err := iofs.New(os.DirFS(e.migrationsDir), ".")
	if err != nil {
		return errors.Wrap(err, "creating dir")
	}

	defer func() {
		err = stderrors.Join(err, db.Close())
	}()

	m, err := migrate.NewWithInstance("file", src, "mysql", db)
	if err != nil {
		return err
	}

	m.Log = &migrateLogger{Logger: appctx.Logger(ctx)}

	return doMigrate(ctx, m, transitions)
}

func (e *Env) Verify(ctx context.Context) error {
	_, err := e.db.ExecContext(ctx, "SELECT 1")
	return err
}
