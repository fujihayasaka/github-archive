package twirp

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
)

// ServerOption defines the function signature for configuring a `Server`
// instance.
type ServerOption func(s *Server)

// WithLogger sets the logger that will be used.
func WithLogger(l log.Logger) ServerOption {
	return func(s *Server) {
		s.logger = l
	}
}

// WithManager sets the `Manager` that will be used.
func WithManager(m dag.Manager) ServerOption {
	return func(s *Server) {
		s.manager = m
	}
}

// WithStatter sets the `stats.Client` that will be used.
func WithStatter(st stats.Client) ServerOption {
	return func(s *Server) {
		s.statter = st
	}
}

// WithHMACKeys sets the HMAC keys for request verification
func WithHMACKeys(keys []string) ServerOption {
	return func(s *Server) {
		s.hmacKeys = keys
	}
}

// WithSASGenerator sets the `blobstore.SASGenerator` that will be used.
func WithSASGenerator(m blobstore.SASGenerator) ServerOption {
	return func(s *Server) {
		s.sasGenerator = m
	}
}
