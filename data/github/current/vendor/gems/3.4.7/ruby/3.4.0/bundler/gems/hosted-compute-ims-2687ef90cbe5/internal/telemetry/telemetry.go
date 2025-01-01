package telemetry

import (
	"context"
	"fmt"

	ghTelemetry "github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/go-stats/ps"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/reporter"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/github/hosted-compute-ims/internal/telemetry/tracer"
)

type Telemetry struct {
	telemProvider *ghTelemetry.Provider
	baseStatter   stats.Client
}

func InitializeTelemetry(ctx context.Context, cfg *Config) (*Telemetry, error) {
	ghTelem, baseLogger, err := initializeLogger(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize logger: %w", err)
	}

	baseTracer := ghTelem.Tracer.Tracer

	baseStatter, err := initializeStats(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize statter: %w", err)
	}
	baseStatter.Run()

	if cfg.IsProductionEnv() {
		processStatter := ps.Reporter{
			Stats:    baseStatter,
			Interval: cfg.StatsInterval,
		}
		go processStatter.Run(ctx) //nolint:errcheck
	}

	baseReporter, err := initializeReporter(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize reporter: %w", err)
	}

	logger.SetLogger(baseLogger)
	tracer.SetTracer(baseTracer)
	statter.SetStatter(baseStatter)
	reporter.SetReporter(baseReporter)

	baseLogger.Info("finished telemetry initialization")

	return &Telemetry{
		baseStatter:   baseStatter,
		telemProvider: ghTelem,
	}, nil
}

func (tel *Telemetry) Shutdown(ctx context.Context) {
	logger.Info(ctx, "shutting down telemetry")

	tel.baseStatter.Stop()
	if err := tel.telemProvider.Shutdown(ctx); err != nil {
		logger.WithError(err).Error(ctx, "failed to shutdown telemetry")
	}
}
