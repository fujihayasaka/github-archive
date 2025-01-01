// Package logger implements a simple logging API that uses github/github-telemetry-go/log for its
// underlying implementation.
//
// Each logging method call produces a single log line with the given message
// and field context given at the call site, as well as the receiving Logger's
// pre-defined context.
//
// For instance, say you would like to log information about a given application
// request. You would start by using the application-level logger, which embeds
// information about the application's runtime: perhaps its host, deployed SHA1,
// and others. You would then attach a message and contextual data to the logger
// like so:
//
//	var app logger.Logger
//	app.Log("preformed request",
//		kvp.String("to", "https://api.github.com/),
//		kvp.Int("respsonse", res.StatusCode),
//		// ...
//	)
//
// and then receive a log line to stdout that contains:
//  1. The "preformed request" message.
//  2. The pre-defined application context.
//  3. The given request-level context.
//
// to the effect of:
//
//	time=2016-10-25T14:14:19Z Body="preformed request" app=lfs-server to=https://api.github.com response=200
package logger

import (
	"context"
	"fmt"
	"os"

	otelkvp "github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-kvp"
	"github.com/github/go-reqmeta"
	circuit "github.com/rubyist/circuitbreaker"

	mureqmeta "github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/pkg/launchconfig"
)

// Logger represents a logging object that generates log output.
type Logger interface {
	Debug(ctx context.Context, msg string, fields ...kvp.Field)
	Log(ctx context.Context, msg string, fields ...kvp.Field)
	Error(ctx context.Context, msg string, fields ...kvp.Field)
	// Log an error and any fields it has in its context
	ErrorWithFields(ctx context.Context, msg string, err error, fields ...kvp.Field)
	Report(ctx context.Context, err error, fields ...kvp.Field)
	ReportBlocking(ctx context.Context, err error, fields ...kvp.Field) error

	ToOtelLogger() log.Logger
}

type logger struct {
	l log.Logger

	r *exceptions.Reporter

	// Fields to report as tags to Sentry, see https://github.com/github/failbotg/issues/265
	reportFieldTags map[string]bool
}

// Config configures the logger.
type Config struct {
	Debug     bool            // Debug shows log.Debug messages when true 	LogDebug         bool   `config:"true"`
	App       string          // App name for reporting
	ReportURL string          // URL for reporting
	Hostname  string          // Hostname for reporting
	Writer    log.WriteSyncer // Optional destination for writing logs, intended for testing
	FieldTags map[string]bool // Fields to report as tags for sentry
	Reporter  *exceptions.Reporter

	// Logger configuration
	launchconfig.LoggerConfig

	// Length of the reporter queue, beyond this dropped reports will occur
	ReporterQueueLength int `config:"16,env=REPORTER_QUEUE_LENGTH"`
}

// New creates a new Logger that attaches the given fieldset to each log
// line. If debug is true, Debug messages will be logged, and log output will be
// colorized if it is attached to an appropriate terminal.
func New(cfg *Config) Logger {
	// The LAUNCH_LOG_DEBUG env variable (fed into cfg.Debug) is what we use to
	// disable debug logging in GHES, as it's noisy for customers and can
	// cause storage/telemetry issues.
	level := log.InfoLevel.String()
	if cfg.Debug {
		level = log.DebugLevel.String()
	}

	opts := []log.Option{}
	if cfg.Writer != nil {
		opts = append(opts, log.WithWriteSyncer(cfg.Writer))
	}

	l, err := log.NewFromConfig(log.Config{
		LogLevel:           level,
		LogConsoleEncoding: cfg.LoggerConfig.LogFormat,
		LogTimezone:        cfg.LoggerConfig.LogTimezone,
		LogPrecision:       cfg.LoggerConfig.LogPrecision,
	}, opts...)
	if err != nil {
		fmt.Printf("could not parse github-telemetry-go config: %v", err)
	}

	r := cfg.Reporter

	if r == nil {
		errorHandler := func(err error) {
			l.Error("failed reporting haystack needle", otelkvp.Err(err))
		}
		defaultReporter, err := newReporter(cfg.App, cfg.ReportURL, cfg.Hostname, errorHandler, cfg.ReporterQueueLength)
		if err != nil {
			l.Error("could not create defaultReporter", otelkvp.Err(err))
		}
		r = defaultReporter
	}

	l.Debug("logger configuration",
		otelkvp.Any("gh.launch.logger_config", cfg.LoggerConfig),
		otelkvp.Bool("gh.launch.log_level", cfg.Debug),
	)

	return &logger{
		l:               l,
		r:               r,
		reportFieldTags: cfg.FieldTags,
	}
}

