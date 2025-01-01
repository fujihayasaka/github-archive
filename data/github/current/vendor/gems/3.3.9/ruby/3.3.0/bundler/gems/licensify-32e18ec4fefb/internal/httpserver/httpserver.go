// Package httpserver provides a graceful server that can be used to serve HTTP requests.
package httpserver

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/github-telemetry-go/log"
	exceptions "github.com/github/go-exceptions"
)

// GracefulServer is a server that can be gracefully shutdown.
type GracefulServer struct {
	Server           *http.Server
	shutdownFinished chan struct{}
	logger           log.Logger
	errorReporter    *exceptions.Reporter
}

// NewGracefulServer creates a new GracefulServer.
func NewGracefulServer(port int, handler http.Handler, logger log.Logger, errorReporter *exceptions.Reporter) *GracefulServer {
	const readHeaderTimeout = 5 * time.Second
	server := &GracefulServer{
		Server: &http.Server{
			Addr:              fmt.Sprintf(":%d", port),
			Handler:           handler,
			ReadHeaderTimeout: readHeaderTimeout,
		},
		logger:        logger.Named("GracefulServer"),
		errorReporter: errorReporter,
	}
	return server
}

// ListenAndServe starts the server and blocks until the server is gracefully shutdown.
func (s *GracefulServer) ListenAndServe() error {
	if s.shutdownFinished == nil {
		s.shutdownFinished = make(chan struct{})
	}

	err := s.Server.ListenAndServe()
	if err != nil && err != http.ErrServerClosed {
		s.logger.WithError(err).Error("unexpected error from ListenAndServe")
		_ = s.errorReporter.Report(context.Background(), err, nil)
		return fmt.Errorf("unexpected error from ListenAndServe: %w", err)
	}

	<-s.shutdownFinished
	return nil
}

// WaitForExitingSignal waits for a signal to shutdown the server.
func (s *GracefulServer) WaitForExitingSignal(timeout time.Duration) {
	waiter := make(chan os.Signal, 1) // buffered channel
	signal.Notify(waiter, syscall.SIGTERM, syscall.SIGINT)

	// blocks here until there's a signal
	<-waiter

	s.logger.Info("received shutdown signal, shutting down..")
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	err := s.Server.Shutdown(ctx)
	if err != nil {
		_ = s.errorReporter.Report(context.Background(), err, nil)
		s.logger.WithError(err).Error("failed to shutdown gracefully")
	} else {
		close(s.shutdownFinished)
	}
}
