package main

import (
	"context"
	"os"

	"github.com/pkg/errors"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/notifier"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

func main() {
	if err := realMain(); err != nil && !errors.Is(err, context.Canceled) {
		log.WithError(err).Error("failed to run job")
		os.Exit(1)
	}
}

func realMain() error {
	cfg, err := notifier.NewConfigFromEnvironment()
	if err != nil {
		return err
	}

	ctx, err := cfg.NewRootContext()
	if err != nil {
		diagnostics.ReportError(ctx, err, "an error occurred creating the root context", map[string]string{})
		return err
	}

	defer func() {
		if r := recover(); r != nil {
			// An error reporting the error isn't really actionable since we don't have anywhere to report it.
			diagnostics.ReportError(ctx, r, "unhandled panic", map[string]string{})
			panic(r)
		}
	}()

	job, err := notifier.NewJob(ctx, cfg)
	if err != nil {
		diagnostics.ReportError(ctx, err, "an error occurred starting the notifier job", map[string]string{})
		return err
	}

	// add the job ID to the logger
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.notifier.job.id", notifier.JobID))

	err = job.Run(ctx)
	if err != nil {
		diagnostics.ReportError(ctx, err, "an error occurred running the notifier job", map[string]string{})
		return err
	}

	return nil
}
