package tracing

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/trace"
	"github.com/github/go-kvp"
	"go.opentelemetry.io/otel"
	oteltrace "go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/trace/noop"

	"github.com/github/launch/observability/logger"
)

// tracer ensures that if Instrument was not called, a noop tracer will be available
var tracer = noop.NewTracerProvider().Tracer("noop")

// StartWithName starts a span with the given name
// This can be useful for spans that are not tied to a particular function
// and are instead tied to a particular operation or part of a function
func StartWithName(ctx context.Context, spanName string, opts ...oteltrace.SpanStartOption) (context.Context, oteltrace.Span) {
	return tracer.Start(ctx, spanName, opts...)
}

// Start starts a span with information about the calling function
func Start(ctx context.Context, opts ...oteltrace.SpanStartOption) (context.Context, oteltrace.Span) {
	callingFuncName := operationName(1, "") // 1 means get the call frame of the function that called this one
	return tracer.Start(ctx, callingFuncName, opts...)
}

// StartWithOpFuncName starts a span with information about the calling function, overriding the function name
func StartWithOpFuncName(ctx context.Context, opFuncName string, opts ...oteltrace.SpanStartOption) (context.Context, oteltrace.Span) {
	callingFuncName := operationName(1, opFuncName)
	return tracer.Start(ctx, callingFuncName, opts...)
}

// RecordError records the error in the span and returns the error.
// If the error is nil, this is a no-op.
func RecordError(span oteltrace.Span, err error) error {
	if err != nil {
		span.RecordError(err)
	}
	return err
}

// SetTestTracer sets the tracer variable to the named tracer
// This should only be used in tests, services should use Instrument
func SetTestTracer(tp oteltrace.TracerProvider) {
	tracer = tp.Tracer("test")
	otel.SetTracerProvider(tp)
}

// Instrument creates a telemetry provider and sets the tracer variable to
// the named tracer
func Instrument(ctx context.Context, l logger.Logger, enabled bool) (func(), error) {
	if !enabled {
		// Tracing is disabled, so the tracer is a noop
		return func() {}, nil
	}

	otel.SetErrorHandler(&errorHandler{ctx, l})

	tp, err := trace.NewFromEnv()
	if err != nil {
		return nil, fmt.Errorf("could not start telemetry provider: %w", err)
	}

	tracer = tp.Tracer

	return func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := tp.Provider.Shutdown(ctx); err != nil {
			l.Error(ctx, "error shutting down tracer", kvp.String("exception.message", err.Error()))
		}
	}, nil
}

var _ otel.ErrorHandler = errorHandler{}

type errorHandler struct {
	ctx context.Context
	l   logger.Logger
}

func (eh errorHandler) Handle(err error) {
	if err != nil {
		eh.l.Error(eh.ctx, "encountered a problem during tracing", kvp.String("exception.message", err.Error()))
	}
}
