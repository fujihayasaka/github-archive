// Package tracing implements a global tracer.
package tracing

import (
	"context"
	"runtime"
	"strings"
	"sync"

	"github.com/github/github-telemetry-go/log"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
)

var (
	globalTracer        trace.Tracer
	globalTraceProvider trace.TracerProvider
	mu                  sync.RWMutex
)

// ErrorHandler is a handle to an error
type ErrorHandler struct {
	l log.Logger
}

// NewErrorHandler creates a new error handler
func NewErrorHandler(logger log.Logger) *ErrorHandler {
	return &ErrorHandler{l: logger}
}

// Handle logs tracing errors
func (h *ErrorHandler) Handle(err error) {
	if err != nil {
		h.l.WithError(err).Error("encountered a problem during tracing")
	}
}

// Tracer returns the current set otel tracer
func Tracer() trace.Tracer {
	if globalTracer == nil {
		globalTracer = otel.Tracer("notifyd")
	}
	return globalTracer
}

// SetTracer sets the global tracer
func SetTracer(tracer trace.Tracer) {
	mu.Lock()
	globalTracer = tracer
	mu.Unlock()
}

// Provider returns the current set otel tracer provider
func Provider() trace.TracerProvider {
	if globalTraceProvider == nil {
		globalTraceProvider = otel.GetTracerProvider()
	}
	return globalTraceProvider
}

// SetProvider sets the global tracer provider
func SetProvider(provider trace.TracerProvider) {
	mu.Lock()
	globalTraceProvider = provider
	mu.Unlock()
}

// StartSpan starts a new span with the given name and options
func StartSpan(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	return Tracer().Start(ctx, spanName, opts...) //nolint:spancheck // span is assigned in calling function
}

// StartSpanWithCaller starts a new span with name of the caller and options
func StartSpanWithCaller(ctx context.Context, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	// caller name skips 2, so we get this function's caller
	return Tracer().Start(ctx, callerName(2, false), opts...) //nolint:spancheck // span is assigned in calling function
}

// CallerName gets the name of the func caller
// skip is the number of stack frames to ascend
func callerName(skip int, methodOnly bool) string {
	pc, _, _, ok := runtime.Caller(skip)
	if !ok {
		return ""
	}

	details := runtime.FuncForPC(pc)
	if details == nil {
		return ""
	}

	// ie: github.com/github/actions-results/internal/somepkg.FuncName
	fullFunc := details.Name()

	// only grab after last `/`
	// ie: somepkg.FuncName
	caller := fullFunc[strings.LastIndex(fullFunc, "/")+1:]

	// only last part of the function name
	// ie: FuncName
	if methodOnly {
		caller = caller[strings.LastIndex(caller, ".")+1:]
	}

	return caller
}
