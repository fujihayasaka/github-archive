// Package consumer provides functionality to run Aqueduct worker pools and job consumers.
package consumer

import (
	"context"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"go.opentelemetry.io/otel/codes"
)

// Run starts an Aqueduct worker pool with the specified configuration.
// It returns a function that can be called to run the pool.
//
// ctx should be a context that is cancelled when the application is shutting down.
func Run(
	ctx context.Context,
	cfg *config.Config,
	obsv observability.Exporters,
	limiter limiter.RateLimiter,
	aqueductClient sweagentd.AqueductClient,
	ffClient featureflags.Client,
	pool PoolName,
	queues []string,
	handler aqueduct.JobHandler,
	failJob jobs.FailJobFunc,
) func() error {
	return func() error {
		newctx, span := obsv.Tracer.Start(ctx, "aqueduct.consumer.Run")
		defer span.End()

		options := []PoolOption{
			WithWorkerCount(cfg.AqueductWorkerCount),
			WithHeartbeatInterval(30 * time.Second),
			WithHeartbeatTimeout(60 * time.Second),
			WithQueues(queues),
			WithEnvironmentPoolName(cfg.EnvironmentName, pool),
			WithHandler(jobs.Handler(obsv, aqueductClient, ffClient, limiter, handler, failJob)),
			WithBeforeReceiveHook(jobs.BeforeReceive(obsv, ffClient, limiter, jobs.DefaultReceiveHook)),
			WithErrorHook(jobs.OnError(obsv)),
		}

		pool, err := NewWorkerPool(
			newctx,
			obsv,
			aqueductClient,
			options...)
		if err != nil {
			// Make the error special
			err = goerrors.Errorf("failed to create Aqueduct worker pool: %w", err)
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())

			obsv.Logger.WithError(err).Error("Error initializing Aqueduct worker pool")
			return err
		}

		// wait for the shutdown context to be done then call shutdown
		go func() {
			<-ctx.Done()
			shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 20*time.Second)
			defer cancel()
			err := pool.Shutdown(shutdownCtx)
			if err != nil {
				obsv.Logger.WithError(err).Error("Error shutting down Aqueduct worker pool")
			}
		}()

		err = pool.Start()
		if err != nil {
			err = goerrors.Errorf("failed to start Aqueduct worker pool: %w", err)
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())
			obsv.Logger.WithError(err).Error("Error starting Aqueduct worker pool")
			return err
		}

		obsv.Logger.Info("Aqueduct worker pool initialized successfully")
		return nil
	}
}
