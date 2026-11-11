package consumer

import (
	"context"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"go.opentelemetry.io/otel/codes"
)

const defaultPoolName = "default-pool" // should be overwritten by options
const defaultWorkerCount int = 1
const defaultHeartBeatInterval = 30 * time.Second
const defaultHeartBeatTimeout = 60 * time.Second

// workerConfig holds the configuration for the worker pool.
type workerConfig struct {
	obsv              observability.Exporters
	workerCount       int
	heartBeatInterval time.Duration
	heartBeatTimeout  time.Duration
	handler           aqueduct.JobHandler
	beforeReceiveHook aqueduct.BeforeReceiveHook
	queues            []string
	poolName          string
	statsConfig       *aqueduct.StatsConfig
	errorHook         aqueduct.ErrorHook
}

// NewWorkerPool creates a new WorkerPool with the provided options.
func NewWorkerPool(ctx context.Context, obsv observability.Exporters, ac sweagentd.AqueductClient, options ...PoolOption) (*aqueduct.WorkerPool, error) {
	ctx, span := obsv.Tracer.Start(ctx, "aqueduct.NewWorkerPool")
	defer span.End() // Ensure the span is ended

	methodLogger := obsv.Logger.WithContext(ctx).WithFields(
		kvp.String("code.function", "NewWorkerPool"),
		kvp.String("code.namespace", "aqueduct"),
	)
	defer obsv.LogWithDuration(ctx, methodLogger, time.Now(), "NewWorkerPool ")

	wp := &workerConfig{
		workerCount:       defaultWorkerCount,
		heartBeatInterval: defaultHeartBeatInterval,
		heartBeatTimeout:  defaultHeartBeatTimeout,
		poolName:          defaultPoolName,
		obsv:              obsv,
	}
	for _, option := range options {
		option(wp)
	}

	methodLogger.Info("Initializing Aqueduct worker pool")

	statsConfig, err := aqueduct.NewStatsConfig(
		aqueduct.WithStatsClient(wp.obsv.Statter),
	)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		methodLogger.WithError(err).Error("error creating stats config for Aqueduct worker pool")
		return nil, err
	}
	wp.statsConfig = statsConfig

	heartBeatConfig, err := aqueduct.NewHeartbeatConfig(
		aqueduct.WithHeartbeatInterval(wp.heartBeatInterval),
		aqueduct.WithHeartbeatTimeout(wp.heartBeatTimeout),
	)
	if err != nil {
		err = goerrors.Errorf("failed to create heartbeat config: %w", err)
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		methodLogger.WithError(err).Error("error creating heartbeat config for Aqueduct worker pool")
		return nil, err
	}

	pool, err := aqueduct.NewWorkerPool(
		ac.InternalClient(),
		ac.AppName(),
		wp.queues,
		wp.handler,
		wp.workerCount,
		aqueduct.WithPool(wp.poolName),
		aqueduct.WithHeartbeatConfig(heartBeatConfig),
		aqueduct.WithLogger(wp.obsv.Logger.Named("aqueduct-worker")),
		aqueduct.WithWorkerStats(wp.statsConfig),
		aqueduct.WithBeforeReceiveHook(wp.beforeReceiveHook),
		aqueduct.WithErrorHook(wp.errorHook),
	)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		methodLogger.WithError(err).Error("error creating Aqueduct worker pool")
		return nil, goerrors.Errorf("failed to create Aqueduct worker pool: %w", err)
	}

	methodLogger.Info("Aqueduct worker pool created successfully")

	return pool, nil
}
