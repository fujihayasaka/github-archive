package trace

import (
	"context"
	"io"

	otelSdk "go.opentelemetry.io/otel/sdk/trace"
)

// TracerOption let us configure tracer using TracerConfig
type TracerOption func(*Config)

// WithContext overrides the Tracer context (background context) when new tracer is created.
func WithContext(ctx context.Context) TracerOption {
	return func(c *Config) {
		c.ctx = ctx
	}
}

// WithExporter overrides the behavior of the current exporter config when a new tracer is created.
//
// Use one of these values to set the exporter:
//
//	trace.ExporterOtlpHTTP        // production, send the trace data to an exporter
//	trace.ExporterStdout          // send trace data to stdout
//	trace.ExporterDiscard         // discard all trace output uses stdout
//	trace.ExporterUnknown         // same as ExporterNever
//
// An unkown value will result in ExporterNever being used.
func WithExporter(opt exporterType) TracerOption {
	return func(cfg *Config) {
		cfg.exporter = opt
	}
}

// WithExporterWriter configure an io.Writer
//
// Useful in setting the stdout writer to an io.Writer when
// trace.ExporterStdout is set as an option with WithExporter(trace.ExporterStdout).
// For example, this can then be used in looking at the output of a trace in testing.
func WithExporterWriter(io io.Writer) TracerOption {
	return func(cfg *Config) {
		cfg.exporterWriter = io
	}
}

// TODO: revisit if we need this as users should override name through env vars. Example service which needs this is containers not executed thr Moda
//
// # WithServiceName assigns the tracer a name
//
// This is useful when a custom name is being set and SERVICE_NAME is not set.
// Otherwise we set the name for the resource from SERVICE_NAME.
func WithServiceName(name string) TracerOption {
	return func(cfg *Config) {
		cfg.serviceName = &name
	}
}

// WithServiceVersion assigns the instrumentation version to the tracer
//
// This is useful for configuring the instrumentation version to an alternate value
// and when SERVICE_VERSION is not set. Otherwise we set the version from SERVICE_VERSION or
// let the resource tracer.sdk.version be the default value.
func WithServiceVersion(version string) TracerOption {
	return func(cfg *Config) {
		cfg.serviceVersion = &version
	}
}

// WithTracerProviderOptions allows for additional configuration to be passed to a tracer when created
//
// For example, if you want to change default sampler on tracer:
//
//	tracer, err := trace.NewFromEnv(
//		trace.WithTracerProviderOptions(
//			otelSdk.WithRawSpanLimits(otelSdk.SpanLimits{EventCountLimit: 2})
//		)
//	)
//
// When adding customizations be sure to import: `otelSdk "go.opentelemetry.io/otel/sdk/trace"`
// See the OpenTelemetry documentation (https://pkg.go.dev/go.opentelemetry.io/otel/sdk/trace#TracerProviderOption)
// for more details and useful functions on creating otelSdk.TracerProviderOption
func WithTracerProviderOptions(opts ...otelSdk.TracerProviderOption) TracerOption {
	return func(cfg *Config) {
		cfg.providerOptions = opts
	}
}