// DefaultLogger returns the default logger
func DefaultLogger() Logger {
	return New(&Config{Writer: os.Stderr, Reporter: NullReporter()})
}

// TestLogger creates a logger that writes logs to stderr and discards
// reports. This is meant to be used in a testing environment.
// Use testutils.NewRecordingLogger if the logging output is needed for testing purposes.
func TestLogger() Logger {
	return New(&Config{Writer: os.Stderr, Reporter: NullReporter()})
}

// NullLogger creates a logger that discards all logs.
func NullLogger() Logger {
	return &logger{l: log.NewNullLogger(), r: NullReporter()}
}

func (l *logger) ToOtelLogger() log.Logger {
	return l.l
}

// Debug logs the given message and fields at the "debug" level.
func (l *logger) Debug(ctx context.Context, msg string, fields ...kvp.Field) {
	l.l.Debug(msg, l.unwrap(ctx, fields)...)
}

// Log logs the given message and fields.
func (l *logger) Log(ctx context.Context, msg string, fields ...kvp.Field) {
	l.l.Info(msg, l.unwrap(ctx, fields)...)
}

// Error logs the given message and fields.
func (l *logger) Error(ctx context.Context, msg string, fields ...kvp.Field) {
	l.l.Error(msg, l.unwrap(ctx, fields)...)
}

func (l *logger) ErrorWithFields(ctx context.Context, msg string, err error, fields ...kvp.Field) {
	logFields := append(fields, kvp.Err(err))
	for _, f := range kvperrors.FindContext(err) {
		logFields = append(logFields, kvp.Any(f.Key, f.Value()))
	}
	l.Error(ctx, msg, logFields...)
}

// Report reports the error to Sentry along with any given fields.
func (l *logger) Report(ctx context.Context, err error, fields ...kvp.Field) {
	l.logReport(ctx, err, fields...)
	m := l.prepareReport(ctx, err, fields...)
	err = l.r.Report(context.Background(), err, m)
	if err != nil {
		l.l.Error(fmt.Sprintf("error sending report %+v", err))
	}
}

// ReportBlocking reports the error the same as Report but blocks to ensure the
// report is sent.
func (l *logger) ReportBlocking(ctx context.Context, err error, fields ...kvp.Field) error {
	l.logReport(ctx, err, fields...)
	m := l.prepareReport(ctx, err, fields...)
	err = l.r.Report(context.Background(), err, m)
	if err != nil {
		l.l.Error(fmt.Sprintf("error sending report %+v", err))
	}
	return err
}

func (l *logger) logReport(ctx context.Context, err error, fields ...kvp.Field) {
	logFields := append(fields, kvp.Bool("gh.launch.sentry_report", true))
	for _, f := range kvperrors.FindContext(err) {
		logFields = append(logFields, kvp.Any(f.Key, f.Value()))
	}
	msg := fmt.Sprintf("Sentry: %v", err.Error())
	l.Error(ctx, msg, logFields...)
}

