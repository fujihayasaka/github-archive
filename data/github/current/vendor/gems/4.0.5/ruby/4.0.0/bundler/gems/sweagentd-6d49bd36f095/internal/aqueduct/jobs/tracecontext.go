package jobs

import (
	"context"

	"go.opentelemetry.io/otel/propagation"
)

// mapCarrier adapts a map[string]string to the propagation.TextMapCarrier interface.
type mapCarrier map[string]string

func (c mapCarrier) Get(key string) string { return c[key] }
func (c mapCarrier) Set(key, value string) { c[key] = value }
func (c mapCarrier) Keys() []string {
	keys := make([]string, 0, len(c))
	for k := range c {
		keys = append(keys, k)
	}
	return keys
}

var propagator = propagation.TraceContext{}

// InjectTraceContext injects the W3C traceparent and tracestate from the
// context's span into the provided headers map. If there is no active span
// in the context, this is a no-op.
func InjectTraceContext(ctx context.Context, headers map[string]string) {
	propagator.Inject(ctx, mapCarrier(headers))
}

// ExtractTraceContext extracts the W3C traceparent and tracestate from the
// provided headers and returns a new context with the remote span context set.
// If there is no traceparent in the headers, the original context is returned.
func ExtractTraceContext(ctx context.Context, headers map[string]string) context.Context {
	return propagator.Extract(ctx, mapCarrier(headers))
}
