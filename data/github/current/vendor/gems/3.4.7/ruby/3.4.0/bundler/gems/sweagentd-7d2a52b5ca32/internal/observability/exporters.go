// Package observability exports a struct which contains different observability exporters, such as the logger, tracer, and reporter.
package observability

import (
	"context"
	"io"
	stdlog "log"
	"time"

	// Note: please do not import code from github.com/github/sweagentd/ in
	// this package. Observability needs to be a leaf package so that it can be
	// used from almost anywhere else without causing an import loop.

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-server/runtime/telemetry/reporter"
	"github.com/github/go-server/runtime/telemetry/tracer"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/requestctx"
	"go.opentelemetry.io/otel/trace/noop"
)

// Exporters contains different observability tools, such as the logger, tracer, and reporter which export
// data to services such as Sentry, Splunk and Datadog.
type Exporters struct {
	Tracer        tracer.Tracer
	Reporter      reporter.ExceptionReporter
	Statter       stats.Client
	HydroPbl      *hydro.Publisher
	Logger        log.Logger
	telemetryFunc HydrateTelemetryFunc
}

// NewExporters returns a new Exporters struct.
func NewExporters(tracer tracer.Tracer, exceptionsReporter reporter.ExceptionReporter, statter stats.Client, hydroPbl *hydro.Publisher, logger log.Logger) Exporters {
	return Exporters{
		Tracer:   tracer,
		Reporter: exceptionsReporter,
		Statter:  statter,
		HydroPbl: hydroPbl,
		Logger:   logger,
	}
}

// WithNamedLogger returns a new Exporters with the logger named with the given name.
func (e *Exporters) WithNamedLogger(name string) Exporters {
	e.Logger = e.Logger.Named(name)
	return *e
}

func (e *Exporters) WithPublisher(publisher *hydro.Publisher) Exporters {
	e.HydroPbl = publisher
	return *e
}

// WithTelemetryFunc adds a telemetry function to the Exporters struct.
// This function is used to hydrate the telemetry data before it is sent to the telemetry services.
func (e *Exporters) WithTelemetryFunc(telemetryFn HydrateTelemetryFunc) Exporters {
	e.telemetryFunc = telemetryFn
	return *e
}

// LogWithDuration logs a duration and stats it, too.
func (e *Exporters) LogWithDuration(ctx context.Context, logger log.Logger, start time.Time, action string) {
	statsTags, _, logTags := requestctx.ToTelemetry(ctx, nil)
	logger.WithContext(ctx).WithFields(logTags...).WithFields(
		kvp.Duration("duration", time.Since(start)),
		kvp.String("code.action", action),
	).Info("completed")

	e.Statter.WithTags(statsTags).DistributionMs(
		"duration",
		stats.Tags{
			"action": action,
		},
		time.Since(start),
	)
}

// NewNoopExporters returns a new Exporters struct with no-op implementations of the observability tools.
// This should only be used in tests.
func NewNoopExporters() Exporters {
	// wish hydro had a NoopPublisher, but here we are
	hydroSink := hydro.NewLogSink(stdlog.New(io.Discard, "", 0))
	hydroPbl, _ := hydro.NewPublisher(hydroSink, hydro.WithEncoder(hydro.NewJSONEncoder()))

	exp := Exporters{
		Tracer:   noop.NewTracerProvider().Tracer("noop"),
		Reporter: exceptions.NullReporter,
		Statter:  stats.NullStatter,
		HydroPbl: hydroPbl,
		Logger:   log.NewNullLogger(),
	}

	return exp
}

type MockStatter struct {
	stats.NullClient
	MockCounter func(key string, tags stats.Tags, value int64)
}

func (c *MockStatter) Counter(key string, tags stats.Tags, value int64) {
	if c.MockCounter != nil {
		c.MockCounter(key, tags, value)
		return
	}
	c.NullClient.Counter(key, tags, value)
}
