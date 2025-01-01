// Package contextlogger is just some syntactic sugar methods that store FieldLoggers in a context.
// We do this because we don't want to have to pass FieldLogger instances around to make sure that information
// like requestID is appropriately logged, or replicate boilerplate field generation in multiple places in code.
// contextlogger should not be opinionated (e.g. it's just a FieldLogger with some helpful methods to add fields).
package contextlogger

import (
	"context"
	"fmt"
	"time"

	"github.com/github/dependency-snapshots-api/internal/util"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"
	oldkvp "github.com/github/go-kvp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
)

type contextLoggerKey struct{}

// ContextWithFields creates a new context that stores additional logging fields in the FieldLogger.
func ContextWithFields(ctx context.Context, fields ...kvp.Field) context.Context {
	// If we find that this creates too long a linked list in context and becomes performance impactful,
	// we should consider storing fields in a thread safe object that we use the pointer of --
	// this would mean that N logging fields would still only need one Context list node.
	return Set(ctx, get(ctx).WithFields(fields...))
}

// Get returns a FieldLogger that has all the fields accrued by the context up until this point.
func Get(ctx context.Context) log.Logger {
	logger := ctx.Value(contextLoggerKey{})
	if logger != nil {
		return logger.(log.Logger).WithFields(commonFields(ctx)...)
	}
	return log.Named("default").WithFields(commonFields(ctx)...)
}

// Debug writes a debug message using the current FieldLogger instance and applies all common fields.
func Debug(ctx context.Context, msg string, fields ...kvp.Field) {
	Get(ctx).Debug(msg, append(fields, commonFields(ctx)...)...)
}

// Warn writes an informational message using the current FieldLogger instance and applies all common fields.
func Warn(ctx context.Context, msg string, fields ...kvp.Field) {
	Get(ctx).Warn(msg, append(fields, commonFields(ctx)...)...)
}

// Info writes an informational message using the current FieldLogger instance and applies all common fields.
func Info(ctx context.Context, msg string, fields ...kvp.Field) {
	Get(ctx).Info(msg, append(fields, commonFields(ctx)...)...)
}

// Error writes an error message using the current FieldLogger instance and applies all common fields.
func Error(ctx context.Context, msg string, fields ...kvp.Field) {
	Get(ctx).Error(msg, append(fields, commonFields(ctx)...)...)
}

// LogStartAndStop both logs an otel span and a "begin" and "ending" message to our logger.
// Ideally, we the part of our app that logs otel spans would convert otel spans to log messages for
//
//	us (since Lightstep samples way too much to be useful), but this is a stopgap.
//
// Make sure to defer the returned function, which will automatically end the span and log completeness for you.
// The span is returned for tagging purposes but *not* expected to be ended or interacted with most of the time.
func LogStartAndStop(ctx context.Context, tracerName string, operationName string, fields ...kvp.Field) (context.Context, func(), trace.Span) {
	ctx, span := otel.Tracer(tracerName).Start(ctx, operationName)
	Info(ctx, fmt.Sprintf("Beginning %v", operationName), fields...)
	startTime := time.Now()
	deferredFunc := func() {
		Info(ctx, fmt.Sprintf("Ending %v", operationName), append(fields, kvp.Int64("timeTakenMS", time.Since(startTime).Milliseconds()))...)
		span.End()
	}

	return ctx, deferredFunc, span
}

// get returns a FieldLogger without common fields. Public interactions with the package should always get common fields, but internal ones
// don't need to duplicate the fields whenever set is called, so this is used.
func get(ctx context.Context) log.Logger {
	logger := ctx.Value(contextLoggerKey{})
	if logger != nil {
		return logger.(log.Logger)
	}
	return log.Named("default")
}

// Set is a function used to update the "current" FieldLogger instance.
// We rely on a field logger instance to store the field slice over time, but this could be easily changed to independent storage.
func Set(ctx context.Context, logger log.Logger) context.Context {
	return context.WithValue(ctx, contextLoggerKey{}, logger)
}

// commonFields retrieves an array of fields that are considered "common" (should be present on every logged message).
// While you can initialize some common fields in the Logger initialization, this is currently the only way to
// add fields in a cross-cutting way that are context dependent.
func commonFields(ctx context.Context) []kvp.Field {
	var fields []kvp.Field
	if requestID := requestid.GetGitHubRequestIDField(ctx); requestID.String != "unknown" {
		otelFields := []oldkvp.Field{oldkvp.String(requestID.Key, requestID.String)}
		fields = append(fields, util.ToOtelKVP(otelFields...)...)
	}
	return fields
}
