package servermigrator

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

// Option defines the option function signature which may be
// used to configure a serverMigrator.
type Option func(m *ServerMigrator)

// WithListenAddr sets the `ip:port` that will be listened on.
func WithListenAddr(l string) Option {
	return func(m *ServerMigrator) {
		m.listenAddr = l
	}
}

// WithLogger configures the logger that will be used by the
// serverMigrator.
func WithLogger(l log.Logger) Option {
	return func(m *ServerMigrator) {
		m.logger = l
	}
}

// WithResourceFetcher configures the resource fetcher that will
// be used by the serverMigrator.
func WithResourceFetcher(r *ResourceFetcher) Option {
	return func(m *ServerMigrator) {
		m.resourceFetcher = r
	}
}

// WithSecretToken configures the secret token that will be used
// by the serverMigrator.
func WithSecretToken(s string) Option {
	return func(m *ServerMigrator) {
		m.secretToken = []byte(s)
	}
}

// WithOrganization configures the organization that will be used
// by the serverMigrator.
func WithOrganization(o string) Option {
	return func(m *ServerMigrator) {
		m.org = o
	}
}

// WithMigrationTargetClient configures the migration target client
// that will be used by the serverMigrator.
func WithMigrationTargetClient(c MigrationTargetAPI) Option {
	return func(m *ServerMigrator) {
		m.migrationClient = c
	}
}

// WithStatter sets the `stats.Client` that will be used.
func WithStatter(s stats.Client) Option {
	return func(m *ServerMigrator) {
		m.statter = s
	}
}
