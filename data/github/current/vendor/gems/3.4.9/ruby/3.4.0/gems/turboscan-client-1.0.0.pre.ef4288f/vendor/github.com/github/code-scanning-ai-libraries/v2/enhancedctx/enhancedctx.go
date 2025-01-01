// Package enhancedctx defines a structured wrapper around context.WithValue
package enhancedctx

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/trace/noop"
)

type contextKey string

const (
	loggerKey      contextKey = "gh.cs_ai_libs.logger"
	statterKey     contextKey = "gh.cs_ai_libs.statter"
	tracerKey      contextKey = "gh.cs_ai_libs.tracer"
	clientKey      contextKey = "gh.cs_ai_libs.client"
	interactionKey contextKey = "gh.cs_ai_libs.interaction" // Used to store a unique identifier for the interaction
	libraryNameKey contextKey = "gh.cs_ai_libs.library_name"
	intLogCBKey    contextKey = "gh.cs_ai_libs.interaction_log_callbacks"
	requestIDKey   contextKey = "gh.cs_ai_libs.request_id"
)

// LibraryName represents the name of a library using the enhanced context, which is
// used in the keys in metrics and logs.
type LibraryName string

const (
	// LibraryNameAutofix is used for the autofix library
	LibraryNameAutofix LibraryName = "autofix"
	// LibraryNameAutofind is used for the autofind library
	LibraryNameAutofind LibraryName = "autofind"
	// LibraryNameInternal is used for running the CLI in this library
	LibraryNameInternal LibraryName = "internal"
)

const (
	tagKeyClient = "client_name"
	// DefaultClientName is the default client name used when no client name is set.
	DefaultClientName = "no_client_name"
)

// WithRequestID sets the llm/CAPI request id on the context.
func WithRequestID(ctx context.Context, requestID string) context.Context {
	if requestID == "" {
		return ctx
	}
	return context.WithValue(ctx, requestIDKey, requestID)
}

// GetRequestID retrieves the request id from the context.
func GetRequestID(ctx context.Context) string {
	requestID, _ := ctx.Value(requestIDKey).(string)
	return requestID
}

// WithLogger returns a modified version of the provided context, attaching the provided
// logger (and setting the library name).
func WithLogger(ctx context.Context, logger log.Logger, libraryName LibraryName) context.Context {
	ctx = context.WithValue(ctx, libraryNameKey, libraryName)
	return context.WithValue(ctx, loggerKey, logger)
}

// WithLoggerFields returns a modified version of the provided context, attaching the provided
// fields to the active logger in the context (if any).
func WithLoggerFields(ctx context.Context, fields ...kvp.Field) context.Context {
	if logger, ok := ctx.Value(loggerKey).(log.Logger); ok {
		logger = logger.WithFields(fields...)
		return context.WithValue(ctx, loggerKey, logger)
	}
	return ctx
}

// Logger retrieves the logger stored in the context.
// If no logger is found, a null logger is returned.
func Logger(ctx context.Context) log.Logger {
	if loggerFromEnhancedCtx, ok := ctx.Value(loggerKey).(log.Logger); ok {
		libraryName, ok := ctx.Value(libraryNameKey).(LibraryName)
		if !ok {
			// Not possible, since we always set the library-name when setting the logger.
			loggerFromEnhancedCtx.Error("No library name set in context, this should not be possible")
			return loggerFromEnhancedCtx
		}

		clientLoggingKey := fmt.Sprintf("gh.%s.client", string(libraryName))
		interactionLoggingKey := fmt.Sprintf("gh.%s.interaction", string(libraryName))
		requestIDLoggingKey := fmt.Sprintf("gh.%s.github_request_id", string(libraryName))

		fields := make([]kvp.Field, 0, 2)

		interactionIDRaw := ctx.Value(interactionKey)
		if interactionIDRaw != nil {
			interactionID, ok := interactionIDRaw.(string)
			if !ok {
				// Not possible, if we set the interaction ID, it is a string.
				loggerFromEnhancedCtx.Error("Interaction ID is not a string, this should not be possible")
				return loggerFromEnhancedCtx
			}
			fields = append(fields, kvp.String(interactionLoggingKey, interactionID))
		}
		if rid := GetRequestID(ctx); rid != "" {
			fields = append(fields, kvp.String(requestIDLoggingKey, rid))
		}

		fields = append(fields, kvp.String(clientLoggingKey, clientNameOrEmpty(ctx)))
		return loggerFromEnhancedCtx.WithFields(fields...)
	}
	// We should not reach this point, as the logger should always be set in the context.
	return log.NewNullLogger()
}

