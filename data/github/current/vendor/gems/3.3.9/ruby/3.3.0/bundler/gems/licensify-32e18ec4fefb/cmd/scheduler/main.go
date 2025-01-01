// The main.go file is the entry point for the scheduler
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	stats "github.com/github/go-stats"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/hydro"
	"github.com/github/licensify/internal/scheduler"
)

func main() {
	if err := realMain(); err != nil {
		fmt.Printf("failed to run service: %v\n", err)
		os.Exit(1)
	}
}

func realMain() error {
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

	ctx := context.Background()
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		fmt.Printf("Failed configuring telemetry: %v\n", err)
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}
	defer func() {
		if err := telem.Shutdown(ctx); err != nil {
			_ = errorReporter.Report(ctx, err, nil)
			fmt.Printf("failed to shutdown telemetry: %v\n", err)
		}
	}()

	logger := cfg.ConfigureLogger(telem.Logger, "Scheduler")
	logger.Info("initializing service",
		kvp.Int("net.host.port", cfg.HTTPPort),
		kvp.String("db.cosmosdb.container", cfg.ContainerName),
		kvp.String("db.cosmosdb.database", cfg.DatabaseName),
		kvp.String("db.cosmosdb.host", cfg.DatabaseEndpoint),
	)

	// Initialize the statsd client
	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.HeavenEnv, "service": "scheduler"})
	logger.Info("starting statsd client")
	statter.Run()
	defer statter.Stop()

	// set up readiness probe for k8s to check pod is alive
	if err = hydro.CreateReadinessProbeFile(); err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return fmt.Errorf("error creating readiness probe: %w", err)
	}

	// Scheduler
	logger.Info("Initializing scheduler...")
	readWriteDB, err := cosmos.NewDatabaseConnection(ctx, cfg, logger, statter)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}

	sch := scheduler.NewScheduler(ctx, readWriteDB, cfg, logger, errorReporter, statter)

	go sch.RunAsync()

	gracefulShutdown := make(chan os.Signal, 1)
	signal.Notify(gracefulShutdown, syscall.SIGINT, syscall.SIGTERM)

	<-gracefulShutdown
	sch.Stop()

	return nil
}
