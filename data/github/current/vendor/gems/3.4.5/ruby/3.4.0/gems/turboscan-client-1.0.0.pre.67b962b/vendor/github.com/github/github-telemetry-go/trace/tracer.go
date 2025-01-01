// Package trace provides a wrapper around the OpenTelemetry SDK to make it easier to use.
package trace

import (
	"fmt"

	"github.com/github/go-config"
	otelSdk "go.opentelemetry.io/otel/sdk/trace"
	oteltrace "go.opentelemetry.io/otel/trace"
)

// Tracer is a wrapper around the OpenTelemetry SDK.
type Tracer struct {
	config   *Config
	Tracer   oteltrace.Tracer
	Provider *otelSdk.TracerProvider
}

// NewFromEnv is an entrypoint for tracing. It returns the configured Tracer.
func NewFromEnv(opts ...TracerOption) (*Tracer, error) {
	var cfg Config

	if err := config.Load(&cfg); err != nil {
		return nil, fmt.Errorf("error loading tracer configuration: %w", err)
	}

	tracer, err := processConfig(cfg, opts...)
	if err != nil {
		return nil, fmt.Errorf("error configuring tracer: %w", err)
	}
	return tracer, nil
}

// NewFromConfig is an entrypoint for tracing that takes in a configuration struct.
func NewFromConfig(cfg Config, opts ...TracerOption) (*Tracer, error) {
	tracer, err := processConfig(cfg, opts...)
	if err != nil {
		return nil, fmt.Errorf("error configuring tracer: %w", err)
	}

	return tracer, nil
}
