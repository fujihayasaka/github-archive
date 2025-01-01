// Package pprof creates a new service to expose profiling information, it
// follows  https://github.com/github/pyroscope#how-to-profile-your-application
// which would give us a paved path toward Pyroscope support in the future,
// if needed.
package pprof

import (
	"context"
	"fmt"
	"net/http"
	"net/http/pprof"
	"runtime"
	"time"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/log"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/shutdown"
)

// Service represents a pprof service.
type Service struct {
	logger log.Logger
	*http.Server
}

// NewService creates a new pprof service.
func NewService(address string, clock clockpkg.Clock, logger log.Logger) Service {
	mux := http.NewServeMux()
	mux.HandleFunc("/debug/pprof/", pprof.Index)
	mux.HandleFunc("/debug/pprof/cmdline", pprof.Cmdline)
	mux.HandleFunc("/debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("/debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("/debug/pprof/trace", pprof.Trace)
	// Used by https://opaque.githubapp.com/
	mux.HandleFunc("/_ping", func(writer http.ResponseWriter, request *http.Request) {
		_, _ = fmt.Fprintf(writer, "OK - %s - DONE", clock.Now())
	})

	return Service{
		logger: logger,
		Server: &http.Server{
			Addr:              address,
			Handler:           mux,
			ReadHeaderTimeout: 2 * time.Second,
		},
	}
}

// Run starts the service and returns the cleanup function.
func (s Service) Run(ctx context.Context) shutdown.Cleanup {
	s.logger.WithContext(ctx).Info("API server starting")

	// Enable block profiling.
	// When the block profiler is enabled, all events where duration >= rate are captured, and shorter events have a duration/rate chance of being captured.
	// For example, if a rate of 100_000_000 nanoseconds is set, all blocking events lasting 100 milliseconds or longer are captured.
	// In addition, 10% of events lasting 10 milliseconds, 1% of events lasting 1 millisecond, etc., are captured.
	runtime.SetBlockProfileRate(100_000_000 /* ns */)

	go func() {
		if err := s.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			s.logger.WithContext(ctx).WithError(err).Info("error starting the pprof server")
		}
	}()
	return s.Shutdown
}
