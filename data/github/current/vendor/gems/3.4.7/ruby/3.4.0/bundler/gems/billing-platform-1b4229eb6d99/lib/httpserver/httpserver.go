package httpserver

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/log"
	exceptions "github.com/github/go-exceptions"
	"github.com/pkg/errors"
)

type GracefulServer struct {
	Server           *http.Server
	shutdownFinished chan struct{}
	logger           log.Logger
	errorReporter    *exceptions.Reporter
}

func NewGracefulServer(port int, handler http.Handler, logger log.Logger, flagger *vexi.Client, errorReporter *exceptions.Reporter) *GracefulServer {
	server := &GracefulServer{
		Server: &http.Server{
			Addr:    fmt.Sprintf(":%d", port),
			Handler: handler,
		},
		logger:        logger.Named("GracefulServer"),
		errorReporter: errorReporter,
	}
	return server
}

func (s *GracefulServer) ListenAndServe() error {
	if s.shutdownFinished == nil {
		s.shutdownFinished = make(chan struct{})
	}

	err := s.Server.ListenAndServe()
	if err != nil && err != http.ErrServerClosed {
		s.logger.WithError(err).Error("unexpected error from ListenAndServe")
		_ = s.errorReporter.Report(context.Background(), err, nil)
		return errors.Wrap(err, "unexpected error from ListenAndServe")
	}

	<-s.shutdownFinished
	return nil
}

func (s *GracefulServer) WaitForExitingSignal(timeout time.Duration) {
	waiter := make(chan os.Signal, 1) // buffered channel
	signal.Notify(waiter, syscall.SIGTERM, syscall.SIGINT)

	// blocks here until there's a signal
	receivedSignal := <-waiter

	s.logger.Info("received shutdown signal, shutting down..")
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	err := s.Server.Shutdown(ctx)
	if err != nil {
		_ = s.errorReporter.Report(context.Background(), err, map[string]string{"location": "failed to shutdown GracefulServer gracefully", "signal": receivedSignal.String(), "timeout": timeout.String()})
		s.logger.WithError(err).Error("failed to shutdown gracefully")
	} else {
		close(s.shutdownFinished)
	}
}
