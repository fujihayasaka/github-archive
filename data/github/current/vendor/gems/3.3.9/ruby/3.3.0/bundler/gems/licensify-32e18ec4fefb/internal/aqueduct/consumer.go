package aqueduct

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-ctxutil"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/aqueduct/handlers"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/interfaces"
	"github.com/github/licensify/internal/monolith"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"go.opentelemetry.io/otel/trace"
	"golang.org/x/sync/errgroup"
)

const consumerContextCancelDelay = 40 * time.Second

// Consumer creates workers to consume aqueduct messages.
type Consumer struct {
	cfg                *config.Config
	app                string
	queues             []string
	client             aqueduct.Client
	workerCount        int
	dbConnection       *cosmos.DatabaseConnection
	monolithClient     *monolith.Client
	eventHandler       *eventhandlers.EventHandler
	hydroPublisher     interfaces.HydroPublisher
	featureFlagsClient twirpFeatures.FeaturesAPI
}

// NewConsumer creates a new aqueduct consumer.
func NewConsumer(client aqueduct.Client, app string, queues []string, workerCount int,
	dbConnection *cosmos.DatabaseConnection, cfg *config.Config, monolithClient *monolith.Client,
	eventHandler *eventhandlers.EventHandler, hydroPublisher interfaces.HydroPublisher, featureFlagsClient twirpFeatures.FeaturesAPI) *Consumer {
	return &Consumer{
		cfg:                cfg,
		app:                app,
		queues:             queues,
		client:             client,
		workerCount:        workerCount,
		dbConnection:       dbConnection,
		monolithClient:     monolithClient,
		eventHandler:       eventHandler,
		hydroPublisher:     hydroPublisher,
		featureFlagsClient: featureFlagsClient,
	}
}

