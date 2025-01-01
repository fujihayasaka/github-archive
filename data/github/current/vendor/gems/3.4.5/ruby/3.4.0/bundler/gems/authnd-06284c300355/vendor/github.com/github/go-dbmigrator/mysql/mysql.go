// Package mysql provides a MySQL implementation of the Migrator interface.
package mysql

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-dbmigrator"
	"github.com/github/go-dbmigrator/dsn"
	_ "github.com/go-sql-driver/mysql" // this is consumed by others externally, so import it here
	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/mysql"
	_ "github.com/golang-migrate/migrate/v4/source/file" // consumed by others externally, so import here
)

const serviceName = "go-dbmigrator-mysql"

// Assert that these implementations implement the interfaces.
var (
	_ dbmigrator.Migrator = (*Migrator)(nil)
)

// Migrator performs migrations for a MySQL database.
type Migrator struct {
	migrate *migrate.Migrate
	logger  log.Logger
}

// MigratorOpts is used to provide configuration when constructing a Migrator.
type MigratorOpts struct {
	Logger log.Logger
}

// Event is used to build events for each migration.
type Event struct {
	Version      uint      `json:"version"`
	Time         time.Time `json:"start_time"`
	EventVersion string    `json:"event_version"`
	EventType    string    `json:"event_type"`
}

type migrateLogger struct {
	logger log.Logger
}

func (l *migrateLogger) Printf(format string, v ...interface{}) {
	l.logger.Info(fmt.Sprintf(format, v...))
}

func (l *migrateLogger) Verbose() bool {
	return true
}

// If the logger is provided by the caller, use it. If not, create new logger of type github-telemetry-go.
func newWithLogger(migrate *migrate.Migrate, logger log.Logger) *Migrator {
	if logger == nil {
		logger = log.Named(serviceName)
	} else {
		logger = logger.Named(serviceName)
	}

	migrate.Log = &migrateLogger{logger: logger}

	return &Migrator{
		migrate: migrate,
		logger:  logger,
	}
}

// New instantiates an instance of the MySQL migrator with certain files.
func New(opts *MigratorOpts, sourceURL, databaseURL, migrationsTable string) (*Migrator, error) {
	// We have to have the MySQL format in this.
	if !strings.Contains(databaseURL, "mysql://") {
		return nil, fmt.Errorf("database url scheme must be mysql://")
	}

	if err := validateMigrationsTable(migrationsTable); err != nil {
		return nil, fmt.Errorf("invalid migrations table name: %w", err)
	}

	dbURL, err := dsn.WithMigrationsTable(databaseURL, migrationsTable)
	if err != nil {
		return nil, fmt.Errorf("error setting migrations table attribute: %w", err)
	}

	m, err := migrate.New(sourceURL, dbURL)
	if err != nil {
		return nil, fmt.Errorf("error instantiating migrate: %w", err)
	}

	return newWithLogger(m, opts.Logger), nil
}

// NewWithDatabaseInstance creates a MySQL migrator from an existing database
// instance. The underlying database instance must have `multiStatements` set to true.
// See
// https://pkg.go.dev/github.com/golang-migrate/migrate/database/mysql?tab=doc#WithInstance
// for more information.
func NewWithDatabaseInstance(opts *MigratorOpts, db *sql.DB, sourceURL, migrationsTable string) (*Migrator, error) {
	if err := validateMigrationsTable(migrationsTable); err != nil {
		return nil, fmt.Errorf("invalid migrations table name: %w", err)
	}

	instance, err := mysql.WithInstance(db, &mysql.Config{
		MigrationsTable: migrationsTable,
	})
	if err != nil {
		return nil, fmt.Errorf("error creating instance: %w", err)
	}

	m, err := migrate.NewWithDatabaseInstance(sourceURL, "mysql", instance)
	if err != nil {
		return nil, fmt.Errorf("error instantiating migrate from instance: %w", err)
	}

	return newWithLogger(m, opts.Logger), nil
}

