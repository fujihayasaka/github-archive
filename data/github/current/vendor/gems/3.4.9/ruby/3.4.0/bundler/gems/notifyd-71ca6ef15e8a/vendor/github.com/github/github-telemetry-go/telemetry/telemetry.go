package telemetry

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/trace"
	"github.com/github/go-config"
	"github.com/hashicorp/go-multierror"
)

// Provider is a convenience struct that offers a way to initialize and return
// each type of instrumentation (logging, statting, tracing, etc.)
type Provider struct {
	Logger log.Logger
	Tracer *trace.Tracer
}

// NewFromEnv is a convenient entrypoint for telemetry
// - Reads default configuration
// - Allows configuration overrides
// - Initializes default versions of everything (f.e., log, trace, stats, etc.)
// Note that the default logger is configured as part of this function so that static logging
// will work.
func NewFromEnv(telemetryOpts ...TelemetryOption) (*Provider, error) {
	tp := &Provider{}

	var cfg Config
	if err := config.Load(&cfg); err != nil {
		return nil, fmt.Errorf("error loading configuration: %w", err)
	}

	// Adding telemetry options to config
	for _, opt := range telemetryOpts {
		opt(&cfg)
	}

	logger, err := log.NewFromConfig(cfg.Logging, cfg.loggingOpts...)
	if err != nil {
		return nil, err
	}
	log.SetDefault(logger)

	tracer, err := trace.NewFromConfig(cfg.Tracing, cfg.tracingOpts...)
	if err != nil {
		return nil, err
	}

	tp.Logger = logger
	tp.Tracer = tracer
	return tp, nil
}

// NewFromConfig is an entrypoint for telemetry where you provide your own
// configuration values rather than relying on environment variables.
//
// Note that the default logger is _not_ configured as part of this function
// If a global logger is desired, call log.SetDefault with the returned logger
// after calling NewFromConfig. Failure to do so will mean that you cannot
// use the global logging functions (and you will likely get no logs from
// libraries, either).
func NewFromConfig(cfg Config, telemetryOpts ...TelemetryOption) (*Provider, error) {
	// Adding telemetry options to config
	for _, opt := range telemetryOpts {
		opt(&cfg)
	}

	tp := &Provider{}

	logger, err := log.NewFromConfig(cfg.Logging, cfg.loggingOpts...)
	if err != nil {
		return nil, err
	}

	tracer, err := trace.NewFromConfig(cfg.Tracing, cfg.tracingOpts...)
	if err != nil {
		return nil, err
	}

	tp.Logger = logger
	tp.Tracer = tracer
	return tp, nil
}

// The telemetry provider Shutdown gracefully shuts down the configured telemetry
//
// This enables customers to shutdown all instances in a single function call
// For example:
//
//	if err := tp.Shutdown(ctx); err != nil {
//	  fmt.Printf("failed to shutdown telemetry: %v", err)
//	}
func (p *Provider) Shutdown(ctx context.Context) error {
	var errs error = nil

	if err := p.Tracer.Provider.Shutdown(ctx); err != nil {
		p.Logger = p.Logger.WithError(err)
		errs = multierror.Append(errs, fmt.Errorf("failed to shut down tracer: %w", err))
	}

	// Shutdown the logger at last so all failures before this point can be logged
	if err := p.Logger.Sync(); err != nil {
		errs = multierror.Append(errs, fmt.Errorf("failed to shut down logger: %w", err))
	}

	return errs
}
