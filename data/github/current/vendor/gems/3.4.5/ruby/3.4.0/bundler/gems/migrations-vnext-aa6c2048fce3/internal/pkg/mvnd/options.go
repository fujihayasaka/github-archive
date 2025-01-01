package mvnd

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
)

// Option defines the function signature for configuring an `Mvnd`
// instance.
type Option func(m *Mvnd)

// WithListenAddr sets the `ip:port` that will be listened on.
func WithListenAddr(l string) Option {
	return func(m *Mvnd) {
		m.listenAddr = l
	}
}

// WithLogger sets the logger that will be used.
func WithLogger(l log.Logger) Option {
	return func(m *Mvnd) {
		m.logger = l
	}
}

// WithManager sets the `Manager` that will be used.
func WithManager(manager dag.Manager) Option {
	return func(m *Mvnd) {
		m.manager = manager
	}
}

// WithStatter sets the `stats.Client` that will be used.
func WithStatter(s stats.Client) Option {
	return func(m *Mvnd) {
		m.statter = s
	}
}

// WithHMACKeys sets the HMAC keys for request verification
func WithHMACKeys(keys []string) Option {
	return func(m *Mvnd) {
		m.hmacKeys = keys
	}
}

// WithSASGenerator sets the `blobstore.SASGenerator` that will be used.
func WithSASGenerator(b blobstore.SASGenerator) Option {
	return func(m *Mvnd) {
		m.sasGenerator = b
	}
}
