// Package twirp contains functions for twirp functionality
package twirp

import (
	"fmt"
	"net/http"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/twitchtv/twirp"
)

// Interface enforcement
var _ v1.Migration = &Server{}

// Server is a wrapper for the Twirp server.
type Server struct {
	logger       log.Logger
	manager      dag.Manager
	mux          http.Handler
	statter      stats.Client
	hmacKeys     []string
	sasGenerator blobstore.SASGenerator
}

// NewServer takes the provided options and returns a configured
// `Server`.
func NewServer(opts ...ServerOption) (*Server, error) {
	srv := &Server{
		logger:  log.NewNullLogger(),
		statter: stats.NullStatter,
	}

	for _, opt := range opts {
		opt(srv)
	}

	hooks := twirp.ChainHooks(
		twhooks.TimingHooks(),
		twhooks.StoreTwirpErrorHooks(),
		twlog.DefaultHooks(srv.logger),
		twstats.DefaultHooks(srv.statter),
		twhooks.TraceHooks(),
	)

	migrationServer := v1.NewMigrationServer(srv, hooks)
	hmacValidator := hmac.Validator{
		Secrets: srv.hmacKeys,
		Logger:  srv.logger,
	}

	mux := http.NewServeMux()
	mux.Handle(migrationServer.PathPrefix(), hmacValidator.Handler(migrationServer))
	srv.mux = mux

	if err := srv.validate(); err != nil {
		return srv, fmt.Errorf("invalid twirp server configuration: %w", err)
	}

	return srv, nil
}

// Mux returns the HTTP handler (mux) for the server.
// This handler is used to route incoming HTTP requests to the appropriate handlers.
//
// Returns the HTTP handler for the server.
func (s *Server) Mux() http.Handler {
	return s.mux
}

func (s *Server) validate() error {
	if s.manager == nil {
		return fmt.Errorf("twirp server must have a manager")
	}
	if len(s.hmacKeys) == 0 {
		return fmt.Errorf("twirp server must have at least one HMAC key")
	}
	return nil
}
