// Package cronjob contains the logic for setup and teardown of jobs.
package cronjob

import (
	"context"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/turboscan/ts/appctx"
	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/o11y"
)

// JobFunc is the type of the function that runs a job. It is expected to be a self contained execution unit of work.
type JobFunc func(ctx context.Context, cfg *config.Config) error

// Execute runs the given job function with the given name. It sets up observability and exception handling.
// It returns an error if the job function returns an error.
// The name is used for observability and exception handling.
// The job function is expected to be a self contained execution unit of work.
// The job function is expected to use the config, logger and statsClient provided to log, report exceptions
// and emit metrics.
func Execute(name string, f JobFunc) error {
	signalCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	return appctx.WithContext(cfg, name, func(ctx context.Context) error {
		ctx = appctx.WithShutdown(ctx, signalCtx.Done())
		ctx = appctx.With(ctx,
			kvp.String("gh.turboscan."+name, "true"),
			kvp.String("gh.turboscan.env", cfg.Environment),
		)

		ctx, _ = o11y.NamedSpan(ctx, name)

		startTime := time.Now()
		defer func() {
			// Recover from panics and report them to Sentry/Splunk
			if panicErr := recover(); panicErr != nil {
				err := errFromPanic(panicErr)
				appctx.Report(ctx, err, nil)
				appctx.Logger(ctx).WithError(err).Error("Unexpected panic")
			}

			duration := time.Since(startTime)
			appctx.Stats(ctx).DistributionMs("scheduled_job", stats.Tags{"job": name}, duration)

			appctx.Logger(ctx).WithError(err).WithFields(
				kvp.String("gh.operation.name", name),
				kvp.Float64("gh.operation.duration", float64(duration)),
			).Info(name + " completed.")
		}()

		err = f(ctx, cfg)
		if err != nil {
			appctx.Report(ctx, err, nil)
			appctx.Logger(ctx).WithError(err).Error("Unexpected error")
			return err
		}
		return nil
	})
}

// errFromPanic returns the typed error if the recovered panic is an error, otherwise formats as error.
func errFromPanic(p interface{}) error {
	if err, ok := p.(error); ok {
		return err
	}
	return errors.Errorf("panic: %v", p)
}
