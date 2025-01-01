package tracing

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"

	"github.com/github/github-telemetry-go/trace"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/trace/noop"
)

// heavily based on https://github.com/github/issues-graph/blob/3b44384fb7fbb099e6d62de4cd3a59d6a40f2aec/lib/tracing/tracing.go

// tracer ensures that if Instrument was not called, a noop tracer will be available
var tracer = noop.NewTracerProvider().Tracer("")

func ChildSpan(ctx context.Context, spanName string, opts ...oteltrace.SpanStartOption) (context.Context, oteltrace.Span) {
	// apply default attributes first
	ctx, span := tracer.Start(ctx, spanName, opts...)

	if requestId := requestid.GetGitHubRequestID(ctx); requestId != "" {
		span.SetAttributes(attribute.String("gh.request_id", requestId))
	}
	return ctx, span
}

// Instrument creates a telemetry provider and sets the tracer variable to
// the named tracer
func Instrument(l log.Logger) (func(), error) {
	otel.SetErrorHandler(&errorHandler{l})
	tp, err := trace.NewFromEnv()
	if err != nil {
		return nil, err
	}
	tracer = tp.Tracer
	otel.SetTracerProvider(tp.Provider)

	return func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := tp.Provider.Shutdown(ctx); err != nil {
			l.WithError(err).Error("error shutting down tracer")
		}
	}, nil
}

type errorHandler struct {
	l log.Logger
}

func (eh errorHandler) Handle(err error) {
	if err != nil {
		eh.l.WithError(err).Error("encountered a problem during tracing")
	}
}
