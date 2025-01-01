package testutils

import (
	"sync"

	"go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"

	"github.com/github/launch/observability/tracing"
)

var mutex sync.Mutex
var testTracer *tracetest.InMemoryExporter

// CollectFinishedSpans resets the mock tracer, runs the target function, and
// then returns the finished spans
func CollectFinishedSpans(fn func()) tracetest.SpanStubs {
	if testTracer == nil {
		panic("Must call EnsureGlobalTracerIsMocked in test's init() before using")
	}

	mutex.Lock()
	defer mutex.Unlock()
	testTracer.Reset()

	fn()

	return testTracer.GetSpans()
}

// CollectFinishedSpanNames resets the mock tracer, runs the target function, and
// then returns the names of all finished spans
func CollectFinishedSpanNames(fn func()) []string {
	return FinishedSpanNames(CollectFinishedSpans(fn))
}

// EnsureGlobalTracerIsMocked replaces the global tracer with a mocked implementation
// and should be called in your test package's init() function.
//
// It must be called in init() because as the tracer is global, we need to no writes to it
// throughout the execution of any of the goroutines spawned in your package's tests. Otherwise we'll have
// concurrency issues when a goroutine starts a span, uses the unsynchronised GetGlobalTracer(),
// and later we write the mock tracer to it.
//
// If your test package doesn't have goroutines beyond the main one, you're fine, but it's safer
// to do in init anyway so it doesn't start flapping if people add some in later.
func EnsureGlobalTracerIsMocked() {
	mutex.Lock()
	defer mutex.Unlock()

	if testTracer == nil {
		testTracer = tracetest.NewInMemoryExporter()
		tp := trace.NewTracerProvider(trace.WithSyncer(testTracer))
		tracing.SetTestTracer(tp)
	}
}

func FinishedSpanNames(spans tracetest.SpanStubs) []string {
	names := make([]string, 0, len(spans))
	for _, s := range spans {
		names = append(names, s.Name)
	}
	return names
}
