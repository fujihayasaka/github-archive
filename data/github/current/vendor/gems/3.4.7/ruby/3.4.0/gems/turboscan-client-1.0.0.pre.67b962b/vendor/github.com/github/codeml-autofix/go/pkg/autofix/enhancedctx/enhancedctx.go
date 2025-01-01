// Package enhancedctx defines a structured wrapper around context.WithValue
package enhancedctx

import (
	"context"
	"os"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/trace/noop"
)

type contextKey string

const (
	// loggerKey is the key used to store a log.Logger in a context.
	// We will use other keys for other context-specific values.
	loggerKey   contextKey = "gh.autofix.logger"
	logLevelKey contextKey = "gh.autofix.log.level"
	statterKey  contextKey = "gh.autofix.statter"
	tracerKey   contextKey = "gh.autofix.tracer"
)

const (
	LogLevelDebug = "debug"
	LogLevelInfo  = "info"
	LogLevelWarn  = "warn"
	LogLevelError = "error"
)

const TelemetryLogsLevelEnvKey = "GITHUB_TELEMETRY_LOGS_LEVEL"

func WithLogger(ctx context.Context, logger log.Logger) context.Context {
	return context.WithValue(ctx, loggerKey, logger)
}

// WithLogLevel sets the log level in the provided context and updates the
// "GITHUB_TELEMETRY_LOGS_LEVEL" environment variable to the specified level.
// This allows the logger to pick up the log level from the environment.
//
// Parameters:
// - ctx: The context to which the log level will be added.
// - level: The log level to set (e.g., "debug", "info", "warn", "error", "fatal").
//
// Returns:
// A new context with the log level set.
func WithLogLevel(ctx context.Context, level string) context.Context {
	// Set the log level in the context
	ctx = context.WithValue(ctx, logLevelKey, level)
	// Also set it in the environment variable for the logger to pick up
	os.Setenv(TelemetryLogsLevelEnvKey, level)
	return ctx
}

func Logger(ctx context.Context) log.Logger {
	if loggerFromEnhancedCtx, ok := ctx.Value(loggerKey).(log.Logger); ok {
		return loggerFromEnhancedCtx
	}
	// We should not reach this point, as the logger should always be set in the context.
	return log.NewNullLogger()
}

func WithStatter(ctx context.Context, client stats.Client) context.Context {
	// We want a single prefix for all autofix metrics, so we can have a
	// dashboard covering all clients.
	client = client.SetPrefix("autofix")
	return context.WithValue(ctx, statterKey, client)
}

func Statter(ctx context.Context) stats.Client {
	if statterFromEnhancedCtx, ok := ctx.Value(statterKey).(stats.Client); ok {
		return statterFromEnhancedCtx
	}
	// We should not reach this point, as the statter should always be set in the context.
	return stats.NullStatter
}

func With(ctx context.Context, fields ...kvp.Field) context.Context {
	return WithLogger(ctx, Logger(ctx).WithFields(fields...))
}

// WithClientName returns a modified version of the provided context, attaching the provided client name.
func WithClientName(ctx context.Context, clientName string) context.Context {
	return With(ctx, kvp.String("gh.autofix.client_name", clientName)) // TODO: define in https://otel.githubapp.com/
}

// WithTracer sets the tracer in the context.
func WithTracer(ctx context.Context, tracer trace.Tracer) context.Context {
	return context.WithValue(ctx, tracerKey, tracer)
}

var noopTracer = noop.NewTracerProvider().Tracer("")

// Tracer retrieves the tracer stored in the context.
// If no tracer is found, a noop tracer is returned.
func Tracer(ctx context.Context) trace.Tracer {
	if tracerFromCtx, ok := ctx.Value(tracerKey).(trace.Tracer); ok {
		return tracerFromCtx
	}
	// Return a no-op tracer
	return noopTracer
}

// StartSpan creates a new span with the given name using either the tracer from
// the context.
func StartSpan(ctx context.Context, name string) (context.Context, trace.Span) {
	return Tracer(ctx).Start(ctx, name)
}

// GetSpan returns the current span from the context
func GetSpan(ctx context.Context) trace.Span {
	return trace.SpanFromContext(ctx)
}

// AddSpanAttributes adds attributes to the current span
func AddSpanAttributes(ctx context.Context, attrs ...attribute.KeyValue) {
	span := GetSpan(ctx)
	if span.IsRecording() {
		span.SetAttributes(attrs...)
	}
}

// AddSpanEvent adds an event to the current span
func AddSpanEvent(ctx context.Context, name string, attrs ...attribute.KeyValue) {
	span := GetSpan(ctx)
	if span.IsRecording() {
		span.AddEvent(name, trace.WithAttributes(attrs...))
	}
}

// SetSpanStatus sets the status of the current span
func SetSpanStatus(ctx context.Context, code codes.Code, description string) {
	span := GetSpan(ctx)
	if span.IsRecording() {
		span.SetStatus(code, description)
	}
}

// RecordSpanError records an error on the current span
func RecordSpanError(ctx context.Context, err error, options ...trace.EventOption) {
	span := GetSpan(ctx)
	if span.IsRecording() && err != nil {
		span.RecordError(err, options...)
		span.SetStatus(codes.Error, err.Error())
	}
}

// Attaches telemetry to a provided context, and saves it to the configuration.
func WithTelemetry(ctx context.Context) (context.Context, error) {
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		return nil, err
	}
	// Named logger; the underlying telemetry provider will choose a colored formatter
	// if the environment indicates a development mode.
	logger := telem.Logger.Named("autofix")
	logger.Info("Service starting", kvp.String("gh.autofix.env", os.Getenv("ENVIRONMENT"))) // TODO: define in https://otel.githubapp.com/

	// Set up the context with logger
	ctx = WithLogger(ctx, logger)

	return ctx, nil
}

func WithTelemetryAndNamedLogger(ctx context.Context, name string) (context.Context, error) {
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		return nil, err
	}

	logger := telem.Logger.Named(name)
	ctx = WithLogger(ctx, logger)

	return ctx, nil
}
