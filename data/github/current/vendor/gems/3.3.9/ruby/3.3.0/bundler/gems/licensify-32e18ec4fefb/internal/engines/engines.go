package engines

import (
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

func recordError(err error, span trace.Span) {
	span.RecordError(err)
	span.SetStatus(codes.Error, err.Error())
}
