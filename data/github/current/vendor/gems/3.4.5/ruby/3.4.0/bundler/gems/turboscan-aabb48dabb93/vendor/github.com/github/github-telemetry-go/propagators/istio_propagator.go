package propagators

import (
	"context"

	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

// IstioPropagator implements [propagation.TextMapPropagator]
type IstioPropagator struct{}

const requestIDField = "x-request-id"
const requestIDContextKey contextKey = requestIDField

// Inject adds x-request-id headers into the [propagation.TextMapCarrier]. The injected value will be the x-request-id
// from the context, if it exists. Otherwise, the trace id is used as a fallback.
func (p IstioPropagator) Inject(ctx context.Context, carrier propagation.TextMapCarrier) {
	requestID, ok := ctx.Value(requestIDContextKey).(string)
	if ok && requestID != "" {
		carrier.Set(requestIDField, requestID)
		return
	}

	// Fallback to using the w3 trace-id
	carrier.Set(requestIDField, trace.SpanContextFromContext(ctx).TraceID().String())
}

// Extract extracts the x-request-id header from the incoming request and sets it in the context
func (p IstioPropagator) Extract(ctx context.Context, carrier propagation.TextMapCarrier) context.Context {
	requestID := carrier.Get(requestIDField)
	if requestID != "" {
		// Set the request ID in the context or span
		return context.WithValue(ctx, requestIDContextKey, requestID)
	}
	return ctx
}

// Fields returns the keys whose values are set with Inject.
func (p IstioPropagator) Fields() []string {
	return []string{requestIDField}
}
