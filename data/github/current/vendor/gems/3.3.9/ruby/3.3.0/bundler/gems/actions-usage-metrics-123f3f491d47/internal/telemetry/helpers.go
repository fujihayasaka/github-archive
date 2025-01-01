package telemetry

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
)

func Trace(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	ctx, span := otel.Tracer("go.opentelemetry.io").Start(ctx, spanName, append(opts, trace.WithSpanKind(trace.SpanKindServer))...)
	ctx = AddLoggingFields(ctx,
		kvp.String(requestid.GitHubRequestIDLabel, requestid.GetGitHubRequestID(ctx)),
		kvp.String(log.OtelFieldTraceId, span.SpanContext().TraceID().String()),
		kvp.String(log.OtelFieldSpanId, span.SpanContext().SpanID().String()),
	)
	return ctx, span
}

func GetNullTelemetry() *Telemetry {
	logger, _ := NewLogger(log.NewNullLogger(), nil)
	telem := &Telemetry{
		Logger: logger,
		Stats:  &stats.NullClient{},
	}
	return telem
}
