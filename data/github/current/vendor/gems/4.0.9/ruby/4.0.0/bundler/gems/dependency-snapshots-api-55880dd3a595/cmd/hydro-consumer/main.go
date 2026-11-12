package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/dependency-snapshots-api/internal/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/hydro/handlers"
	"github.com/github/go-stats/ps"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/pkg/errors"
)

// BuildCommit - latest commit SHA for this build; injected at compile-time
var BuildCommit = "UNKNOWN"

type Consumer string

const (
	RepoPush                Consumer = "repo-push"
	ActionsComputeUsage     Consumer = "actions-compute-usage"
	ActivationLifecycle     Consumer = "activation-lifecycle"
	SnapshotDenormalization Consumer = "snapshot-denormalization"
)

func (c *Consumer) Set(v string) error {
	switch Consumer(v) {
	case RepoPush, ActionsComputeUsage, ActivationLifecycle, SnapshotDenormalization:
		*c = Consumer(v)
		return nil
	default:
		return fmt.Errorf("invalid consumer: %q", v)
	}
}

func (c *Consumer) String() string {
	if c == nil {
		return ""
	}
	return string(*c)
}

// ShutdownTimeout for graceful termination
const ShutdownTimeout = 30 * time.Second

func main() {
	if err := realMain(); err != nil {
		crashingError := errors.Wrap(err, "application failed")
		contextlogger.Error(context.Background(), "Application crashed",
			kvp.String("exception.message", err.Error()))
		log.Fatal(crashingError.Error())
	}
}

func realMain() error {
	var consumerType Consumer
	flag.Var(&consumerType, "consumer", "Type of consumer to run: repo-push, actions-compute-usage, activation-lifecycle")
	flag.Parse()

	// Root context canceled on SIGINT/SIGTERM.
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	defer cancel()

	// initialize runtime configuration
	cfg, err := config.Load(BuildCommit)
	if err != nil {
		return err
	}

	// initialize logger
	err = cfg.InitDefaultLogger()
	if err != nil {
		log.WithError(err).Fatal("couldn't initialize logger")
	}
	logger := log.Named("default")
	logger.Info("initializing consumer...")

	// initialize statter
	statter, err := cfg.NewStatsClient()
	if err != nil {
		return err
	}
	logger.Info("starting statsd client.")
	statter.Run()
	defer statter.Stop()

	// initialize runtime teardown context
	tracerTeardown, err := config.Instrument(cfg)
	if err != nil {
		return errors.Wrap(err, "failed to create tracer")
	}
	defer tracerTeardown()

	// initialize proc stats reporter
	procStats := &ps.Reporter{Stats: statter, Interval: time.Second * 5}

	if cfg.Enterprise {
		logger.Info("Hydro consumer is not supported in GHES; exiting")
		return nil
	}

	// initialize aqueduct enqueuer
	aqueductClient, err := aqueduct.NewClient(cfg, logger, statter)
	if err != nil {
		return errors.Wrap(err, "failed to create aqueduct client")
	}
	enqueuer := aqueduct.NewJobEnqueuer(cfg, aqueductClient, statter)

	// Clear registration of topics -> handlers
	registeredHandlers := map[string]hydro.EnvelopeHandler{}

	switch consumerType {
	case RepoPush:
		repoPushHandler := handlers.NewRepositoryPushHandler(cfg, logger, statter, enqueuer)
		registeredHandlers[handlers.HydroTopicRepositoryPush] = repoPushHandler
	case ActionsComputeUsage:
		actionsComputeUsageHandler := handlers.NewActionsComputeUsageHandler(cfg, logger, statter, enqueuer)
		registeredHandlers[handlers.HydroTopicActionsComputeUsage] = actionsComputeUsageHandler
	case ActivationLifecycle:
		// We consume both enroll and reset manifests topics in the same pod
		// since they are both part of the activation lifecycle domain.
		resetManifestsHandler := handlers.NewResetManifestsHandler(cfg, logger, statter, enqueuer)
		enrollManifestsHandler := handlers.NewEnrollManifestsHandler(cfg, logger, statter, enqueuer)
		registeredHandlers[handlers.HydroTopicEnrollManifests] = enrollManifestsHandler
		registeredHandlers[handlers.HydroTopicResetManifests] = resetManifestsHandler
	case SnapshotDenormalization:
		snapshotProcessedHandler := handlers.NewSnapshotProcessedHandler(logger, statter, enqueuer)
		registeredHandlers[handlers.HydroTopicSnapshotProcessed] = snapshotProcessedHandler
	default:
		return fmt.Errorf("unknown consumer type: %q", consumerType)
	}

	hydroConsumer, err := hydro.NewConsumer(cfg, logger, statter, registeredHandlers)
	if err != nil {
		return fmt.Errorf("error constructing Hydro consumer: %w", err)
	}

	return run(ctx, logger, hydroConsumer, procStats, ShutdownTimeout)
}

type Runner interface {
	Run(context.Context) error
}

// run executes the consumer + proc-stats orchestration and handles graceful shutdown.
func run(ctx context.Context, logger log.Logger, consumer, procStats Runner, shutdownTimeout time.Duration) error {
	// Derive a context we can always cancel on return so background goroutines don't leak.
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Run the proc stats reporter on a goroutine
	go func() {
		err := procStats.Run(ctx)
		if err != nil {
			// At the time of this code being written, procStats.Run had no error case.
			// We don't want this goroutine to crash the process, so we just log the error.
			logger.Error("procStats.Run returned an error", kvp.String("exception.message", err.Error()))
		}
	}()

	// Run hydro in background, report when it exits.
	hydroDone := make(chan error, 1)
	go func() {
		hydroDone <- consumer.Run(ctx)
	}()

	// Wait for either shutdown signal or hydro exiting on its own.
	select {
	case <-ctx.Done():
		logger.Info("shutdown signal received, cancelling hydro consumer...")
	case err := <-hydroDone:
		if err != nil && !errors.Is(err, context.Canceled) {
			logger.WithError(err).Error("hydroConsumer.Run returned an error")
			return err
		}
		logger.Info("hydro consumer exited, shutting down...")
		return nil
	}

	// Cancel after shutdownTimeout
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer shutdownCancel()

	// Wait for hydro to stop or shutdown timeout.
	select {
	case err := <-hydroDone:
		if err != nil && !errors.Is(err, context.Canceled) {
			logger.WithError(err).Error("Hydro stopped with error during shutdown")
			return err
		}
		logger.Info("shutdown complete")
		return nil
	case <-shutdownCtx.Done():
		logger.Error("shutdown timed out waiting for Hydro to stop",
			kvp.String("timeout", shutdownTimeout.String()))
		return shutdownCtx.Err()
	}
}
