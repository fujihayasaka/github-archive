// Snapshot Processed Hydro consumer with managed lifecycle
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/consumer"
)

const (
	shutdownTimeout = 30 * time.Second
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "snapshot-processed consumer failed: %v\n", err) //nolint:revive // unhandled-error: already in an error condition
		os.Exit(1)
	}
}

func run() error {
	ctx := context.Background()
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	tele, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}
	logger := tele.Logger.Named("snapshot-processed")

	reporter, err := cfg.NewExceptionReporter()
	if err != nil {
		return err
	}

	statter, err := cfg.NewStatsClient()
	if err != nil {
		return err
	}
	logger.Info("starting statsd client.")
	statter.Run()
	defer statter.Stop()

	defer func() {
		if recovered := recover(); recovered != nil {
			tags := stats.Tags{
				"service": "snapshot-processed",
			}
			statter.Counter("internal.service.panic", tags, 1)
			panic(recovered)
		}
	}()

	app, err := application.New(cfg, logger, statter)
	if err != nil {
		// Report the error to Sentry via failbotg
		if reportErr := reporter.Report(ctx, err, map[string]string{
			"service":   "snapshot-processed",
			"component": "application_setup",
		}); reportErr != nil {
			logger.Error("Failed to report error to Sentry", kvp.String("error", reportErr.Error()))
		}
		statter.Counter("internal.service.error", stats.Tags{
			"service":   "snapshot-processed",
			"component": "application_setup",
		}, 1)
		return fmt.Errorf("error creating application: %w", err)
	}

	logger.Info("Application successfully set up")

	defer func() {
		if err := app.Close(); err != nil {
			logger.Error("failed to close application %s", kvp.String("error msg:", err.Error()))
		}
	}()

	c, err := consumer.New(cfg, statter, app)
	if err != nil {
		return fmt.Errorf("setup consumer: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	logger.Info(
		"snapshot-processed consumer starting",
		kvp.String("brokers", cfg.HydroKafkaBrokers),
		kvp.String("client_id", cfg.KafkaClientID),
	)

	errCh := make(chan error, 1)
	go func() {
		defer func() {
			if recovered := recover(); recovered != nil {
				tags := stats.Tags{
					"service":   "snapshot-processed",
					"component": "consumer",
				}
				statter.Counter("internal.service.panic", tags, 1)
				panic(recovered)
			}
		}()
		errCh <- c.Consume(ctx)
	}()

	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-errCh:
		// Report the consumer error to Sentry via failbotg
		if reportErr := reporter.Report(ctx, err, map[string]string{
			"service":   "snapshot-processed",
			"component": "consumer",
		}); reportErr != nil {
			logger.Error("Failed to report error to Sentry", kvp.String("error", reportErr.Error()))
		}
		statter.Counter("internal.service.error", stats.Tags{
			"service":   "snapshot-processed",
			"component": "consumer",
		}, 1)
		return fmt.Errorf("consumer error: %w", err)
	case sig := <-shutdown:
		logger.Info("shutdown signal received", kvp.String("signal", sig.String()))
		cancel()
		toCtx, toCancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer toCancel()
		<-toCtx.Done()
		logger.Info("snapshot-processed consumer shutdown complete")
		return nil
	}
}
