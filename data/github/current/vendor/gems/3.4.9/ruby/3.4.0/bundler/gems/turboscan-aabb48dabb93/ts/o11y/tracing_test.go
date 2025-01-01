package o11y_test

import (
	"bytes"
	"context"
	"io"
	"testing"

	"github.com/github/github-telemetry-go/log"
	ghtrace "github.com/github/github-telemetry-go/trace"
	"github.com/github/turboscan/ts/o11y"
	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/otel"
)

// setupTracer configures the tracer. This is necessary to get correct data into the Spans.
// Returns a buffer that will be used to store the trace for further inspection and a close function
// to be called to flush the trace.
func setupTracer(t *testing.T) (*bytes.Buffer, func(context.Context) error) {
	t.Helper()

	out := new(bytes.Buffer)
	tracer, err := ghtrace.NewFromEnv(
		ghtrace.WithExporterWriter(io.Writer(out)),
		// !!! The exporter must be set to ExporterStdout to get the trace into the buffer !!!
		ghtrace.WithExporter(ghtrace.ExporterStdout),
	)
	require.NoError(t, err)

	// Set the global tracer provider.
	otel.SetTracerProvider(tracer.Provider)

	return out, tracer.Provider.Shutdown
}

func TestNamedSpan(t *testing.T) {
	out, stop := setupTracer(t)

	ctx, span := o11y.NamedSpan(context.Background(), "testName")
	require.True(t, span.IsRecording())
	require.True(t, span.SpanContext().IsValid())

	// Close the Span and the tracer.
	span.End()
	require.NoError(t, stop(ctx))

	// Check that the trace is in the buffer.
	outStr := out.String()
	require.NotEmpty(t, outStr)
	require.Contains(t, outStr, `"Name": "github.com/github/turboscan/ts/o11y"`)
	require.Contains(t, outStr, `"Name": "testName"`)
}

func TestStartSpan_SimpleMethod(t *testing.T) {
	out, stop := setupTracer(t)
	ctx, span := o11y.StartSpan(context.Background())
	span.End()
	require.NoError(t, stop(ctx))

	outStr := out.String()
	require.NotEmpty(t, outStr)
	require.Contains(t, outStr, `"Name": "o11y_test.TestStartSpan_SimpleMethod"`)
}

func TestStartSpan_ReceiverMehod(t *testing.T) {
	out, stop := setupTracer(t)
	ctx := context.Background()

	m := &MyStruct{}
	m.aMethod(ctx)

	require.NoError(t, stop(ctx))

	outStr := out.String()
	require.NotEmpty(t, outStr)
	require.Contains(t, outStr, `"Name": "o11y_test/(*MyStruct).aMethod"`)
}

type MyStruct struct{}

func (m *MyStruct) aMethod(ctx context.Context) {
	_, span := o11y.StartSpan(ctx)
	defer span.End()
}

func TestStartTracing(t *testing.T) {
	// There is always a tracer provider
	oldTP := otel.GetTracerProvider()
	require.NotNil(t, oldTP)

	closeFn := o11y.StartTracing(log.NewNullLogger())

	require.NotNil(t, closeFn)
	closeFn() // should not panic

	// After this operation the global tracer provider should be set
	require.NotNil(t, otel.GetTracerProvider())
	require.NotEqual(t, oldTP, otel.GetTracerProvider())
}
