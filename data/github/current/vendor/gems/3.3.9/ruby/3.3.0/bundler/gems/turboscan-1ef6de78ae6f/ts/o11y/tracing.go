package o11y

import (
	"context"
	"time"

	ghtrace "github.com/github/github-telemetry-go/trace"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// tracerName is the name we consistently use to identify the tracer
// created for manual instrumentation within Turboscan.
const tracerName = "github.com/github/turboscan/ts/o11y"

// StartTracing initializes an OpenTelemetry tracer and sets the GlobalTracerProvider.
// It returns a close function that needs to be called to ensure the flushing of
// all the spans.
func StartTracing(logger log.Logger) func() {
	tp, closeFn, err := newTracerProvider(logger)
	if err != nil {
		logger.Error("error starting tracer", kvp.String("err", err.Error()))
		return func() {}
	}

	otel.SetTracerProvider(tp)
	return closeFn
}

// Tracer returns a tracer to be used for manual instrumentation.
func Tracer() trace.Tracer {
	// We define a global tracer. Since these methods are meant to be used in manual instrumentation
	// we use a custom name for the tracer.
	return otel.GetTracerProvider().Tracer(tracerName)

}

// NamedSpan returns a new span with the given name and options.
// See StartSpan for a simpler way to add manual instrumentation.
func NamedSpan(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	ctx, span := Tracer().Start(ctx, spanName, opts...)
	setSpanNameAndAttributesFromCaller(span, spanName, 1)
	return ctx, span
}

// StartSpan returns a new span with the name auto-generated from the calling function name.
func StartSpan(ctx context.Context, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	ctx, span := Tracer().Start(ctx, "", opts...)
	setSpanNameAndAttributesFromCaller(span, "", 1)
	return ctx, span
}

// RecordError records the error in the span and returns the error.
// If the error is nil, this is a no-op.
func RecordError(span trace.Span, err error) error {
	if err != nil {
		span.RecordError(err)
	}
	return err
}

type RepoIDProvider interface {
	GetRepositoryId() uint64
}

// WithRepoIDFromRequest returns an option attribute to include the repository ID from to the span.
// This is useful for TWIRP requests since we typically want to at least log the repository ID.
func WithRepoIDFromRequest(r RepoIDProvider) trace.SpanStartOption {
	return trace.WithAttributes(attribute.Int("gh.repo.id", int(r.GetRepositoryId())))
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
			logger.WithError(err).Error("error shutting down tracer")
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