func validateMigrationsTable(migrationsTable string) error {
	// This is a defensive means for folks who may be using this in GHES to
	// prevent them from overriding the Rails migration table with the same name.
	// Alternatively, we may be able to extend this to explicitly force users to
	// allow the default name if they truly want to use this.
	if migrationsTable == "schema_migrations" {
		return fmt.Errorf("migrations table name cannot be named `schema_migrations`")
	}

	if migrationsTable == "" {
		return fmt.Errorf("migrations table name cannot be blank")
	}
	return nil
}

// Migrate executes each migration one by one, checking to see if there's a
// transition at each step.
func (m *Migrator) Migrate(ctx context.Context, transitions *dbmigrator.Transitioner, eventFilename string) error {
	writer := io.Discard
	if eventFilename != "" {
		file, err := os.OpenFile(eventFilename, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o644) // #nosec
		if err != nil {
			m.logger.WithError(err).Warn("could not open events file")
		} else {
			defer func() {
				if closeErr := file.Close(); closeErr != nil {
					m.logger.WithError(closeErr).Warn("could not close events file")
				}
			}()
			writer = file
		}
	}

	events := json.NewEncoder(writer)

	// Attempt any transitions that may exist on the current schema version
	if err := m.attemptTransition(ctx, transitions, events); err != nil {
		return fmt.Errorf("error attempting transition for initial version: %w", err)
	}

	// Loop through every single migration one step at a time, also check for
	// transitions that come after that migration. The underlying algorithm is the
	// following:
	//
	// (1) Check the migration version and see if there are any transitions defined
	// for this version. Returns any errors for this.
	// (2) See if there are any transitions defined for this version. Execute if
	// they do exist. Returns any errors from this.
	// (3) Apply the next migration. If error is returned and equals
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
			return fmt.Errorf("error applying migration step: %w", err)
		}

		if err = m.attemptTransition(ctx, transitions, events); err != nil {
			return fmt.Errorf("attempting transition: %w", err)
		}
	}

	return nil
}

// Rollback rolls back the last migration.
func (m *Migrator) Rollback() error {
	return m.migrate.Steps(-1)
}

func noMoreMigrations(err error) bool {
	return os.IsNotExist(err)
}

func (m *Migrator) attemptTransition(ctx context.Context, transitions *dbmigrator.Transitioner, events *json.Encoder) error {
	version, _, err := m.migrate.Version()
	if err != nil {
		// No migrations have been applied yet, so we can't run any transitions.
		if errors.Is(err, migrate.ErrNilVersion) {
			return nil
		}

		return fmt.Errorf("error checking migration version for transition: %w", err)
	}

	if transition, ok := transitions.GetTransition(version); ok {
		v := kvp.Uint("gh.go-dbmigrator.schema_version", version)
		m.logger.Info("executing transition function", v)
		if transition != nil {
			m.publishEvent("start_event", version, events)
			err := transition.Run(ctx)
			if err != nil {
				m.publishEvent("error_event", version, events)
				return fmt.Errorf("error executing transition for schema version: %d: %w", version, err)
			}
			m.publishEvent("end_event", version, events)
		}
		m.logger.Info("finished executing transition function", v)
	}

	return nil
}

// Close closes the underlying source and database.
func (m *Migrator) Close() error {
	sourceErr, databaseErr := m.migrate.Close()
	if sourceErr != nil {
		return fmt.Errorf("error closing source: %w", sourceErr)
	}

	if databaseErr != nil {
		return fmt.Errorf("error closing database: %w", databaseErr)
	}

	return nil
}

// publishEvent publishes start/end events for each migration to a file in json format.
// These events are consumed by GHES workflow to add additional observability to the migration process.
// The main consumer of these events is ghe-migrations tool.
func (m *Migrator) publishEvent(eventType string, version uint, events *json.Encoder) {
	event := Event{
		Version:      version,
		Time:         time.Now(),
		EventVersion: "v1",
		EventType:    eventType,
	}

	if err := events.Encode(event); err != nil {
		m.logger.WithError(err).Info("Error Publishing event for schema migration", kvp.String("gh.go-dbmigrator.event", eventType), kvp.Uint("gh.go-dbmigrator.schema_version", version))
	}
}
