// Check Deletion Cycle cleanup deletes old checks,
package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/config"
)

const thirtyDays = 30 * 24 * time.Hour

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "check deletion cycle failed failed: %v\n", err) //nolint:revive // unhandled-error: already in an error condition
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
	logger := tele.Logger.Named("check-deletion-cycle-job")

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
				"service": "check-deletion-cycle",
			}
			statter.Counter("internal.service.panic", tags, 1)
			panic(recovered)
		}
	}()

	app, err := application.New(cfg, logger, statter)
	if err != nil {
		// Report the error to Sentry via failbotg
		if reportErr := reporter.Report(ctx, err, map[string]string{
			"service":   "check-deletion-cycle",
			"component": "application_setup",
		}); reportErr != nil {
			logger.Error("Failed to report error to Sentry", kvp.String("error", reportErr.Error()))
		}
		statter.Counter("internal.service.error", stats.Tags{
			"service":   "check-deletion-cycle",
			"component": "application_setup",
		}, 1)
		return fmt.Errorf("error creating application: %w", err)
	}

	defer func() {
		if err := app.Close(); err != nil {
			logger.Error("failed to close application %s", kvp.String("error msg:", err.Error()))
		}
	}()

	logger.Info("Application successfully set up")

	logger.Info("Starting deletion of 30 day old checks")

	deletedCount, err := app.Subsystems.Storage.DeleteCheckJobsStartedBefore(context.Background(), thirtyDays)
	if err != nil {
		// Report the error to Sentry via failbotg
		if reportErr := reporter.Report(ctx, err, map[string]string{
			"service":   "check-deletion-cycle",
			"component": "delete_old_checks",
		}); reportErr != nil {
			logger.Error("Failed to report error to Sentry", kvp.String("error", reportErr.Error()))
		}
		statter.Counter("internal.service.error", stats.Tags{
			"service":   "check-deletion-cycle",
			"component": "delete_old_checks",
		}, 1)
		logger.Error("error deleting old checks: %s", kvp.String("error msg:", err.Error()))
		return fmt.Errorf("error deleting old checks: %w", err)
	}

	logger.Info("Successfully deleted old checks", kvp.Int64("deleted_count", deletedCount))
	return nil
}
