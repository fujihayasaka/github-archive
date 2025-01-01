// Package enhancedctx defines a structured wrapper around context.WithValue
package enhancedctx

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"

	shared_enhancedctx "github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
)

type contextKey string

const (
	logLevelKey        contextKey = "gh.autofix.log.level"
	logInteractionsKey contextKey = "gh.autofix.log.interactions"
)

// LogLevel is the log level used in the context.
const (
	LogLevelDebug = "debug"
	LogLevelInfo  = "info"
	LogLevelWarn  = "warn"
	LogLevelError = "error"
)

// DefaultClientName is the default client name used when no client name is set.
const DefaultClientName = shared_enhancedctx.DefaultClientName

// TelemetryLogsLevelEnvKey is the environment variable used to set the log level for telemetry.
const TelemetryLogsLevelEnvKey = "GITHUB_TELEMETRY_LOGS_LEVEL"

// WithLogger returns a modified version of the provided context, attaching the provided
func WithLogger(ctx context.Context, logger log.Logger) context.Context {
	return shared_enhancedctx.WithLogger(ctx, logger, shared_enhancedctx.LibraryNameAutofix)
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

// Logger retrieves the logger from the context.
func Logger(ctx context.Context) log.Logger {
	return shared_enhancedctx.Logger(ctx)
}

// WithStatter sets the stats client in the context.
func WithStatter(ctx context.Context, client stats.Client) context.Context {
	return shared_enhancedctx.WithStatter(ctx, client, shared_enhancedctx.LibraryNameAutofix)
}

// Statter retrieves the stats client from the context.
func Statter(ctx context.Context) stats.Client {
	return shared_enhancedctx.Statter(ctx)
}

// With adds fields to the logger in the context.
func With(ctx context.Context, fields ...kvp.Field) context.Context {
	return shared_enhancedctx.WithLoggerFields(ctx, fields...)
}

// WithClientName returns a modified version of the provided context, attaching the provided client name.
func WithClientName(ctx context.Context, clientName string) context.Context {
	return shared_enhancedctx.WithClientName(ctx, clientName)
}

// WithTracer sets the tracer in the context.
func WithTracer(ctx context.Context, tracer trace.Tracer) context.Context {
	return shared_enhancedctx.WithTracer(ctx, tracer)
}

// Tracer retrieves the tracer stored in the context.
// If no tracer is found, a noop tracer is returned.
func Tracer(ctx context.Context) trace.Tracer {
	return shared_enhancedctx.Tracer(ctx)
}

// StartSpan creates a new span with the given name using either the tracer from
// the context.
func StartSpan(ctx context.Context, name string) (context.Context, trace.Span) {
	return shared_enhancedctx.StartSpan(ctx, name)
}

// GetSpan returns the current span from the context
func GetSpan(ctx context.Context) trace.Span {
	return shared_enhancedctx.GetSpan(ctx)
}

// AddSpanAttributes adds attributes to the current span
func AddSpanAttributes(ctx context.Context, attrs ...attribute.KeyValue) {
	shared_enhancedctx.AddSpanAttributes(ctx, attrs...)
}

// AddSpanEvent adds an event to the current span
func AddSpanEvent(ctx context.Context, name string, attrs ...attribute.KeyValue) {
	shared_enhancedctx.AddSpanEvent(ctx, name, attrs...)
}

// SetSpanStatus sets the status of the current span
func SetSpanStatus(ctx context.Context, code codes.Code, description string) {
	shared_enhancedctx.SetSpanStatus(ctx, code, description)
}

// RecordSpanError records an error on the current span
func RecordSpanError(ctx context.Context, err error, options ...trace.EventOption) {
	shared_enhancedctx.RecordSpanError(ctx, err, options...)
}

// WithTelemetry Attaches telemetry to a provided context, and saves it to the configuration.
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

// WithTelemetryAndNamedLogger attaches telemetry to the context and sets a named logger.
func WithTelemetryAndNamedLogger(ctx context.Context, name string) (context.Context, error) {
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		return nil, err
	}

	logger := telem.Logger.Named(name)
	ctx = WithLogger(ctx, logger)

	return ctx, nil
}

// StartInteraction starts a new interaction in the context.
func StartInteraction(ctx context.Context) context.Context {
	// Log the start of the interaction
	return shared_enhancedctx.StartInteraction(ctx)
}

