// Package chatopsservice implements a service for handling chatops requests.
package chatopsservice

import (
	"context"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/shutdown"
)

// Service represents the chatops service.
type Service struct {
	*http.Server
	telem *telemetry.Provider
}

// NewService builds a new API service for ChatOps handler.
func NewService(address string, telem *telemetry.Provider, handler http.Handler) Service {
	return Service{
		Server: &http.Server{
			Addr:              address,
			Handler:           handler,
			ReadHeaderTimeout: 2 * time.Second,
			ReadTimeout:       2 * time.Second,
			WriteTimeout:      2 * time.Second,
		},
		telem: telem,
	}
}

// Run starts the service and returns the cleanup function.
func (s Service) Run(ctx context.Context) shutdown.Cleanup {
	s.telem.Logger.WithContext(ctx).Info("Chatops server starting")
	go func() {
		if err := s.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			s.telem.Logger.WithContext(ctx).WithError(err).Error("error starting the chatops server")
		}
	}()
	return s.Shutdown
}
