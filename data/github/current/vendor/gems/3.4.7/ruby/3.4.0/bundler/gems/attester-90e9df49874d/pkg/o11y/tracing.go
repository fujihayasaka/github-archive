package o11y

// ref: https://github.com/github/turboscan/blob/main/ts/o11y/tracing.go
// ref: https://github.com/github/github-telemetry-go

import (
	"context"
	"time"

	ghtrace "github.com/github/github-telemetry-go/trace"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
)

// tracerName is the name we consistently use to identify the tracer
// created for manual instrumentation within Turboscan.
const tracerName = "github.com/github/attester/o11y"

// StartTracing initializes an OpenTelemetry tracer and sets the GlobalTracerProvider.
// It returns a close function that needs to be called to ensure the flushing of
// all the spans.
func StartTracing(logger log.Logger) (func(), error) {
	tp, closeFn, err := newTracerProvider(logger)
	if err != nil {
		logger.Error("error starting tracer", kvp.String("err", err.Error()))
		return func() {}, err
	}

	logger.Log(log.InfoLevel, "started tracer")

	otel.SetTracerProvider(tp)
	return closeFn, nil
}

// Tracer returns a tracer to be used for manual instrumentation.
func Tracer() trace.Tracer {
	// We define a global tracer. Since these methods are meant to be used in manual instrumentation
	// we use a custom name for the tracer.
	return otel.Tracer(tracerName)
}

// NamedSpan returns a new span with the given name and options.
// See StartSpan for a simpler way to add manual instrumentation.
func NamedSpan(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	ctx, span := Tracer().Start(ctx, spanName, opts...)
	return ctx, span
}

// newTracerProvider returns an OpenTelemetry tracer provider and a close function.
// The TracerProvider can be used to obtain a tracer.
func newTracerProvider(logger log.Logger) (trace.TracerProvider, func(), error) {
	otel.SetErrorHandler(&errorHandler{logger})

	tp, err := ghtrace.NewFromEnv()
	if err != nil {
		return nil, nil, errors.Wrap(err, "could not start telemetry provider")
	}

	return tp.Provider, func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := tp.Provider.Shutdown(ctx); err != nil {
			logger.Fatal("error shutting down tracer", kvp.String("err", err.Error()))
		}
	}, nil
}

type errorHandler struct {
	l log.Logger
}

func (eh errorHandler) Handle(err error) {
	if err != nil {
		eh.l.Error("encountered a problem during tracing", kvp.String("err", err.Error()))
	}
}
