// Package internal contains the internal interfaces that are shared within Vexi. This avoids having to re-create the same interfaces in multiple packages where they are needed.
package internal

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

// Telemetry defines the interface for telemetry operations.
type Telemetry interface { //nolint:interfacebloat // this interface is for a wrapper that standardizes logs, metrics and tracing.
	GetStatsClient() stats.Client
	GetLogger() log.Logger

	// AddFields adds fields that will be added to all log messages. This is not thread safe, so it should be called in constructors before any logs are emitted.
	AddFields(fields ...zap.Field)

	// AddTags adds tags that will be added to all metrics. This is not thread safe, so it should be called in constructors before any metrics are emitted.
	AddTags(tags stats.Tags)

	LogDebug(ctx context.Context, msg string, fields ...zap.Field)
	LogInfo(ctx context.Context, msg string, fields ...zap.Field)
	LogWarn(ctx context.Context, msg string, fields ...zap.Field)
	LogWithError(ctx context.Context, err error, msg string, fields ...zap.Field)
	LogError(ctx context.Context, msg string, fields ...zap.Field)
	StartTrace(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span)

	// See https://docs.datadoghq.com/metrics/types/?tab=gauge#metric-types
	MetricGauge(ctx context.Context, key string, tags stats.Tags, value int64)

	// See https://docs.datadoghq.com/metrics/types/?tab=count#metric-types
	MetricCounter(ctx context.Context, key string, tags stats.Tags, value int64)

	// See https://docs.datadoghq.com/metrics/types/?tab=distribution#metric-types
	MetricDistribution(ctx context.Context, key string, tags stats.Tags, value float64)

	// See https://docs.datadoghq.com/metrics/types/?tab=distribution#metric-types. Specifically for duration metrics
	MetricDistributionMs(ctx context.Context, key string, tags stats.Tags, value time.Duration)
}
