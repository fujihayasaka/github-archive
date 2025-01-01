package telemetry

import (
	"context"
	"fmt"
	"os"

	"github.com/github/github-telemetry-go/log"
	ghTelemetry "github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-exceptions"
	exceptions_http "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
)

func initializeLogger(cfg *Config) (*ghTelemetry.Provider, log.Logger, error) {
	ghTelem, err := ghTelemetry.NewFromEnv()
	if err != nil {
		return nil, nil, fmt.Errorf("failed to initialize github telemetry client from env: %w", err)
	}

	baseLogger := ghTelem.Logger.Named(cfg.ServiceName)

	return ghTelem, baseLogger, nil
}

func initializeStats(cfg *Config) (stats.Client, error) {
	var client stats.Client

	if len(cfg.StatsAddr) > 0 {
		sink, err := stats.NewUDPSink(fmt.Sprintf("%s:%v", cfg.StatsAddr, cfg.StatsPort))
		if err != nil {
			return nil, fmt.Errorf("failed to create stats udp sink: %w", err)
		}
		client = stats.NewClient(sink, cfg.StatsInterval, cfg.StatsPrefix, stats.WithChannelExceededReporting())
	} else {
		client = stats.NullStatter
	}

	return client.WithTags(stats.Tags{
		"application":    cfg.ServiceName,
		"moda_env":       cfg.Env,
		"environment":    cfg.Env,
		"release":        cfg.DeployedSha,
		"deployed_ref":   cfg.DeployedRef,
		"stamp":          cfg.StampName,
		"kube_pod":       cfg.KubernetesPod,
		"kube_namespace": cfg.KubernetesNamespace,
		"kube_host":      cfg.KubernetesNode,
	}), nil
}

func initializeReporter(cfg *Config) (*exceptions.Reporter, error) {
	var (
		exporter exceptions.Exporter
		err      error
	)

	exporter = writer.NewExporter(os.Stdout)

	if cfg.FailbotURL != "" {
		exporter, err = exceptions_http.NewExporter(
			exceptions_http.WithURL(cfg.FailbotURL),
		)
		if err != nil {
			return nil, fmt.Errorf("failed to create http exporter: %w", err)
		}
	}

	errorLogger := func(reportErr, _ error, _ map[string]string) {
		logger.WithError(reportErr).Error(context.Background(), "reporter.Report has failed to report an exception")
	}

	reporter, err := exceptions.NewReporter(
		exceptions.WithApplication(cfg.ServiceName),
		exceptions.WithExporter(exporter),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithRollupInfoFunc(exceptions.RollupInfo),
		exceptions.WithErrorLogger(errorLogger),
		exceptions.WithValues(map[string]string{
			"deployed_to": cfg.Env,
			"release":     cfg.DeployedSha,
		}),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create reporter: %w", err)
	}

	return reporter, nil
}
