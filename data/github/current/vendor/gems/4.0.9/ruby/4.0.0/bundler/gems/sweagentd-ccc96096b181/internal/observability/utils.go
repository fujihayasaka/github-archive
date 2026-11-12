package observability

import (
	"context"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/goerrors"
)

// HydrateTelemetryFunc is a function that extracts telemetry data from a request context.
type HydrateTelemetryFunc func(ctx context.Context, r *http.Request) (stats stats.Tags, exception map[string]string, log []kvp.Field)

// LoggerWithTelemetry returns a logger with telemetry fields populated from the
// context using the custom HydrateTelemetryFunc if it is set.
func (e *Exporters) LoggerWithTelemetry(ctx context.Context) log.Logger {
	if e.telemetryFunc == nil {
		return e.Logger.WithContext(ctx)
	}

	_, _, kvps := e.telemetryFunc(ctx, nil)
	return e.Logger.WithContext(ctx).WithFields(kvps...)
}

// LoggerWithRequestTelemetry returns a logger with telemetry fields populated from the request.
func (e *Exporters) LoggerWithRequestTelemetry(ctx context.Context, r *http.Request) log.Logger {
	if e.telemetryFunc == nil {
		return e.Logger.WithContext(ctx)
	}

	_, _, kvps := e.telemetryFunc(ctx, r)
	return e.Logger.WithContext(ctx).WithFields(kvps...)
}

type logAndReportOptions struct {
	r *http.Request
}

// LogAndReportOption is a functional option for configuring LogAndReportError.
type LogAndReportOption func(opts *logAndReportOptions)

// WithRequest attaches an HTTP request to the error logging context.
func WithRequest(r *http.Request) LogAndReportOption {
	return func(opts *logAndReportOptions) {
		opts.r = r
	}
}

// LogAndReportError is a convenience function that logs an error and reports
// it to sentry, using the custom HydrateTelemetryFunc if it is set.
func (e *Exporters) LogAndReportError(ctx context.Context, err error, message string, opts ...LogAndReportOption) {
	options := &logAndReportOptions{}
	for _, opt := range opts {
		opt(options)
	}

	if err == nil && message == "" {
		return
	}
	if err == nil {
		err = goerrors.New(message)
	}

	class := ""
	if t, ok := err.(interface{ Class() string }); ok {
		class = t.Class()
	}

	if e.telemetryFunc == nil {
		e.Logger.WithContext(ctx).WithError(err).Error(message)
		ex := map[string]string{}
		if class != "" {
			ex["class"] = class
		}
		_ = e.Reporter.Report(context.WithoutCancel(ctx), err, ex)
		return
	}

	_, ex, kvps := e.telemetryFunc(ctx, options.r)
	e.Logger.WithContext(ctx).WithFields(kvps...).WithError(err).Error(message)
	if class != "" {
		ex["class"] = class
	}
	_ = e.Reporter.Report(context.WithoutCancel(ctx), err, ex)
}

// TelemetryTags extracts telemetry tags from the context.
func (e *Exporters) TelemetryTags(ctx context.Context) stats.Tags {
	if e.telemetryFunc == nil {
		return stats.Tags{}
	}

	tags, _, _ := e.telemetryFunc(ctx, nil)
	return tags
}

// Increment increments a counter metric with the given key and tags.
func (e *Exporters) Increment(ctx context.Context, key string, tags stats.Tags) {
	e.Statter.Counter(key, e.TelemetryTags(ctx).Merge(tags), 1)
}

// DistributionMs records a distribution metric with the given key, tags, and duration.
func (e *Exporters) DistributionMs(ctx context.Context, key string, tags stats.Tags, time time.Duration) {
	e.Statter.DistributionMs(key, e.TelemetryTags(ctx).Merge(tags), time)
}