// Start creates and starts all of the workers.
func (c *Consumer) Start(ctx context.Context, logger log.Logger, statter stats.Client, errorReporter *exceptions.Reporter, tracer trace.Tracer) error {
	wrapHandler := func(workerID int) func(context.Context, aqueduct.ReceiveResult) error {
		return func(ctx context.Context, rr aqueduct.ReceiveResult) error {
			timeNow := time.Now()
			ctx, sp := tracer.Start(ctx, fmt.Sprintf("queue_worker:%s", rr.Queue))

			var err error
			var jobName string
			var topic string
			defer func() {
				sp.End()

				success := err == nil
				finalAttempt := rr.DeliveryAttempt == rr.MaxDeliveryAttempts
				failedFinalAttempt := finalAttempt && !success

				statter.Timing("queue_worker.process_message", stats.Tags{
					"queue_name":    rr.Queue,
					"job_name":      jobName,
					"success":       strconv.FormatBool(success),
					"final_attempt": strconv.FormatBool(finalAttempt),
				}, time.Since(timeNow))

				if failedFinalAttempt {
					tags := map[string]string{
						"gh.aqueduct.job.id":       rr.ID,
						"gh.aqueduct.queue.name":   rr.Queue,
						"gh.aqueduct.job.name":     jobName,
						"gh.hydro.msg.topic":       topic,
						"gh.aqueduct.job.attempts": strconv.Itoa(rr.DeliveryAttempt),
					}
					if reportErr := errorReporter.Report(ctx, fmt.Errorf("job completely failed"), tags); reportErr != nil {
						logger.WithError(reportErr).Error(fmt.Sprintf("failed to report error: %s", err.Error()))
					}
				}
			}()

			jobName = rr.Job.Headers[jobs.JobNameHeader]
			topic = rr.Job.Headers["topic"]

			logger := logger.WithContext(ctx).WithFields(
				kvp.Int("gh.aqueduct.worker_id", workerID),
				kvp.String("gh.aqueduct.job.id", rr.ID),
				kvp.String("gh.aqueduct.job.name", jobName),
				kvp.Int("gh.aqueduct.job.attempts", rr.DeliveryAttempt),
				kvp.Int("gh.aqueduct.job.max_attempts", rr.MaxDeliveryAttempts),
				kvp.String("gh.aqueduct.queue.name", rr.Queue),
			)

			logger.Info("begin processing aqueduct message")

			if topic != "" {
				logger = logger.WithFields(kvp.String("gh.hydro.msg.topic", topic))
				err = c.eventHandler.HandleRaw(ctx, logger, rr.Job.Payload, topic)
			} else {
				var jobProcessor jobs.JobProcessor

				customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, c.dbConnection)
				licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(statter, tracer, c.dbConnection)
				customerEngine := engines.NewCustomerEngine(statter, tracer, c.dbConnection)
				jobby := &jobs.Jobby{Cfg: c.cfg, AqueductClient: c.client}

				switch jobName {
				case jobs.JobNameProductEnablementUpdated:
					productEnablementEngine := engines.NewProductEnablementEngine(statter, tracer, c.dbConnection)
					jobProcessor = handlers.NewProductEnablementUpdatedHandler(productEnablementEngine, statter, tracer)
				case jobs.JobNameSyncOrgMemberships:
					jobProcessor = handlers.NewSyncOrgMembershipsHandler(customerEngine, customerLicenseEngine, licenseeLicenseEngine, c.monolithClient, statter, tracer)
				case jobs.JobNameDeleteEnablements:
					jobProcessor = handlers.NewDeleteEnablementsHandler(statter, tracer, customerLicenseEngine, licenseeLicenseEngine, customerEngine)
				case jobs.JobNameCreateRepositoryCollaborators:
					jobProcessor = handlers.NewCreateRepositoryCollaboratorsHandler(statter, tracer, c.monolithClient, customerLicenseEngine, licenseeLicenseEngine)
				case jobs.JobNameBackfillLicenseStatus:
					jobProcessor = handlers.NewBackfillLicenseStatusHandler(statter, tracer, c.dbConnection, customerLicenseEngine, licenseeLicenseEngine)
				case jobs.JobNameScheduleEmissions:
					jobProcessor = handlers.NewScheduleEmissionsHandler(c.cfg, customerEngine, jobby, statter, tracer)
				case jobs.JobNamePublishEmission:
					jobProcessor = handlers.NewPublishEmissionHandler(c.cfg, customerEngine, customerLicenseEngine, c.featureFlagsClient, c.hydroPublisher, statter, tracer)
				default:
					return fmt.Errorf("unknown job name: %q", jobName)
				}

				err = jobProcessor.ProcessMessage(ctx, logger, rr)
			}

			if err != nil {
				tags := map[string]string{
					"gh.aqueduct.job.id":     rr.ID,
					"gh.aqueduct.queue.name": rr.Queue,
					"gh.aqueduct.job.name":   jobName,
					"gh.hydro.msg.topic":     topic,
				}
				if reportErr := errorReporter.Report(ctx, err, tags); reportErr != nil {
					logger.WithError(reportErr).Error(fmt.Sprintf("failed to report error: %s", err.Error()))
				}
			}
			return err
		}
	}

	// passing a new "delayed" context to ProcessJob so that we can wait for the message to be processed
	delayedCtx, cancel := ctxutil.DelayedCancel(ctx, consumerContextCancelDelay)
	defer cancel()

	grp, _ := errgroup.WithContext(delayedCtx)
	for i := range c.workerCount {
		grp.Go(func() error {
			logger.Debug(fmt.Sprintf("creating worker %d", i))
			worker, err := NewWorker(
				c.client,
				wrapHandler(i),
				c.app,
				c.queues,
				logger,
				statter,
			)
			if err != nil {
				_ = errorReporter.Report(delayedCtx, err, nil)
				return fmt.Errorf("failed to create aqueduct worker: %w", err)
			}

			// wait on the parent signal context before ending the worker
			for ctx.Err() == nil {
				// use the delayed context to let the worker finish processing
				// before shutdown
				err := worker.ProcessJob(delayedCtx)
				if err != nil {
					logger.WithError(err).Error("error processing job")
					_ = errorReporter.Report(delayedCtx, err, nil)
				}
			}
			return nil
		})
	}

	err := grp.Wait()
	if err != nil {
		return fmt.Errorf("failed to run workers: %w", err)
	}

	logger.Info("shutting down aqueduct consumer")
	return nil
}
