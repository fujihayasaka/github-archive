// Package shutdown provides primitives for an ordered graceful shutdown.
// There should be at most one shutdown instance per program.
package shutdown

import (
	"context"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/hashicorp/go-multierror"

	"github.com/github/notifyd/internal/pkg/errors"
)

// Cleanup is a function that performs a cleanup process.
type Cleanup func(ctx context.Context) error

// Shutdown represents a graceful shutdown process.
type Shutdown struct {
	cleanups []Cleanup
	timeout  time.Duration
	logger   log.Logger
}

// New shutdown instance. It should only be called once per program.
func New(timeout time.Duration, logger log.Logger) *Shutdown {
	return &Shutdown{timeout: timeout, logger: logger}
}

// Register a new Cleanup. Cleanup functions will be called in register order.
func (s *Shutdown) Register(c Cleanup) {
	s.cleanups = append(s.cleanups, c)
}

// Wait for the stop signal and call registered cleanup functions in order.
func (s *Shutdown) Wait(ctx context.Context) error {
	sigint := make(chan os.Signal, 1)
	signal.Notify(sigint, os.Interrupt, syscall.SIGTERM)
	<-sigint
	s.logger.WithContext(ctx).Info("Interruption signal received, starting shutdown process")

	ctx, cancel := context.WithTimeout(ctx, s.timeout)
	defer cancel()
	var err error
	for _, cleanup := range s.cleanups {
		if stopErr := cleanup(ctx); stopErr != nil {
			err = multierror.Append(err, stopErr)
		}
	}
	s.cleanups = nil
	return err
}

// WrapNoContext wraps a cleanup function that doesn't handle context.
func WrapNoContext(f func() error) Cleanup {
	return func(ctx context.Context) error {
		done := make(chan error)
		go func() { done <- f() }()
		select {
		case err := <-done:
			return err
		case <-ctx.Done():
			return errors.Wrap(ctx.Err(), "timeout during cleanup")
		}
	}
}

// WrapNoError wraps a cleanup function that doesn't return errors.
func WrapNoError(f func(context.Context)) Cleanup {
	return func(ctx context.Context) error {
		f(ctx)
		return nil
	}
}

// WrapNoErrorAndContext wraps a cleanup function that neither handles context nor returns errors.
func WrapNoErrorAndContext(f func()) Cleanup {
	return WrapNoContext(func() error {
		f()
		return nil
	})
}
