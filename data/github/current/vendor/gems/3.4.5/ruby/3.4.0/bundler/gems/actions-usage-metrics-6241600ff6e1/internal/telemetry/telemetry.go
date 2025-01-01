package telemetry

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/github-telemetry-go/trace"
	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/go-stats"
	otelSdk "go.opentelemetry.io/otel/sdk/trace"
	"go.uber.org/zap/zapcore"
	"gopkg.in/DataDog/dd-trace-go.v1/ddtrace/tracer"
)

type Telemetry struct {
	Provider *telemetry.Provider
	Stats    stats.Client
	Failbot  *exceptions.Reporter
	Logger   *Logger
	Config   config.TelemetryConfig
}

func NewTelemetry(ctx context.Context, config *config.TelemetryConfig) (*Telemetry, error) {
	telemetry := &Telemetry{
		Config: *config,
	}
	err := telemetry.setupTracing(config)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error initializing tracing: %s\n", err)
		return nil, err
	}

	err = telemetry.setupLogging(config)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error initializing logging: %s\n", err)
		return nil, err
	}
	logger := log.WithContext(ctx)

	err = telemetry.setupMetrics(ctx, config)
	if err != nil {
		logger.WithError(err).Error("error initializing metrics")
		return nil, err
	}

	err = telemetry.setupFailbot(ctx, config)
	if err != nil {
		logger.WithError(err).Error("error initializing failbot")
		return nil, err
	}

	return telemetry, nil
}

func (t *Telemetry) Shutdown(ctx context.Context) {
	tracer.Stop()
	if t.Provider != nil {
		err := t.Provider.Shutdown(ctx)
		if err != nil {
			log.WithContext(ctx).WithError(err).Error("failed to shut down telemetry")
		}
	}
	t.Stats.Stop()
	t.Logger.Shutdown()
}

func (t *Telemetry) setupTracing(config *config.TelemetryConfig) error {
	telem, err := telemetry.NewFromEnv(
		telemetry.WithTracerOptions(
			trace.WithTracerProviderOptions(
				otelSdk.WithSpanProcessor(NewLoggingContextSpanProcessor(config)),
				otelSdk.WithSampler(otelSdk.ParentBased(otelSdk.TraceIDRatioBased(config.TraceSampleRate))),
			),
			trace.WithServiceName(config.Service),
		),
	)
	if err != nil {
		return err
	}
	t.Provider = telem

	tracer.Start(getTracerOptions(config)...)
	return nil
}

func (t *Telemetry) setupLogging(config *config.TelemetryConfig) error {
	baseLogger := t.Provider.Logger.Named(config.Service)
	baseLogger = baseLogger.WithLevel(ToLogLevel(config.LogLevel, log.InfoLevel))

	logger, err := NewLogger(baseLogger, nil)
	if err != nil {
		return err
	}
	log.SetDefault(logger)

	t.Logger = logger
	return nil
}

func (t *Telemetry) setupMetrics(ctx context.Context, config *config.TelemetryConfig) error {
	logger := log.WithContext(ctx)
	sinks := []io.Writer{}
	if config.DatadogAgentHost != "" && config.DatadogAgentPort != 0 {
		datadogEndpoint := fmt.Sprintf("%v:%v", config.DatadogAgentHost, config.DatadogAgentPort)
		logger.Info("setting up datadog metrics", kvp.String(DatadogEndpointKey, datadogEndpoint))

		sink, err := stats.NewUDPSink(datadogEndpoint)
		if err != nil {
			logger.Error("could not connect to datadog agent", kvp.String(DatadogEndpointKey, datadogEndpoint))
			return err
		}

		sinks = append(sinks, sink)
	}

	if config.StdoutMetrics {
		logger.Info("setting up stdout metrics")
		sinks = append(sinks, os.Stdout)
	}

	var sink io.Writer
	switch len(sinks) {
	case 0:
		logger.Info("no metrics sinks configured")
		sink = nil
	case 1:
		sink = sinks[0]
	default:
		sink = io.MultiWriter(sinks...)
	}

	tags := stats.Tags{
		"service":             config.Service,
		"kube_namespace":      config.KubeNamespace,
		"pod_name":            config.PodName,
		"kube_container_name": config.KubeContainerName,
		"environment":         string(config.Environment),
	}

	var statsClient stats.Client
	if sink != nil {
		statsClient = stats.NewClient(sink, time.Second, "").WithTags(tags)
		statsClient.Run()
		statsClient.Event("telemetry.started", "telemetry started", stats.Tags{})
	} else {
		statsClient = stats.NullStatter
	}

	t.Stats = statsClient
	t.Logger.metrics.client = statsClient

	return nil
}

func (t *Telemetry) setupFailbot(ctx context.Context, config *config.TelemetryConfig) error {
	var exporter exceptions.Exporter
	var err error
	logger := log.WithContext(ctx)

	// Create a http exporter if we're in production && have a failbot url set
	if config.FailbotHaystackURL == "" {
		exporter = writer.NewExporter(os.Stdout)
	} else {
		exporter, err = http.NewExporter(http.WithURL(config.FailbotHaystackURL))
		if err != nil {
			return err
		}
	}

	errorLogger := func(reportErr, exception error, payload map[string]string) {
		var fields []zapcore.Field
		for key, value := range payload {
			fields = append(fields, kvp.String(key, value))
		}
		logger.WithError(reportErr).WithError(exception).Error("reporter.Report has failed to report an exception", fields...)
	}

	// Initialize the error reporter client
	r, err := exceptions.NewReporter(
		exceptions.WithApplication(config.Service),
		exceptions.WithExporter(exporter),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithRollupInfoFunc(exceptions.RollupInfo),
		exceptions.WithErrorLogger(errorLogger),
		exceptions.WithValues(map[string]string{
			"service":             config.Service,
			"environment":         string(config.Environment),
			"cluster":             config.KubeClusterName,
			"namespace":           config.KubeNamespace,
			"pod_name":            config.PodName,
			"kube_container_name": config.KubeContainerName,
		}),
	)
	if err != nil {
		return err
	}

	SetFailbotClient(r)
	t.Failbot = r
	return nil
}

func getTracerOptions(config *config.TelemetryConfig) []tracer.StartOption {
	options := []tracer.StartOption{
		tracer.WithEnv(string(config.Environment)),
		tracer.WithService(config.Service),
		tracer.WithTraceEnabled(false),
		tracer.WithRuntimeMetrics(),
		tracer.WithServiceVersion("0.0.1"),
		tracer.WithGlobalTag("service", config.Service),
	}
	if config.DatadogAgentHost != "" && config.DatadogAgentPort != 0 {
		datadogEndpoint := fmt.Sprintf("%v:%v", config.DatadogAgentHost, config.DatadogAgentPort)
		options = append(options, tracer.WithDogstatsdAddress(datadogEndpoint))
	}
	return options
}