// ClientNameFromContext retrieves the client name from the context.
// If no client name is set, it returns a default value.
// The default client name is "no_client_name".
func ClientNameFromContext(ctx context.Context) string {
	return shared_enhancedctx.ClientNameFromContext(ctx)
}

// CheckRequiredClient ensures client name is set and valid
func CheckRequiredClient(ctx context.Context) error {
	return shared_enhancedctx.CheckRequiredClient(ctx)
}

type toModelInteraction struct {
	InteractionID string `json:"interactionId"`
	Kind          string `json:"kind"`
	ToModel       string `json:"toModel"`
	Timestamp     int64  `json:"timestamp"`
}

type errorInteraction struct {
	InteractionID string `json:"interactionId"`
	Kind          string `json:"kind"`
	ErrorMessage  string `json:"error"`
	Timestamp     int64  `json:"timestamp"`
}

type fromModelInteraction struct {
	InteractionID string                        `json:"interactionId"`
	Kind          string                        `json:"kind"`
	FromModel     string                        `json:"fromModel"`
	FinishReason  string                        `json:"finish_reason"`
	Cached        bool                          `json:"cached"`
	Usage         shared_enhancedctx.TokenUsage `json:"usage"`
	Model         string                        `json:"model,omitempty"`
	Timestamp     int64                         `json:"timestamp"`
}

// LogToModelInteraction logs the request to the model to the model interaction log file.
func LogToModelInteraction(ctx context.Context, text string) {
	if logFile, ok := getLogInteractionsFile(ctx); ok {
		interactionID := shared_enhancedctx.GetInteraction(ctx)

		// Log the message to the model interaction
		toModel := toModelInteraction{
			InteractionID: interactionID,
			Kind:          "toModel",
			ToModel:       text,
			Timestamp:     time.Now().UnixMilli(),
		}
		writeValueToLogFile(logFile, toModel)
	}
}

// LogErrorInteraction logs an error interaction to the model interaction log file.
func LogErrorInteraction(ctx context.Context, text string) {
	if logFile, ok := getLogInteractionsFile(ctx); ok {
		interactionID := shared_enhancedctx.GetInteraction(ctx)
		// Log the message to the model interaction
		errorInteraction := errorInteraction{
			InteractionID: interactionID,
			Kind:          "error",
			ErrorMessage:  text,
			Timestamp:     time.Now().UnixMilli(),
		}

		writeValueToLogFile(logFile, errorInteraction)
	}
}

// LogFromModelInteraction logs the response from the model to the model interaction log file.
func LogFromModelInteraction(ctx context.Context, text, finishReason string, cached bool, usage shared_enhancedctx.TokenUsage, model string) {
	if logFile, ok := getLogInteractionsFile(ctx); ok {
		// Log the message to the model interaction
		interactionID := shared_enhancedctx.GetInteraction(ctx)
		fromModel := fromModelInteraction{
			InteractionID: interactionID,
			Kind:          "fromModel",
			FromModel:     text,
			FinishReason:  finishReason,
			Cached:        cached,
			Usage:         usage,
			Model:         model,
			Timestamp:     0,
		}
		writeValueToLogFile(logFile, fromModel)
	}
}

// SetLogInteractionsFile sets the log interactions file in the context.
// This file will be used to log interactions with the model.
// If this function is not called, no interactions will be logged.
func SetLogInteractionsFile(ctx context.Context, fileName string) context.Context {
	ctx = context.WithValue(ctx, logInteractionsKey, fileName)
	return ctx
}

func getLogInteractionsFile(ctx context.Context) (string, bool) {
	if v, ok := ctx.Value(logInteractionsKey).(string); ok {
		return v, true
	}
	return "", false
}

func writeValueToLogFile(logFile string, value interface{}) {
	// Open the log file in append mode and write the interaction as JSON
	file, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		panic(fmt.Sprintf("failed to open log interactions file: %v", err))
	}
	defer func() {
		// ensure we catch any error flushing buffered writes
		if err := file.Close(); err != nil {
			panic(fmt.Sprintf("failed to close log interactions file: %v", err))
		}
	}()

	jsonValue, err := json.Marshal(value)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal value to JSON: %v", err))
	}

	if _, err := fmt.Fprintf(file, "%s\n", jsonValue); err != nil {
		panic(fmt.Sprintf("failed to write to log interactions file: %v", err))
	}
}
