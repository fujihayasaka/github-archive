package tracer

import (
	"context"
	"sync"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
)

var (
	globalTracer trace.Tracer
	mu           sync.Mutex
)

func GetTracer() trace.Tracer {
	if globalTracer == nil {
		return otel.Tracer("hosted-compute-ims")
	}

	return globalTracer
}

func SetTracer(baseTracer trace.Tracer) {
	mu.Lock()
	globalTracer = baseTracer
	mu.Unlock()
}

func StartSpan(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	return GetTracer().Start(ctx, spanName, opts...)
}
