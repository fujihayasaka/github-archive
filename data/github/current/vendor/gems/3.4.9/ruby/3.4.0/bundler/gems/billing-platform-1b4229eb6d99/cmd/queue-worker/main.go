package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/lib/azure/kusto"
	"github.com/github/billing-platform/lib/azurecommerce"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/data"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/hydro"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/messaging/handlers"
	"github.com/github/billing-platform/lib/messaging/handlers/rollups"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	ctxutil "github.com/github/go-ctxutil"
	"go.uber.org/ratelimit"

	exceptions "github.com/github/go-exceptions"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

func main() {
	if err := realMain(); err != nil {
		fmt.Printf(" failed to run service: %v\n", err)
		os.Exit(1)
	}
}

func realMain() error {
	ctx := context.Background()
	ctx, stop := signal.NotifyContext(ctx, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return errors.Wrap(err, "failed loading config")
	}

	if err = cfg.ValidateWorkerConfig(); err != nil {
		return errors.Wrap(err, "failed validating worker config")
	}

	errorReporter, err := cfg.NewExceptionReporter()
	if err != nil {
		return errors.Wrap(err, "failed configuring exception reporter")
	}

	telem, err := telemetry.NewFromEnv()
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return errors.Wrap(err, "failed configuring telemetry")
	}
	defer func() {
		if err := telem.Shutdown(context.Background()); err != nil {
			_ = errorReporter.Report(ctx, err, nil)
			fmt.Printf("failed to shutdown telemetry: %v\n", err)
		}
	}()

	logger := cfg.ConfigureLogger(telem.Logger, "BillingPlatformWorker")
	logger.Info("initializing service",
		kvp.Int("net.host.port", cfg.HTTPPort),
		kvp.String("db.cosmosdb.container", cfg.ContainerName),
		kvp.String("db.cosmosdb.database", cfg.DatabaseName),
		kvp.String("db.cosmosdb.host", cfg.DatabaseEndPoint),
		kvp.String("db.cosmosdb.gateway_host", cfg.GatewayDatabaseEndPoint),
	)

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.Environment, "service": "queue-worker", "worker_type": cfg.CurrentWorkerType().String()})

	logger.Info("starting statsd client")
	statter.Run()
	defer statter.Stop()

	tracer := telem.Tracer.Tracer

	logger.Info("initializing feature flag client")
	flagger, err := featureflags.NewClient(ctx, cfg, logger, statter)
	if err != nil {
		logger.Error("failed to create feature flag client", kvp.String("error", err.Error()))
		_ = errorReporter.Report(ctx, err, nil)
	}

	statter.Counter("consumer.start", stats.Tags{"consumer": "billing-rollups"}, 1)

	logger.Info("initializing messaging client")
	client, err := messaging.NewMessagingClient(ctx, cfg, statter)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return fmt.Errorf("error creating client: %w", err)
	}

	logger.Info("initializing database client")
	readWriteDB := db.NewDatabase(cfg, logger, statter, tracer)

	logger.Info("initializing hydro publisher")
	hydroPublisher, err := hydro.NewHydroPublisher(ctx, cfg, logger)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return fmt.Errorf("error creating hydro publisher: %w", err)
	}

	logger.Info("initializing monolith client")
	monolithClient, err := cfg.NewMonolithClient(ctx)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}

	var handler interfaces.MessageHandler
	workerType := cfg.CurrentWorkerType()

	logger.Info("initializing engines")
	engineParams := engines.NewEngineParams(client, cfg, readWriteDB, flagger, statter, monolithClient, tracer)
	totalsPatching := engines.NewTotalPatchingEngine(engineParams)
	handlerParams := handlers.NewHandlerParams(client, cfg, readWriteDB, statter, tracer, flagger, totalsPatching)

	adminEngine := engines.NewAdminEngine(engineParams)
	azureEmissionEngine := engines.NewAzureEmissionEngine(engineParams)
	customerEngine := engines.NewCustomerEngine(engineParams)
	invoiceEngine := engines.NewInvoiceEngine(engineParams)
	pricingEngine := engines.NewPricingEngine(engineParams)
	costCenterEngine := engines.NewCostCenterEngine(engineParams, pricingEngine, customerEngine)
	productEngine := engines.NewProductEngine(engineParams)
	usageEngine := engines.NewUsageEngine(engineParams)
	subscriptionsEngine := engines.NewSubscriptionsEngine(engineParams, totalsPatching, logger)
	usageReportEngine := engines.NewUsageReportEngine(engineParams)
	zuoraEngine := engines.NewZuoraEngine(engineParams, zuora.NewClient(cfg.ZuoraApiURL, cfg.ZuoraClientID, cfg.ZuoraClientSecret, logger), costCenterEngine, invoiceEngine, productEngine)
	budgetEngine := engines.NewBudgetEngine(engineParams, customerEngine)
	discountEngine := engines.NewDiscountEngine(engineParams, pricingEngine, subscriptionsEngine)
	dataService := data.NewDataService(hydroPublisher, usageEngine, costCenterEngine, discountEngine, logger, statter)

	switch workerType {
	case models.WorkerTypeUsageIngestion:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [UsageIngestion]")
		handler = handlers.NewUsageHandler(handlerParams, costCenterEngine, customerEngine, invoiceEngine, pricingEngine, hydroPublisher, subscriptionsEngine, productEngine, usageEngine, discountEngine, budgetEngine)
	case models.WorkerTypeCustomerDailyRollup:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [CustomerDailyRollup]")
		handler = rollups.NewCustomerDailyRollupHandler(handlerParams)
	case models.WorkerTypeCustomerMonthlyRollup:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [CustomerMonthlyRollup]")
		handler = rollups.NewCustomerMonthlyRollupHandler(handlerParams)
	case models.WorkerTypeCustomerYearlyRollup:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [CustomerYearlyRollup]")
		handler = rollups.NewCustomerYearlyRollupHandler(handlerParams)
	case models.WorkerTypeAzureEmission:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [AzureEmission]")
		ac := azurecommerce.NewAzureCommerceClient()
		handler = handlers.NewAzureEmissionHandler(handlerParams, ac, customerEngine, costCenterEngine, azureEmissionEngine, usageEngine, dataService, discountEngine)
	case models.WorkerTypeEmissionHandler:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [EmissionHandler]")
		handler = handlers.NewEmissionHandler(handlerParams, customerEngine, costCenterEngine, usageEngine, zuoraEngine)
	case models.WorkerTypeWatermarkHandler:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [WatermarkHandler]")
		handler = handlers.NewWatermarkHandler(handlerParams, customerEngine, usageEngine, pricingEngine, discountEngine, monolithClient)
	case models.WorkerTypeInvoiceGeneration:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [InvoiceGeneration]")
		zuoraClient := zuora.NewClient(cfg.ZuoraApiURL, cfg.ZuoraClientID, cfg.ZuoraClientSecret, logger)
		zuoraEngine := engines.NewZuoraEngine(engineParams, zuoraClient, costCenterEngine, invoiceEngine, productEngine)
		handler = handlers.NewInvoiceGenerationHandler(handlerParams, customerEngine, invoiceEngine, productEngine, usageEngine, zuoraEngine, hydroPublisher, costCenterEngine, discountEngine)
	case models.WorkerTypeRequestHandler:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [RequestHandler]")
		handler = handlers.NewRequestHandler(handlerParams, adminEngine, azureEmissionEngine, invoiceEngine, usageEngine, usageReportEngine, pricingEngine, zuoraEngine)
	case models.WorkerTypeUsageReport:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [UsageReport]")

		kustoService, err := kusto.New(cfg, statter, logger)
		if err != nil {
			return err
		}

		handler = handlers.NewUsageReportHandler(handlerParams, usageReportEngine, kustoService, hydroPublisher)
	case models.WorkerTypeUsageReportFanOut:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [UsageReportFanOut]")
		handler = handlers.NewUsageReportFanOutHandler(handlerParams, usageReportEngine)
	case models.WorkerTypeCustomerAzureEmissionDailyRollup:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [CustomerAzureEmissionDailyRollup]")
		handler = rollups.NewCustomerAzureEmissionDailyRollupHandler(handlerParams)
	case models.WorkerTypeCustomerZuoraEmissionDailyRollup:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [CustomerZuoraEmissionDailyRollup]")
		handler = rollups.NewCustomerZuoraEmissionDailyRollupHandler(handlerParams)
	case models.WorkerTypeZeroOutQuantities:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [ZeroOutQuantities]")
		handler = handlers.NewZeroOutQuantitiesHandler(handlerParams, usageEngine)
	case models.WorkerTypeHighWatermarkRolloverHandler:
		handler = handlers.NewHighWatermarkRolloverHandler(handlerParams, usageEngine, subscriptionsEngine)
	case models.WorkerTypeFailedRollups:
		handler = handlers.NewFailedRollupHandler(handlerParams)
	case models.WorkerTypeDiscountStateUpdate:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [DiscountStateUpdate]")
		handler = handlers.NewDiscountStateHandler(handlerParams, discountEngine)
	case models.WorkerTypeThrottledWatermark:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [ThrottledWatermark]")
		handler = handlers.NewThrottledWatermarkHandler(handlerParams)
	case models.WorkerTypeZuoraBatchEmissionHandler:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [ZuoraBatchEmissionHandler]")
		handler = handlers.NewZuoraBatchEmissionHandler(handlerParams, zuoraEngine, hydroPublisher, productEngine, costCenterEngine, discountEngine, customerEngine)
	case models.WorkerTypeBulkUsageEmission:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [WorkerTypeBulkUsageEmission]")
		handler = handlers.NewBulkUsageEmissionsHandler(handlerParams)
	case models.WorkerTypeBudgetState:
		logger = cfg.ConfigureLogger(telem.Logger, "Worker [BudgetState]")
		handler = handlers.NewBudgetStateHandler(handlerParams, budgetEngine, hydroPublisher)
	default:
		return fmt.Errorf("unknown worker type: %s", workerType)
	}

	logger.Info("queue-worker type selected", kvp.String("gh.billing_platform.worker_type", string(workerType)))

	// Wrap the ProcessMessage function defined by the handler so we can gather and report metrics
	messageHandler := func(ctx context.Context, rr aqueduct.ReceiveResult) error {
		timeNow := time.Now()
		// tracer.Start() sets tracing fields into the context.
		ctx, sp := tracer.Start(ctx, fmt.Sprintf("queue_worker:%s", handler.ReceiveQueueName()))
		// Create a new logger here to ensure all log messages within the handler contain tracing fields.
		isLastAttempt := rr.DeliveryAttempt == rr.MaxDeliveryAttempts
		logger := logger.WithContext(ctx).WithFields(
			kvp.String("aqueduct.job.id", rr.Job.ID),
			kvp.String("aqueduct.job.queue", rr.Queue),
			kvp.Int("aqueduct.job.delivery_attempt", rr.DeliveryAttempt),
			kvp.Int("aqueduct.job.max_delivery_attempt", rr.MaxDeliveryAttempts),
			kvp.Bool("aqueduct.delivery.last", isLastAttempt),
			kvp.String("receive_queue_name", handler.ReceiveQueueName()),
		)
		logger.Info("begin processing message", kvp.String("gh.aqueduct.queue.name", handler.ReceiveQueueName()))

		// Process the message using the handler
		err := handler.ProcessMessage(ctx, logger, rr)
		if err != nil {
			logger.WithError(err).Error("error from handler", kvp.String("queue", handler.ReceiveQueueName()), kvp.Bool("aqueduct_last_redelivery", isLastAttempt), kvp.String("aqueduct.job.id", rr.Job.ID))
			if isLastAttempt {
				tags := map[string]string{"queue": handler.ReceiveQueueName(), "aqueduct_last_redelivery": strconv.FormatBool(isLastAttempt), "aqueduct.job.id": rr.Job.ID}
				if reportErr := errorReporter.Report(ctx, err, tags); reportErr != nil {
					logger.WithError(reportErr).Error(fmt.Sprintf("error reporting %s", err.Error()))
				}
			}
		}

		// End the span and record metrics
		sp.End()
		statter.Timing("queue_worker.process_message", stats.Tags{
			"queue_name":               handler.ReceiveQueueName(),
			"success":                  strconv.FormatBool(err == nil),
			"aqueduct_last_redelivery": strconv.FormatBool(isLastAttempt),
		}, time.Since(timeNow))

		return err
	}

	// Create the aqueduct worker
	logger.Info("initializing aqueduct worker")
	worker, err := messaging.NewMessagingHandler(ctx, client, cfg, logger, statter, handler.ReceiveQueueName(), messageHandler)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return fmt.Errorf("error creating worker: %w", err)
	}

	// set up readiness probe for k8s to check pod is alive
	logger.Info("creating readiness probe")
	if err = messaging.CreateReadinessProbeFile(); err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return fmt.Errorf("error creating readines probe: %w", err)
	}

	if !cfg.RunLimited {
		logger.Info("Starting new queue worker", kvp.String("gh.billing_platform.worker_type", string(workerType)))
		rateLimitingEnabled := workerType == models.WorkerTypeThrottledWatermark
		runWorkers(worker, rateLimitingEnabled, cfg, ctx, logger, errorReporter)
	} else {
		logger.Info("Starting new queue worker for testing", kvp.String("gh.billing_platform.worker_type", string(workerType)))
		return runForTesting(logger, worker, ctx, cfg, handler)
	}

	return nil
}

