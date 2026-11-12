package oteltwirp

import "go.opentelemetry.io/otel/trace"

// TraceOptions holds configuration for TraceHTTPClient.
type TraceOptions struct {
	tracerProvider trace.TracerProvider
}

// TraceOption is a functional option for configuring TraceHTTPClient.
type TraceOption func(*TraceOptions)

// WithTracerProvider sets a specific [trace.TracerProvider] for the client.
// If not set, the global provider from [otel.GetTracerProvider] is used.
func WithTracerProvider(tp trace.TracerProvider) TraceOption {
	return func(opts *TraceOptions) {
		opts.tracerProvider = tp
	}
}
