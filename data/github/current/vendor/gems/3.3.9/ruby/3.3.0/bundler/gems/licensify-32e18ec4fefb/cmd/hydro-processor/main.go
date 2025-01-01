// This is the main entry point for the hydro-processor service.
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
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/hydro"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/hydro/topics"
	"github.com/github/licensify/internal/monolith"
)

func main() {
	if err := runProcessor(); err != nil {
		fmt.Printf("failed to run the processor: %v\n", err)
		os.Exit(1)
	}
}

func runProcessor() error {
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

	logger := cfg.ConfigureLogger(telem.Logger, cfg.ServiceName).Named("hydro-processor")

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.HeavenEnv, "service": cfg.ServiceName, "process.executable.name": "hydro-processor"})

	logger.Info("starting statsd client")
	statter.Run()
	defer statter.Stop()

	tracer := telem.Tracer.Tracer

	dbConnection, err := cosmos.NewDatabaseConnection(mainCtx, cfg, logger, statter)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return err
	}

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

	monolithClient, err := monolith.NewClient(cfg.MonolithTwirpURL, cfg.MonolithTwirpHMACKey)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("failed to create monolith client for hydro processor: %w", err)
	}

	eventHandler, err := eventhandlers.NewEventHandler(dbConnection, jobby, monolithClient, statter, tracer)
	if err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("error creating event handler: %w", err)
	}

	consumer := &hydro.Consumer{
		Config:       cfg,
		Topics:       topics.All(),
		EventHandler: eventHandler,
		Logger:       logger,
		Statter:      statter,
		Tracer:       tracer,
	}

	// set up readiness probe for k8s to check pod is alive
	if err = hydro.CreateReadinessProbeFile(); err != nil {
		_ = errorReporter.Report(mainCtx, err, nil)
		return fmt.Errorf("error creating readines probe: %w", err)
	}

	signalCtx, stop := signal.NotifyContext(mainCtx, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	if err := consumer.Run(signalCtx); err != nil {
		logger.WithError(err).Error("consumer crashed")
		_ = errorReporter.Report(mainCtx, err, nil)
		return err
	}

	return nil
}
