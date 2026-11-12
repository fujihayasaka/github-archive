package propagators

import (
	"context"

	"github.com/google/uuid"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

// RequestIDPropagator implements [propagation.TextMapPropagator]
type RequestIDPropagator struct{}

const requestIDField = "x-request-id"
const githubRequestIDField = "x-github-request-id"
const requestIDContextKey contextKey = requestIDField
const githubRequestIDContextKey contextKey = githubRequestIDField

type contextKey string

// Inject adds x-github-request-id and x-request-id headers into the [propagation.TextMapCarrier].
//
// For x-github-request-id, the value will be set to:
//   - the x-github-request-id on the carrier, if it exists; otherwise
//   - x-github-request-id from the context, if it exists; otherwise
//   - trace-id, if it exists; otherwise falls back to
//   - a UUID
//
// For x-request-id, the injected value will be the x-request-id from the context,
// if it exists. Otherwise, the trace id is used as a fallback.
func (p RequestIDPropagator) Inject(ctx context.Context, carrier propagation.TextMapCarrier) {
	// Handle x-github-request-id
	githubRequestID := carrier.Get(githubRequestIDField)
	if githubRequestID == "" {
		// Check for existing GitHub request IDs in the context
		var ok bool
		githubRequestID, ok = ctx.Value(githubRequestIDContextKey).(string)
		if !ok || githubRequestID == "" {
			sp := trace.SpanContextFromContext(ctx)
			if sp.IsValid() {
				githubRequestID = sp.TraceID().String()
			} else {
				// Fallback to a UUID
				githubRequestID = uuid.New().String()
			}
		}
	}
	carrier.Set(githubRequestIDField, githubRequestID)

	// Handle x-request-id
	requestID, ok := ctx.Value(requestIDContextKey).(string)
	if ok && requestID != "" {
		carrier.Set(requestIDField, requestID)
	} else {
		// Fallback to using the w3 trace-id
		carrier.Set(requestIDField, trace.SpanContextFromContext(ctx).TraceID().String())
	}
}

// Extract extracts the x-github-request-id and x-request-id headers from the incoming request and sets them in the context
func (p RequestIDPropagator) Extract(ctx context.Context, carrier propagation.TextMapCarrier) context.Context {
	githubRequestID := carrier.Get(githubRequestIDField)
	if githubRequestID != "" {
		// Set the GitHub request ID in the context
		ctx = context.WithValue(ctx, githubRequestIDContextKey, githubRequestID)
	}

	requestID := carrier.Get(requestIDField)
	if requestID != "" {
		// Set the request ID in the context
		ctx = context.WithValue(ctx, requestIDContextKey, requestID)
	}
	return ctx
}

// Fields returns the keys whose values are set with Inject.
func (p RequestIDPropagator) Fields() []string {
	return []string{requestIDField, githubRequestIDField}
}
