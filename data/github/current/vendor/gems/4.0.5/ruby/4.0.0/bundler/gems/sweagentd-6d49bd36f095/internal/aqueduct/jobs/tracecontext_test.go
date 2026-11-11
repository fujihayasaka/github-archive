package jobs

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

func TestInjectTraceContext(t *testing.T) {
	t.Run("injects traceparent when span is active", func(t *testing.T) {
		tp := sdktrace.NewTracerProvider()
		tracer := tp.Tracer("test")
		ctx, span := tracer.Start(context.Background(), "test-span")
		defer span.End()

		headers := make(map[string]string)
		InjectTraceContext(ctx, headers)

		traceparent, ok := headers["traceparent"]
		require.True(t, ok, "traceparent header should be set")
		require.NotEmpty(t, traceparent)

		// W3C traceparent format: version-traceid-parentid-flags
		require.Regexp(t, `^[0-9a-f]{2}-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$`, traceparent)
	})

	t.Run("no-op when no span in context", func(t *testing.T) {
		headers := make(map[string]string)
		InjectTraceContext(context.Background(), headers)

		_, ok := headers["traceparent"]
		require.False(t, ok, "traceparent header should not be set without an active span")
	})
}

func TestExtractTraceContext(t *testing.T) {
	t.Run("extracts traceparent from headers", func(t *testing.T) {
		traceparent := "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
		headers := map[string]string{
			"traceparent": traceparent,
		}

		ctx := ExtractTraceContext(context.Background(), headers)

		spanCtx := trace.SpanContextFromContext(ctx)
		require.True(t, spanCtx.IsValid(), "span context should be valid after extraction")
		require.True(t, spanCtx.IsRemote(), "span context should be marked as remote")
		require.Equal(t, "4bf92f3577b34da6a3ce929d0e0e4736", spanCtx.TraceID().String())
		require.Equal(t, "00f067aa0ba902b7", spanCtx.SpanID().String())
	})

	t.Run("returns original context when no traceparent header", func(t *testing.T) {
		headers := map[string]string{}

		ctx := ExtractTraceContext(context.Background(), headers)

		spanCtx := trace.SpanContextFromContext(ctx)
		require.False(t, spanCtx.IsValid(), "span context should not be valid without traceparent")
	})

	t.Run("returns original context for invalid traceparent", func(t *testing.T) {
		headers := map[string]string{
			"traceparent": "invalid-traceparent-value",
		}

		ctx := ExtractTraceContext(context.Background(), headers)

		spanCtx := trace.SpanContextFromContext(ctx)
		require.False(t, spanCtx.IsValid(), "span context should not be valid with invalid traceparent")
	})
}

func TestTraceContextRoundTrip(t *testing.T) {
	t.Run("inject then extract preserves trace ID", func(t *testing.T) {
		tp := sdktrace.NewTracerProvider()
		tracer := tp.Tracer("test")
		ctx, span := tracer.Start(context.Background(), "test-span")
		defer span.End()

		originalTraceID := span.SpanContext().TraceID()
		originalSpanID := span.SpanContext().SpanID()

		// Inject
		headers := make(map[string]string)
		InjectTraceContext(ctx, headers)

		// Extract into a fresh context
		newCtx := ExtractTraceContext(context.Background(), headers)

		extractedSpanCtx := trace.SpanContextFromContext(newCtx)
		require.True(t, extractedSpanCtx.IsValid())
		require.True(t, extractedSpanCtx.IsRemote())
		require.Equal(t, originalTraceID, extractedSpanCtx.TraceID(), "trace ID should be preserved")
		require.Equal(t, originalSpanID, extractedSpanCtx.SpanID(), "parent span ID should be preserved")
	})

	t.Run("inject then extract preserves tracestate", func(t *testing.T) {
		traceparent := "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
		tracestate := "congo=t61rcWkgMzE"
		sourceHeaders := map[string]string{
			"traceparent": traceparent,
			"tracestate":  tracestate,
		}

		// Extract from source
		ctx := ExtractTraceContext(context.Background(), sourceHeaders)

		// Re-inject into new headers
		destHeaders := make(map[string]string)
		InjectTraceContext(ctx, destHeaders)

		require.Contains(t, destHeaders, "traceparent")
		require.Contains(t, destHeaders, "tracestate")
		require.Equal(t, tracestate, destHeaders["tracestate"])
	})
}
