package telemetry

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/sdk/trace"
)

type contextFieldsType struct{}

var contextFieldsKey contextFieldsType

// Takes a subset of fields from the logging context and adds them as trace attributes.
type LoggingContextSpanProcessor struct {
	fieldKeys map[string]bool
}

func NewLoggingContextSpanProcessor(cfg *config.TelemetryConfig) LoggingContextSpanProcessor {
	fieldKeysToTrace := GetTracingKeys(cfg.Environment)
	fieldKeys := map[string]bool{}
	for _, key := range fieldKeysToTrace {
		fieldKeys[key] = true
	}

	return LoggingContextSpanProcessor{
		fieldKeys: fieldKeys,
	}
}

func (p LoggingContextSpanProcessor) OnStart(ctx context.Context, s trace.ReadWriteSpan) {
	fields, ok := ctx.Value(contextFieldsKey).([]kvp.Field)
	if !ok {
		return
	}

	// only add trace attributes that are in the list of fields to trace, since tracing PII requirements are more strict than logging
	attributes := []attribute.KeyValue{}
	for _, field := range fields {
		if _, ok := p.fieldKeys[field.Key]; ok {
			attributes = append(attributes, kvp.AttributeMapper(field))
		}
	}

	s.SetAttributes(attributes...)
}

func (p LoggingContextSpanProcessor) OnEnd(s trace.ReadOnlySpan)           {}
func (p LoggingContextSpanProcessor) Shutdown(ctx context.Context) error   { return nil }
func (p LoggingContextSpanProcessor) ForceFlush(ctx context.Context) error { return nil }

func GetTracingKeys(env config.Environment) []string {
	fields := []string{
		requestid.GitHubRequestIDLabel,
		log.OtelFieldTraceId,
		log.OtelFieldSpanId,
		HttpStatusKey,
		HttpMethodKey,
		HttpStatusTextKey,
	}
	return fields
}

type Context struct {
	context.Context
	Fields []kvp.Field
}

func AddLoggingFields(ctx context.Context, fields ...kvp.Field) context.Context {
	if lc, ok := ctx.Value(contextFieldsKey).([]kvp.Field); ok {
		fields = append(fields, lc...)
	}
	return context.WithValue(ctx, contextFieldsKey, fields)
}

func FieldsFromContext(ctx context.Context) ([]kvp.Field, bool) {
	fields, ok := ctx.Value(contextFieldsKey).([]kvp.Field)
	return fields, ok
}
