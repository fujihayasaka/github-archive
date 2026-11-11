// Package telemetry provides an interface to the go structured logging library used by GitHub.
package telemetry

import (
	"context"
	"time"

	"github.com/github/feature-management-client-go/vexi/v2/version"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

const (
	// Environment is the stats tag name for environment.
	Environment = "moda_environment"
	// PodName is the stats tag name for the pod name.
	PodName         = "pod_name"
	errorCodeTag    = "error_code"
	subErrorCodeTag = "cause_error_code" // represents the error code of the inner most error, if one exists.
	errorMetricName = "service_error"
	operationKey    = "operation"
	timeElapsed     = "time_elapsed"
	tenantID        = "tenant_id"
)

// Tracer is the interface used by vexi for creating spans for enabled checks.
type Tracer interface {
	// Start creates a span and a context.Context containing the newly-created span.
	//
	// If the context.Context provided in `ctx` contains a Span then the newly-created
	// Span will be a child of that span, otherwise it will be a root span. This behavior
	// can be overridden by providing `WithNewRoot()` as a SpanOption, causing the
	// newly-created Span to be a root span even if `ctx` contains a Span.
	//
	// When creating a Span it is recommended to provide all known span attributes using
	// the `WithAttributes()` SpanOption as samplers will only have access to the
	// attributes provided when a Span is created.
	//
	// Any Span that is created MUST also be ended. This is the responsibility of the user.
	// Implementations of this API may leak memory or other resources if Spans are not ended.
	Start(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span)
}

// StandardTelemetry is a wrapper around the go structured logging library used by GitHub.
type StandardTelemetry struct {
	logger log.Logger
	tracer Tracer
	statsd stats.Client
}

// NewStandardTelemetry returns a new instance of the vexiy Telemetry wrapper.
func NewStandardTelemetry(logger log.Logger, tracer Tracer, statsClient stats.Client) *StandardTelemetry {
	telem := &StandardTelemetry{
		logger: logger,
		tracer: tracer,
		statsd: statsClient,
	}

	// TODO: When telem becomes a separate library, the consumer will need to add these
	// Identify vexi version in all metrics and logs
	telem.AddFields(zap.String(VexiVersionFieldName, version.Version))
	telem.AddTags(stats.Tags{VexiVersionTagName: version.Version})

	// Identify vexi distribution in all metrics and logs
	telem.AddFields(zap.String(ClientNameFieldName, "vexi-go"))
	telem.AddTags(stats.Tags{ClientNameTag: "vexi-go"})

	// set the prefix to an empty string to avoid adding the calling service name to all metrics
	telem.statsd = telem.statsd.SetPrefix("")
	return telem
}

// Tracer returns the instance of the tracer used in the wrapper.
func (t *StandardTelemetry) Tracer(name string, options ...trace.TracerOption) Tracer {
	return t.tracer
}

// LogDebug logs a debug message.
func (t *StandardTelemetry) LogDebug(ctx context.Context, msg string, fields ...zap.Field) {
	t.logger.WithContext(ctx).WithFields(fields...).Debug(msg)
}

// LogInfo logs an info message.
func (t *StandardTelemetry) LogInfo(ctx context.Context, msg string, fields ...zap.Field) {
	t.logger.WithContext(ctx).WithFields(fields...).Info(msg)
}

// LogWarn logs a warning message.
func (t *StandardTelemetry) LogWarn(ctx context.Context, msg string, fields ...zap.Field) {
	t.logger.WithContext(ctx).WithFields(fields...).Warn(msg)
}

// LogWithError logs an error message.
func (t *StandardTelemetry) LogWithError(ctx context.Context, err error, msg string, fields ...zap.Field) {
	t.logger.WithContext(ctx).WithFields(fields...).WithError(err).Error(msg)
}

// LogError logs an error message.
func (t *StandardTelemetry) LogError(ctx context.Context, msg string, fields ...zap.Field) {
	t.logger.WithContext(ctx).WithFields(fields...).Error(msg)
}

// StartTrace starts a new open telemetry trace. If a parent span is present in the context, it will be used as the parent of the new span.
func (t *StandardTelemetry) StartTrace(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	return t.tracer.Start(ctx, spanName, opts...) //nolint:spancheck // This is a wrapper around the opentelemetry Start method. Callers are expected to end the span.
}

// MetricGauge records gauage metrics: See https://docs.datadoghq.com/metrics/types/?tab=gauge#metric-types.
func (t *StandardTelemetry) MetricGauge(ctx context.Context, key string, tags stats.Tags, value int64) {
	t.statsd.Gauge(key, tags, value)
}

// MetricCounter records count metrics: See https://docs.datadoghq.com/metrics/types/?tab=count#metric-types.
func (t *StandardTelemetry) MetricCounter(ctx context.Context, key string, tags stats.Tags, value int64) {
	t.statsd.Counter(key, tags, value)
}

// MetricDistributionMs records duration metrics: See https://docs.datadoghq.com/metrics/types/?tab=distribution#metric-types.
func (t *StandardTelemetry) MetricDistributionMs(ctx context.Context, key string, tags stats.Tags, value time.Duration) {
	t.statsd.DistributionMs(key, tags, value)
}

// MetricDistribution records distribution metrics. See https://docs.datadoghq.com/metrics/types/?tab=distribution#metric-types.
func (t *StandardTelemetry) MetricDistribution(ctx context.Context, key string, tags stats.Tags, value float64) {
	t.statsd.Distribution(key, tags, value)
}

// AddTags adds tags that will be added to all metrics. This is not thread safe, so it should be called in constructors before any metrics are emitted.
func (t *StandardTelemetry) AddTags(tags stats.Tags) {
	t.statsd = t.statsd.WithTags(tags)
}

// AddFields adds fields that will be added to all log messages. This is not thread safe, so it should be called in constructors before any log messages are emitted.
func (t *StandardTelemetry) AddFields(fields ...zap.Field) {
	t.logger = t.logger.WithFields(fields...)
}

// NewTimer returns a function that will track and return the duration since the timer was constructed.
func NewTimer() func() time.Duration {
	start := time.Now()
	return func() time.Duration {
		return time.Since(start)
	}
}

// GetStatsClient returns the stats client.
func (t *StandardTelemetry) GetStatsClient() stats.Client {
	return t.statsd
}

// GetLogger returns the logger.
func (t *StandardTelemetry) GetLogger() log.Logger {
	return t.logger
}
