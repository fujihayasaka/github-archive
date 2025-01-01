package upgrades

import (
	"context" //lint:ignore faillint importing for errors.Join
	"fmt"
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/pkg/errors"
)

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

func attemptTransition(ctx context.Context, migrator *migrate.Migrate, transitions map[uint]func(ctx context.Context) error) error {
	version, _, err := migrator.Version()
	migrator.Log.Printf("detecting transition for version %d", version)
	if err != nil {
		// No migrations have been applied yet, so we can't run any transitions.
		if errors.Is(err, migrate.ErrNilVersion) {
			return nil
		}

		return errors.Wrap(err, "error checking migration version for transition: %w")
	}

	if transition, ok := transitions[version]; ok && transition != nil {
		migrator.Log.Printf("starting transition for %d", version)
		err := transition(ctx)
		if err != nil {
			return errors.Wrap(err, fmt.Sprintf("error executing transition for schema version: %d", version))
		}
		migrator.Log.Printf("completed transition %d", version)
	}

	return nil
}

// Migrate executes each migration one by one, checking to see if there's a
// transition at each step.
func doMigrate(ctx context.Context, migrator *migrate.Migrate, transitions map[uint]func(ctx context.Context) error) error {
	migrator.Log.Printf("starting migrations...")

	// Attempt any transitions that may exist on the current schema version
	if err := attemptTransition(ctx, migrator, transitions); err != nil {
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
	// (3) Apply the next migration. If error is returned and equals
	// `ErrNoChange`, break the loop, otherwise return the error.
	// (4) GOTO (1)
	for {
		err := migrator.Steps(1)
		if os.IsNotExist(err) {
			break
		}
		if err != nil {
			return errors.Wrap(err, "error applying migration step")
		}

		if err = attemptTransition(ctx, migrator, transitions); err != nil {
			return errors.Wrap(err, "attempting transition")
		}
	}

	return nil
}
