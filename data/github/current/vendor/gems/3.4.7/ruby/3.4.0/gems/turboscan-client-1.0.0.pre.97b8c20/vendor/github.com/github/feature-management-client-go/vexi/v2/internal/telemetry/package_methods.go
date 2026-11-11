package telemetry

import (
	"context"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// NewContextWithTraceID returns a new context with a trace span context with the provided trace id configured. If the provided trace id is not valid, it will return a context with a new trace span context and the error.
func NewContextWithTraceID(ctx context.Context, traceID string) (context.Context, error) {
	sc := trace.SpanContext{}
	tid, err := trace.TraceIDFromHex(traceID)
	if err == nil && tid.IsValid() {
		sc = sc.WithTraceID(tid)
	}
	return trace.ContextWithSpanContext(ctx, sc), err
}

// AddAttributesToSpan adds the provided attributes to the span in the provided context.
func AddAttributesToSpan(ctx context.Context, attributes ...attribute.KeyValue) {
	span := trace.SpanFromContext(ctx)
	span.SetAttributes(attributes...)
}

// RecordErrorToSpan records the provided error to the span in the provided context.
func RecordErrorToSpan(ctx context.Context, err error) {
	span := trace.SpanFromContext(ctx)
	span.RecordError(err)
}

// SetSpanStatus sets the status of the span in the provided context.
func SetSpanStatus(ctx context.Context, code codes.Code, description string) {
	span := trace.SpanFromContext(ctx)
	span.SetStatus(code, description)
}