func (l *logger) prepareReport(ctx context.Context, err error, fields ...kvp.Field) map[string]string {
	m := make(map[string]string)

	fields = append(ctxstash.From(ctx).Fields(), fields...)

	if rmd, ok := ctx.Value(mureqmeta.RMDContextKey).(*mureqmeta.RequestMetadata); ok {
		for _, f := range rmd.LogFields() {
			m[f.Key] = f.String()
		}
	}

	if rmeta, ok := reqmeta.GetRequestMetadata(ctx); ok {
		for _, f := range rmeta.LogFields() {
			m[f.Key] = f.String()
		}
	}

	for _, f := range fields {
		m[f.Key] = f.String()
	}

	for _, f := range kvperrors.FindContext(err) {
		m[f.Key] = f.String()
	}

	// Report repo global id as user to Sentry (if no explicit user set)
	if repoGlobalID, ok := m["gh.repo.global_id"]; ok {
		if _, ok := m["user"]; !ok {
			m["user"] = repoGlobalID
		}
	}

	// Prefix interesting fields with "#" to mark them as tags for Sentry
	for k, v := range m {
		if l.reportFieldTags[k] {
			delete(m, k)
			m["#"+k] = v
		}
	}
	m["reporter-type"] = "go-exceptions"

	// go-exceptions really wants to set these itself, and mu has added them.
	delete(m, "host")
	delete(m, "app")

	return m
}

// unwrap takes a slice of wrapped `Field`s, and returns underlying
// fields in the same order as was given in the `fields` argument.
// These fields will be converted to `otelkvp.Field` and returned.
func (l *logger) unwrap(ctx context.Context, fields []kvp.Field) []otelkvp.Field {
	fields = append(fields, ctxstash.From(ctx).Fields()...)

	// Tired: rmdFields use mu's KVP and RequestMetadata
	var rmdFields []kvp.Field

	if rmd, ok := ctx.Value(mureqmeta.RMDContextKey).(*mureqmeta.RequestMetadata); ok {
		rmdFields = rmd.LogFields()
	}

	// Wired: go-kvp and go-reqmeta instead
	var goFields []kvp.Field
	if rmd, ok := reqmeta.GetRequestMetadata(ctx); ok {
		goFields = rmd.LogFields()
	}

	// Put them all together
	inners := make([]kvp.Field, 0, len(goFields)+len(rmdFields)+len(fields))

	// Add rmdFields
	for _, f := range rmdFields {
		inners = append(inners, kvp.String(f.Key, f.String()))
	}

	// Append goFields
	inners = append(inners, goFields...)

	// Finally append the passed in `fields`
	inners = append(inners, fields...)

	// Convert to otelkvp.Field
	return toOtelKVP(inners...)
}

func toOtelKVP(fields ...kvp.Field) []otelkvp.Field {
	o := make([]otelkvp.Field, 0, len(fields))
	for _, f := range fields {
		var of otelkvp.Field
		switch f.T {
		case kvp.AnyType:
			of = otelkvp.Any(f.Key, f.Any)
		case kvp.BoolType:
			of = otelkvp.Bool(f.Key, f.Boolean)
		case kvp.IntType:
			of = otelkvp.Int(f.Key, int(f.Int))
		case kvp.UintType:
			of = otelkvp.Uint(f.Key, uint(f.Int))
		case kvp.FloatType:
			of = otelkvp.Float64(f.Key, f.AsFloat())
		case kvp.DurationType:
			of = otelkvp.Duration(f.Key, f.AsDuration())
		case kvp.TimeType:
			of = otelkvp.Time(f.Key, f.AsTime())
		case kvp.StringType:
			of = otelkvp.String(f.Key, f.Str)
		case kvp.LazyType:
			// no longer lazy, but we never use it.
			of = otelkvp.Any(f.Key, f.LazyValue())
		case kvp.ErrorType:
			of = otelkvp.Any(f.Key, f.Str)
		}
		o = append(o, of)
	}
	return o
}

// eventKeys is the set of circuit breaker events we would like logged.
var eventKeys = map[circuit.BreakerEvent]string{
	circuit.BreakerTripped: "tripped",
	circuit.BreakerReset:   "reset",
	circuit.BreakerReady:   "ready",
}

// MonitorCircuitBreaker will log circuit breaker events.
func MonitorCircuitBreaker(ctx context.Context, log Logger, name string, breaker *circuit.Breaker) {
	bc := make(chan circuit.ListenerEvent, 1)
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case e := <-bc:
				if key, ok := eventKeys[e.Event]; ok {
					log.Debug(ctx, "Circuit Breaker Event", kvp.String("gh.circuit_breaker.state", key), kvp.String("gh.circuit_breaker.name", name))
				}
			}
		}
	}()

	breaker.AddListener(bc)
}
