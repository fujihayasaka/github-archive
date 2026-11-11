package log

import "go.opentelemetry.io/otel/sdk/resource"

// These constants come from https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/logs/data-model.md
const (
	OtelFieldBody                 = "Body"
	OtelFieldInstrumentationScope = "InstrumentationScope"
	OtelFieldSeverityText         = "SeverityText"
	OtelFieldTimestamp            = "Timestamp"
	OtelFieldTraceId              = "TraceId" //nolint:revive,stylecheck // Can't change the name of exported fields
	OtelFieldTraceFlags           = "TraceFlags"
	OtelFieldSpanId               = "SpanId" //nolint:revive,stylecheck // Can't change the name of exported fields
)

// openTelemetryMapper takes a zap format message and maps it to OpenTelemetry format.
type openTelemetryMapper struct {
	resources map[string]string
}

func newOpenTelemetryMapper(resources *resource.Resource) *openTelemetryMapper {
	r := make(map[string]string, resources.Len())
	for _, attr := range resources.Attributes() {
		r[string(attr.Key)] = attr.Value.AsString()
	}
	return &openTelemetryMapper{resources: r}
}
