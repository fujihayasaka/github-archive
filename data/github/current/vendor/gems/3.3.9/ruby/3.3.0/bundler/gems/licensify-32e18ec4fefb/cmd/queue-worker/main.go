// This is the main entry point for the queue worker. It is responsible for processing messages from the aqueduct queue.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/aqueduct"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/featureflags"
	"github.com/github/licensify/internal/hydro"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/monolith"
)

func main() {
	if err := runQueueWorker(); err != nil {
		fmt.Printf("failed to run the worker: %v\n", err)
		os.Exit(1)
	}
}

func runQueueWorker() error {
	mainCtx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		fmt.Printf("Failed loading config: %v\n", err)
		return err
	}

	errorReporter, err := cfg.NewExceptionReporter()
	if err != nil {
		fmt.Printf("Failed initializing exception reporter: %v\n", err)
		return err
	}

	telem, err := telemetry.NewFromEnv()
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("failed to configure telemetry: %w", err)
	}
	defer func() {
		if err := telem.Shutdown(mainCtx); err != nil {
			_ = errorReporter.Report(mainCtx, err, nil)
			fmt.Printf("failed to shutdown telemetry: %v\n", err)
		}
	}()

	logger := cfg.ConfigureLogger(telem.Logger, cfg.ServiceName).Named("queue-worker")

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.HeavenEnv, "process.executable.name": "queue-worker"})

	logger.Info("starting statsd client")
	statter.Run()
	defer statter.Stop()

	tracer := telem.Tracer.Tracer

	aqueductClient, err := aqueduct.NewClient(
		cfg.AqueductURL,
		cfg.AqueductAPIKey,
		cfg.AqueductAPIKeyVersion,
		statter,
	)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("failed to create aqueduct client: %w", err)
	}
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: aqueductClient}

	dbConnection, err := cosmos.NewDatabaseConnection(mainCtx, cfg, logger, statter)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return err
	}

	monolithClient, err := monolith.NewClient(cfg.MonolithTwirpURL, cfg.MonolithTwirpHMACKey)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("failed to create monolith client for worker: %w", err)
	}

	featureFlagsClient, err := featureflags.NewClient(cfg.FeaturesAPIURL, cfg.FeaturesAPIHMACKey)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("failed to create feature flags client for worker: %w", err)
	}

	if err = aqueduct.CreateReadinessProbeFile(); err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("failed to create readiness probe file for worker: %w", err)
	}

	eventHandler, err := eventhandlers.NewEventHandler(dbConnection, jobby, monolithClient, statter, tracer)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("error creating event handler: %w", err)
	}

	hydroPublisher, err := hydro.NewHydroPublisher(mainCtx, cfg, logger)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("error creating hydro publisher: %w", err)
	}

	workerType := queues.QueueWorkerType(cfg.AqueductWorkerType)
	var workerQueues []string

	switch workerType {
	case queues.WorkerTypeLowPriority:
		logger.Info("starting low-priority queue worker")
		workerQueues = queues.LowPriorityQueues
	case queues.WorkerTypeStandardPriority:
		logger.Info("starting standard-priority queue worker")
		workerQueues = queues.StandardPriorityQueues
	default:
		err := fmt.Errorf("unknown worker type: %s", workerType)
		_ = errorReporter.Report(mainCtx, err, nil)
		return err
	}

	signalCtx, stop := signal.NotifyContext(mainCtx, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	aqueductConsumer := aqueduct.NewConsumer(
		aqueductClient,
		cfg.AqueductApp,
		workerQueues,
		cfg.AqueductWorkerCount,
		dbConnection,
		cfg,
		monolithClient,
		eventHandler,
		hydroPublisher,
		featureFlagsClient,
	)
	err = aqueductConsumer.Start(signalCtx, logger, statter, errorReporter, tracer)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("failed to start aqueduct consumer: %w", err)
	}
	return nil
}