// WithStatter sets the stats client in the context.
func WithStatter(ctx context.Context, client stats.Client, prefix LibraryName) context.Context {
	// We want a single prefix (autofix/autofind) for all  metrics, so we can have a
	// dashboard covering all clients. Also need to include the client name in the tags
	// so we can filter by client in the dashboard.
	client = client.SetPrefix(string(prefix))
	return context.WithValue(ctx, statterKey, client)
}

// Statter retrieves the stats client stored in the context.
// If no stats client is found, a null stats client is returned.
func Statter(ctx context.Context) stats.Client {
	if statterFromEnhancedCtx, ok := ctx.Value(statterKey).(stats.Client); ok {
		statterFromEnhancedCtx = statterFromEnhancedCtx.WithTags(stats.Tags{tagKeyClient: clientNameOrEmpty(ctx)})
		return statterFromEnhancedCtx
	}
	// We should not reach this point, as the statter should always be set in the context.
	return stats.NullStatter
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
	return Tracer(ctx).Start(ctx, name) //nolint:spancheck // spancheck complains that we don't end the span. It's possible to configure extra functions that creates spans (see https://github.com/jjti/go-spancheck?tab=readme-ov-file#extra-start-span-signatures), but since we don't control the golanci-lint configuration (controlled by github/go-linter action), we can't really do anything about it.
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

// StartInteraction creates a fresh interaction ID, that will be used in all logging, so
// events can be correlated.
func StartInteraction(ctx context.Context) context.Context {
	interactionID := fmt.Sprintf("interaction-%s", uuid.New().String())

	return startInteraction(ctx, interactionID)
}

// Exposed for testing
func startInteraction(ctx context.Context, interactionID string) context.Context {
	return context.WithValue(ctx, interactionKey, interactionID)
}

// GetInteraction retrieves the current interaction ID from the context.
// If no interaction ID is found, it returns an empty string.
func GetInteraction(ctx context.Context) string {
	interactionID, ok := ctx.Value(interactionKey).(string)
	if !ok {
		return ""
	}
	return interactionID
}

// WithClientName returns a modified version of the provided context, attaching the provided client name.
func WithClientName(ctx context.Context, clientName string) context.Context {
	if clientName == "" {
		clientName = DefaultClientName
	}

	return context.WithValue(ctx, clientKey, clientName)
}

// ClientNameFromContext retrieves the client name from the context.
// If no client name is set, it returns a default value.
// The default client name is "no_client_name".
func ClientNameFromContext(ctx context.Context) string {
	return clientNameOrEmpty(ctx)
}

// CheckRequiredClient ensures client name is set and valid
func CheckRequiredClient(ctx context.Context) error {
	name := ClientNameFromContext(ctx)
	if name == DefaultClientName || name == "" {
		return errors.New("client name is required for telemetry")
	}
	return nil
}

func clientNameOrEmpty(ctx context.Context) string {
	if client, ok := ctx.Value(clientKey).(string); ok {
		return client
	}

	return DefaultClientName
}

// WithTelemetryAndNamedLogger initializes telemetry and returns a context with a named logger.
func WithTelemetryAndNamedLogger(ctx context.Context, name LibraryName) (context.Context, error) {
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		return nil, err
	}

	logger := telem.Logger.Named(string(name))
	ctx = WithLogger(ctx, logger, name)

	return ctx, nil
}

// TokenUsage represents the token usage in a model interaction.
type TokenUsage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}

// InteractionLogCallbacks defines the interface for logging interactions with the model.
type InteractionLogCallbacks interface {
	LogToModelInteraction(ctx context.Context, text string)
	LogErrorInteraction(ctx context.Context, text string)
	LogFromModelInteraction(ctx context.Context, text, finishReason string, cached bool, usage TokenUsage, model string)
}

type noopInteractionLogCallbacks struct{}

func (noopInteractionLogCallbacks) LogToModelInteraction(ctx context.Context, text string) {
	// No-op implementation
}

func (noopInteractionLogCallbacks) LogErrorInteraction(ctx context.Context, text string) {
	// No-op implementation
}

func (noopInteractionLogCallbacks) LogFromModelInteraction(ctx context.Context, text, finishReason string, cached bool, usage TokenUsage, model string) {
	// No-op implementation
}

// InteractionLogger retrieves the interaction log callbacks from the context, or returns a noop implementation if not set.
func InteractionLogger(ctx context.Context) InteractionLogCallbacks {
	if cb, ok := ctx.Value(intLogCBKey).(InteractionLogCallbacks); ok {
		return cb
	}
	return noopInteractionLogCallbacks{}
}

// WithInteractionLogger sets the interaction log callbacks in the context.
func WithInteractionLogger(ctx context.Context, cb InteractionLogCallbacks) context.Context {
	return context.WithValue(ctx, intLogCBKey, cb)
}
