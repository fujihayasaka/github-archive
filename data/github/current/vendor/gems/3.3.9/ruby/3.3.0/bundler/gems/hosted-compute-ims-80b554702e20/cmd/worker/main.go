package main

import (
	"context"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/resources"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/worker"
)

func main() {
	if err := realMain(); err != nil {
		panic(err)
	}
}

func realMain() error {
	ctx := context.Background()

	// load app config
	cfg := &config.Config{}
	if err := cfg.Load(); err != nil {
		return err
	}

	// initialize telemetry
	telem, err := telemetry.NewTelemetry(ctx, cfg.ServiceName, cfg.Telemetry)
	if err != nil {
		return err
	}

	defer telem.Shutdown(ctx)
	logger := telem.Logger

	err = featureflags.SetupNewGlobalFeatureFlagsClient(ctx, &cfg.FeatureFlags, logger)
	if err != nil {
		logger.ErrorWithReport("failed to initialize feature flags client", err)
		return err
	}

	// initialize  db stores
	imagesStore, err := store.NewImagesStoreWithMySQLConnection(&cfg.MySQL, telem.Logger, telem.Stats)
	if err != nil {
		logger.ErrorWithReport("failed to initialize database connection", err)
		return err
	}

	// initialize azure client
	azureClient, err := azure.NewAzureClient(&cfg.Azure, logger)
	if err != nil {
		logger.ErrorWithReport("failed to initialize azure client", err)
		return err
	}

	// initialize promotion client
	resourceManager := resources.NewManager(cfg.Resources, imagesStore, logger)

	promotionClient, err := promotion.NewImagePromotionClient(&cfg.Worker.Aqueduct, azureClient, imagesStore, resourceManager)
	if err != nil {
		logger.ErrorWithReport("failed to initialize promotion client", err)
		return err
	}

	logger.Info("worker service initialized")

	// Create a new worker pool
	workerPool, err := worker.NewWorkerPool(&cfg.Worker, promotionClient, telem)
	if err != nil {
		logger.ErrorWithReport("failed to create a worker pool", err)
		return err
	}

	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	ctx, ctxCancel := context.WithCancel(ctx)

	go func() {
		<-shutdown
		logger.Info("received shutdown signal")
		close(shutdown)
		ctxCancel()
	}()

	var wg sync.WaitGroup

	// Add worker instances to the worker pool
	for i := 0; i < cfg.Worker.PoolSize; i++ {
		w, err := workerPool.NewWorker()
		if err != nil {
			logger.ErrorWithReport("failed to create a new worker instance in worker pool", err)
			continue
		}

		wg.Add(1)

		go func(w *worker.WorkerInstance) {
			defer wg.Done()

			workerLogger := logger.WithFields(kvp.String("worker_id", w.ID))
			workerLogger.Info("created worker instance")

			for {
				select {
				case <-ctx.Done():
					workerLogger.Info("worker instance shutting down")
					return
				default:
					workerLogger.Debug("worker instance requesting job")

					if err := w.ProcessJob(ctx); err != nil {
						workerLogger.WithError(err).Error("failed to process job")
					}
				}
			}
		}(w)
	}

	wg.Wait()

	logger.Info("shutting down worker service")

	return nil
}
