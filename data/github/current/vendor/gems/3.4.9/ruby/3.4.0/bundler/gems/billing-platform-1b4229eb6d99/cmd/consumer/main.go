package main

import (
	"context"
	"fmt"
	"os"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/hydro"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
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

	if err = cfg.ValidateBaseConfig(); err != nil {
		fmt.Printf("Failed validating config: %v\n", err)
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
		_ = errorReporter.Report(ctx, err, nil)
		return errors.Wrap(err, "failed to configure telemetry")
	}
	defer func() {
		if err := telem.Shutdown(ctx); err != nil {
			_ = errorReporter.Report(ctx, err, nil)
			fmt.Printf("failed to shutdown telemetry: %v\n", err)
		}
	}()

	logger := cfg.ConfigureLogger(telem.Logger, "BillingPlatformHydroConsumer")
	logger.Info("initializing service",
		kvp.Int("net.host.port", cfg.HTTPPort),
		kvp.String("db.cosmosdb.container", cfg.ContainerName),
		kvp.String("db.cosmosdb.database", cfg.DatabaseName),
		kvp.String("db.cosmosdb.host", cfg.DatabaseEndPoint),
		kvp.String("db.cosmosdb.gateway_host", cfg.GatewayDatabaseEndPoint),
	)

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.Environment, "service": "consumer"})

	logger.Info("starting statsd client")
	statter.Run()
	defer statter.Stop()

	tracer := telem.Tracer.Tracer
	// flagger := cfg.NewFeatureFlagClient(logger, statter)

	statter.Counter("consumer.start", stats.Tags{"consumer": "billing-hydro-consumer"}, 1)

	readWriteDB := db.NewDatabase(cfg, logger, statter, tracer)
	monolithClient, err := cfg.NewMonolithClient(ctx)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return errors.Wrap(err, "failed to configure monolith client")
	}

	consumer := &hydro.Consumer{
		Config:           cfg,
		EnvelopeHandlers: hydro.BuildHandlers(readWriteDB, monolithClient),
		Topics:           hydro.BuildTopics(cfg),
		Logger:           logger,
		Statter:          statter,
		Tracer:           tracer,
	}

	// set up readiness probe for k8s to check pod is alive
	if err = messaging.CreateReadinessProbeFile(); err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return fmt.Errorf("error creating readines probe: %w", err)
	}

	if err := consumer.Run(ctx); err != nil {
		logger.WithError(err).Error("consumer crashed")
		_ = errorReporter.Report(context.Background(), err, nil)
		return err
	}

	return nil
}
