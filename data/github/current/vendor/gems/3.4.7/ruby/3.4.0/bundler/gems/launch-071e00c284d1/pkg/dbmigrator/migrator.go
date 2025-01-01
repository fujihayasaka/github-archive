package dbmigrator

import "context"

type MigrationFunc func(context.Context) error

// Migrator is an interface for applying migrations and transitions for a
// specific database.
type Migrator interface {
	// Migrate executes migrations one at a time checks for any dependencies for each
	// transition before executing them.
	Migrate(ctx context.Context, transitions *Transitioner) error // Return current version here?

	// Close closes any underlying connections.
	Close() error
}
