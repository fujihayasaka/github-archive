package mysql

import (
	"context"
	"database/sql"
	"log"
	"os"
	"strings"

	_ "github.com/go-sql-driver/mysql" // this is consumed by others externally, so import it here
	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/mysql"
	_ "github.com/golang-migrate/migrate/v4/source/file" // consumed by others externally, so import here
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/dbmigrator"
	"github.com/github/launch/utils/dsn"
)

// Migrator performs migrations for a MySQL database.
type Migrator struct {
	migrate *migrate.Migrate
}

// simpleLog just wraps the default go logger as we don't need more at the moment.
type simpleLog struct{}

func (l *simpleLog) Printf(format string, v ...any) { log.Printf(format, v...) }
func (l *simpleLog) Verbose() bool                  { return true }

var _ dbmigrator.Migrator = (*Migrator)(nil)

// New instantiates an instance of the MySQL migrator with certain files,
func New(sourceURL, databaseURL, migrationsTable string) (*Migrator, error) {
	// We have to have the MySQL format in this.
	if !strings.Contains(databaseURL, "mysql://") {
		return nil, errors.New("database url scheme must be mysql://")
	}

	if err := validateMigrationsTable(migrationsTable); err != nil {
		return nil, errors.Wrap(err, "invalid migrations table name")
	}

	dbURL, err := dsn.WithMigrationsTable(databaseURL, migrationsTable)
	if err != nil {
		return nil, errors.Wrap(err, "error setting migrations table attribute")
	}

	m, err := migrate.New(sourceURL, dbURL)
	if err != nil {
		return nil, errors.Wrap(err, "error instantiating migrate")
	}

	return &Migrator{
		migrate: m,
	}, nil
}

// NewWithDatabaseInstance creates a MySQL migrator from an existing database
// instance. The underlying database instance must have `multiStatements` set to true.
// See
// https://pkg.go.dev/github.com/golang-migrate/migrate/database/mysql?tab=doc#WithInstance
// for more information.
func NewWithDatabaseInstance(db *sql.DB, sourceURL string, migrationsTable string) (*Migrator, error) {
	if err := validateMigrationsTable(migrationsTable); err != nil {
		return nil, errors.Wrap(err, "invalid migrations table name")
	}

	instance, err := mysql.WithInstance(db, &mysql.Config{
		MigrationsTable: migrationsTable,
	})
	if err != nil {
		return nil, errors.Wrap(err, "error creating instance")
	}

	m, err := migrate.NewWithDatabaseInstance(sourceURL, "mysql", instance)
	if err != nil {
		return nil, errors.Wrap(err, "error instantiating migrate from instance")
	}

	m.Log = &simpleLog{}

	return &Migrator{
		migrate: m,
	}, nil
}

func validateMigrationsTable(migrationsTable string) error {
	// This is a defensive means for folks who may be using this in GHES to
	// prevent them from overriding the Rails migration table with the same name.
	// Alternatively, we may be able to extend this to explicitly force users to
	// allow the default name if they truly want to use this.
	if migrationsTable == "schema_migrations" {
		return errors.New("migrations table name cannot be named `schema_migrations`")
	}

	if migrationsTable == "" {
		return errors.New("migrations table name cannot be blank")
	}
	return nil
}

// Migrate executes each migration one by one, checking to see if there's a
// transition at each step.
func (m *Migrator) Migrate(ctx context.Context, transitions *dbmigrator.Transitioner) error {
	// Attempt any transitions that may exist on the current schema version
	if err := m.attemptTransition(ctx, transitions); err != nil {
		return errors.Wrap(err, "error attempting transition for initial version")
	}

	// Loop through every single migration one step at a time, also check for
	// transitions that come after that migration. The underlying algorithm is the
	// following:
	//
	// (1) Check the migration version and see if there are any transitions defined
	// for this version. Returns any errors for this.
	// (2) See if there are any transitions defined for this version. Execute if
	// they do exist. Returns any errors from this.
	// (3) Apply tthe next migration. If error is returned and equals
	// `ErrNoChange`, break the loop, otherwise return the error.
	// (4) GOTO (1)
	for {
		// NOTE: I'm wondering if we could optimize the transition functions in a way
		// that allows us to run transitions in a goroutine, but then force them to
		// block at their "last safe version". Meaning, if we have migrations "M1",
		// "M2", "M3" and "M4" and transitions "T1" and "T3", "T1" must finish
		// executing before we execute "M3" and "T3", and "T3" must execute
		// before "M4". In this case, when "M2" is applied, if we check it's version
		// and it says "block T1 at the end of this version", we can speed up
		// migrations this way by doing some of the transitions async while still
		// applying migrations when possible. But unsure if this is optimizing too
		// much.
		err := m.migrate.Steps(1)
		if noMoreMigrations(err) {
			break
		}
		if err != nil {
			return errors.Wrap(err, "error applying migration step")
		}

		if err = m.attemptTransition(ctx, transitions); err != nil {
			return err
		}
	}

	finalVersion, _, err := m.migrate.Version()
	if err != nil {
		return err
	}
	log.Printf("Final migration version: %d", finalVersion)

	return nil
}

func noMoreMigrations(err error) bool {
	return os.IsNotExist(err)
}

func (m *Migrator) attemptTransition(ctx context.Context, transitions *dbmigrator.Transitioner) error {
	version, _, err := m.migrate.Version()
	if err != nil {
		// No migrations have been applied yet, so we can't run any transitions.
		if err == migrate.ErrNilVersion {
			return nil
		}

		return errors.Wrap(err, "error checking migration version for transition")
	}

	if transition, ok := transitions.Get(version); ok {
		log.Printf("transition function found for schema version %d, executing transition", version)
		if transition != nil {
			err := transition.Run(ctx)
			if err != nil {
				return errors.Wrapf(err, "error executing transition for schema version: %d", version)
			}
		}
		log.Printf("finished executing transition function for schema version %v", version)
	}

	return nil
}

// Force forces the existence of a specific migration version.
func (m *Migrator) Force(version int) error {
	if err := m.migrate.Force(version); err != nil {
		if noMoreMigrations(err) {
			return nil
		}

		return err
	}

	return nil
}

// Close closes the underlying source and database.
func (m *Migrator) Close() error {
	sourceErr, databaseErr := m.migrate.Close()
	if sourceErr != nil {
		return errors.Wrap(sourceErr, "error closing source")
	}

	if databaseErr != nil {
		return errors.Wrap(databaseErr, "error closing database")
	}

	return nil
}
