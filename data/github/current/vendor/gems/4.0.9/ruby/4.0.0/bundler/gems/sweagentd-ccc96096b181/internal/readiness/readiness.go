// Package readiness provides utilities for Kubernetes readiness probes and health checks.
package readiness

import (
	"context"
	"os"

	"github.com/github/sweagentd/internal/goerrors"
)

// DefaultProbeFilePath is the default path for the readiness probe file.
const DefaultProbeFilePath = "/tmp/consumer_healthy"

// HealthChecker is an interface for checking the health of a service dependency.
type HealthChecker interface {
	HealthCheck(ctx context.Context) error
}

// Probe manages the readiness state and health checks for a service.
type Probe struct {
	filePath string
	checkers []HealthChecker
}

// Option is a functional option for configuring a Probe.
type Option func(*Probe)

// WithFilePath sets a custom file path for the readiness probe.
func WithFilePath(path string) Option {
	return func(p *Probe) {
		p.filePath = path
	}
}

// WithHealthChecker adds a health checker to verify before marking the service as ready.
func WithHealthChecker(checker HealthChecker) Option {
	return func(p *Probe) {
		if checker != nil {
			p.checkers = append(p.checkers, checker)
		}
	}
}

// NewProbe creates a new readiness probe with the given options.
func NewProbe(opts ...Option) *Probe {
	p := &Probe{
		filePath: DefaultProbeFilePath,
		checkers: make([]HealthChecker, 0),
	}

	for _, opt := range opts {
		opt(p)
	}

	return p
}

// MarkReady creates the readiness probe file after verifying all health checks pass.
// This signals to Kubernetes that the pod is ready to receive traffic.
func (p *Probe) MarkReady(ctx context.Context) error {
	// Verify all health checks pass before creating the probe file.
	for _, checker := range p.checkers {
		err := checker.HealthCheck(ctx)
		if err != nil {
			return goerrors.Errorf("health check failed: %w", err)
		}
	}

	//nolint:gosec // G303: Shared tmp directory is acceptable for readiness probe file
	_, err := os.Create(p.filePath)
	if err != nil {
		return goerrors.Errorf("error creating readiness probe file: %w", err)
	}

	return nil
}

// MarkNotReady removes the readiness probe file, signaling that the pod
// should no longer receive traffic.
func (p *Probe) MarkNotReady() error {
	err := os.Remove(p.filePath)
	if err != nil && !os.IsNotExist(err) {
		return goerrors.Errorf("error removing readiness probe file: %w", err)
	}

	return nil
}
