package cacheobs

import (
	"context"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/cache"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/cache/cachetest"
)

const (
	KiB = 1 << 10
	MiB = 1 << 20
)

func TestWithExpiry(t *testing.T) {
	cachetest.TestWithExpiry(t, func(t *testing.T) cache.ExpiringCache {
		local := cachemem.NewExpiringCache(10 * MiB)
		return Observe(local, "test", observability.NewNullObservability())
	})
}

func TestObserves(t *testing.T) {
	tests := []struct {
		name  string
		check func(t *testing.T, ctx context.Context)
	}{
		{
			name: "collects traces",
			check: func(t *testing.T, ctx context.Context) {

				exporter := tracetest.NewInMemoryExporter()
				tp := trace.NewTracerProvider(trace.WithSyncer(exporter))
				tracing.SetTestTracer(tp)

				wantTag := kvp.String("hello", "world")
				wantAttribute := kvp.AttributeMapper(kvp.String("hello", "world"))

				obs := observability.NewTestObservability()
				local := cachemem.NewExpiringCache(1 * KiB)
				cache := Observe(local, "test", obs, WithTraceTags(wantTag))

				now := time.Now()
				wantKey := "hello"
				wantValue := []byte("world")
				expiresIn := time.Second

				err := cache.Set(ctx, wantKey, wantValue, now, expiresIn)
				require.NoError(t, err)

				got, ok, err := cache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.True(t, ok)
				require.Equal(t, wantValue, got.Value)

				spans := exporter.GetSpans()
				require.Len(t, spans, 2)
				setSpan := spans[0]
				require.Contains(t, setSpan.Name, "cacheobs/(*cacheObs).Set")
				require.Contains(t, setSpan.Attributes, wantAttribute)

				getSpan := spans[1]
				require.Contains(t, getSpan.Name, "cacheobs/(*cacheObs).Get")
				require.Contains(t, setSpan.Attributes, wantAttribute)
			},
		},
	}
	ctx := context.Background()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Helper()
			tt.check(t, ctx)
		})
	}
}