func runForTesting(logger log.Logger, worker *aqueduct.Worker, ctx context.Context, cfg *config.Config, handler interfaces.MessageHandler) error {
	num := cfg.NumberOfLimitedMessagesToProcess
	logger.Info(fmt.Sprintf("running limited for %d messages", num))
	for i := 0; i < num; i++ {
		_ = worker.ProcessJob(ctx)
		// aqueduct client doesn't return an error, it deals with it internally
		// this is a hacky workaround. TODO: fix this
		processJobError := handler.GetProcessJobError()
		if processJobError != nil {
			logger.WithError(processJobError).Error("error processing job")
			return processJobError
		}
		logger.Info(fmt.Sprintf("processed job for message %d", i+1))
	}
	return nil
}

func runWorkers(worker *aqueduct.Worker, rateLimitingEnabled bool, cfg *config.Config, ctx context.Context, logger log.Logger, errorReporter *exceptions.Reporter) {
	// passing a new "delayed" context to ProcessJob so that we can wait for the message to be processed
	delayedCtx, cancel := ctxutil.DelayedCancel(ctx, 70*time.Second)
	defer cancel()

	rateLimiter := ratelimit.New(cfg.ThrottledWatermarkItemsPerSecond)
	var wg sync.WaitGroup
	process := func() {
		defer wg.Done()
		for {
			select {
			case <-ctx.Done():
				logger.Info("Context cancelled - shutting down the worker")
				return
			default:
				if rateLimitingEnabled {
					_ = rateLimiter.Take()
				}
				err := worker.ProcessJob(delayedCtx)
				if err != nil {
					logger.WithError(err).Error("error processing job")
					_ = errorReporter.Report(context.Background(), err, nil)
				}
			}
		}
	}

	wg.Add(32)
	for i := 0; i < 32; i++ {
		go process()
	}

	wg.Wait()
	logger.Info("All workers have exited - shutting down")
}
