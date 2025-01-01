// Package mvnd contains the domain logic for the migrations-vnext daemon
package mvnd

import (
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/twirp"
	"github.com/github/otel-instrumentation-go/oteltwirp"
)

// Mvnd represents the migrations-vnext daemon, encapsulating its
// configuration and behavior.
type Mvnd struct {
	listenAddr   string
	httpServer   *http.Server
	logger       log.Logger
	manager      dag.Manager
	statter      stats.Client
	hmacKeys     []string
	sasGenerator blobstore.SASGenerator
}

// New creates and returns a new `Mvnd` configured with the provided
// options. If the configuration is determined to be illegal an error
// will be returned.
func New(opts ...Option) (*Mvnd, error) {
	m := &Mvnd{
		listenAddr: ":80",
		logger:     log.NewNullLogger(),
		statter:    stats.NullStatter,
	}

	for _, opt := range opts {
		opt(m)
	}

	twirpSrv, err := twirp.NewServer(
		twirp.WithLogger(m.logger),
		twirp.WithManager(m.manager),
		twirp.WithStatter(m.statter),
		twirp.WithHMACKeys(m.hmacKeys),
		twirp.WithSASGenerator(m.sasGenerator),
	)
	if err != nil {
		return m, fmt.Errorf("error creating twirp server: %w", err)
	}

	m.httpServer = &http.Server{
		Addr:              m.listenAddr,
		Handler:           oteltwirp.Middleware(twirpSrv.Mux()),
		ReadHeaderTimeout: 2 * time.Second,
	}

	if err := m.validate(); err != nil {
		return m, fmt.Errorf("invalid configuration provided: %w", err)
	}

	return m, nil
}

// Run starts the HTTP server and listens for incoming connections.
// If the server encounters an error, it logs the error and returns it.
//
// Returns an error if the HTTP server fails to start or encounters an issue
// while running.
func (m *Mvnd) Run() error {
	if err := m.httpServer.ListenAndServe(); err != nil {
		m.logger.Error("error running HTTP server", kvp.Err(err))
		return err
	}
	return nil
}

func (m *Mvnd) validate() error {
	if _, _, err := net.SplitHostPort(m.listenAddr); err != nil {
		return fmt.Errorf("invalid listen address set. must be 'ip:port', got %q", m.listenAddr)
	}
	if len(m.hmacKeys) == 0 {
		return fmt.Errorf("must have at least one HMAC key")
	}
	return nil
}
