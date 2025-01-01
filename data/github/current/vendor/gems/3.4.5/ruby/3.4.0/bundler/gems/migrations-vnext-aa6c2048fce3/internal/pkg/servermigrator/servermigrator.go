// Package servermigrator contains code for live migrating resources
// from Enterprise Server.
package servermigrator

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/adapters/googlegithub"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/go-chi/chi/v5"
	"github.com/google/go-github/v65/github"
)

// ServerMigrator represents the migration daemon, encapsulating its
// configuration and behavior.
type (
	ServerMigrator struct {
		httpServer      *http.Server
		listenAddr      string
		logger          log.Logger
		migrationClient MigrationTargetAPI
		resourceFetcher *ResourceFetcher
		org             string

		// secretToken is the secret token configured within the webhooks.
		// This token is used to validate authenticity of the payload. For
		// more information, see:
		// https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
		secretToken []byte

		statter stats.Client
	}
)

// New creates and returns a new instance of ServerMigrator. Options
// may be supplied through the `opts` argument to configure the
// migrator.
func New(opts ...Option) (*ServerMigrator, error) {
	m := &ServerMigrator{
		logger:      log.NewNullLogger(),
		secretToken: nil,
		statter:     stats.NullStatter,
	}

	// Configure the ServerMigrator by invoking the options
	for _, opt := range opts {
		opt(m)
	}

	// Validate the configuration
	if err := m.validate(); err != nil {
		return m, fmt.Errorf("invalid configuration provided: %w", err)
	}

	m.setupHTTPServer()

	return m, nil
}

// Run starts the HTTP server and listens for incoming connections.
// In the future, it will also start the crawling process for resource
// discovery.
//
// Returns an error if the HTTP server fails to start or encounters an issue
// while running.
func (m *ServerMigrator) Run() error {
	if err := m.httpServer.ListenAndServe(); err != nil {
		// If the server was shut down gracefully, return nil
		if errors.Is(err, http.ErrServerClosed) {
			m.logger.Info("server shut down gracefully")
			return nil
		}
		// Otherwise, log the error and return it
		m.logger.WithError(err).Error("error running HTTP server")
		return err
	}
	return nil
}

// Shutdown gracefully shuts down the HTTP server.
func (m *ServerMigrator) Shutdown(ctx context.Context) error {
	return m.httpServer.Shutdown(ctx)
}

func (m *ServerMigrator) setupHTTPServer() {
	r := chi.NewRouter()
	r.Post("/api/v1/webhooks", m.webhookHandler)

	m.httpServer = &http.Server{
		Addr:              m.listenAddr,
		Handler:           r,
		ReadHeaderTimeout: 2 * time.Second,
	}
}

func (m *ServerMigrator) validate() error {
	if _, _, err := net.SplitHostPort(m.listenAddr); err != nil {
		return fmt.Errorf("invalid listen address set. must be 'ip:port', got %q", m.listenAddr)
	}

	if m.migrationClient == nil {
		return errors.New("must have a mvn client")
	}

	if m.org == "" {
		return errors.New("must have an org")
	}

	return nil
}

func (m *ServerMigrator) createMannequins(ctx context.Context, users ...*github.User) error {
	for _, u := range users {
		user := googlegithub.User{User: *u}
		convU, err := user.ToV1Mannequin(m.org)
		if err != nil {
			return fmt.Errorf("error converting github.User to v1.Mannequin: %w", err)
		}
		err = m.migrationClient.SendResources(
			ctx,
			"",
			[]*v1.Resource{
				{
					Resource: &v1.Resource_Mannequin{
						Mannequin: convU,
					},
				},
			})
		if err != nil {
			return fmt.Errorf("error sending mannequin resource %w", err)
		}
	}
	return nil
}
