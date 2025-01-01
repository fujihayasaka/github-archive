package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/utils"
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

	telem, err := telemetry.InitializeTelemetry(ctx, &cfg.Telemetry)
	if err != nil {
		return fmt.Errorf("failed to initialize telemetry: %w", err)
	}
	defer telem.Shutdown(ctx)

	err = featureflags.SetupNewGlobalFeatureFlagsClient(ctx, &cfg.FeatureFlags)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize feature flags client", err)
		return err
	}

	// initialize  db stores
	imagesStore, err := store.NewImagesStoreWithMySQLConnection(&cfg.MySQL)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize database connection", err)
		return err
	}

	// initialize promotion client
	promotionClient, err := promotion.NewImagePromotionClient(ctx, &cfg.Worker.Aqueduct, &cfg.Azure, &cfg.MCP, &cfg.TwirpServer.JWTConfig, imagesStore)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize promotion client", err)
		return err
	}

	logger.Info(ctx, "worker service initialized")

	// Create a new worker pool
	workerPool, err := worker.NewWorkerPool(ctx, &cfg.Worker, promotionClient)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to create a worker pool", err)
		return err
	}

	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	ctx, ctxCancel := context.WithCancel(ctx)

	go func() {
		<-shutdown
		logger.Info(ctx, "received shutdown signal")
		close(shutdown)
		ctxCancel()
	}()

	var wg sync.WaitGroup

	// Add worker instances to the worker pool
	for i := 0; i < cfg.Worker.PoolSize; i++ {
		w, err := workerPool.NewWorker()
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to create a new worker instance in worker pool", err)
			continue
		}

		workerCtx := stash.WithLoggingFields(ctx, kvp.String("worker_id", w.ID))

		wg.Add(1)

		go func(w *worker.WorkerInstance) {
			defer wg.Done()

			logger.Info(workerCtx, "created worker instance")

			for {
				select {
				case <-workerCtx.Done():
					logger.Info(workerCtx, "worker instance shutting down")
					return
				default:
					logger.Debug(workerCtx, "worker instance requesting job")

					if err := w.ProcessJob(workerCtx); err != nil {
						logger.WithError(err).Error(workerCtx, "failed to process job")
					}
				}
			}
		}(w)
	}

	// This is used to signal to Kube that the worker service has started and is ready to process jobs
	// via the readiness probe
	err = utils.WriteStartupCompletionFlag()
	if err != nil {
		logger.WithError(err).Error(ctx, "failed to create startup completion file")
		return err
	} else {
		logger.Info(ctx, "created startup completion file, signaling readiness to kube")
	}

	wg.Wait()

	logger.Info(ctx, "shutting down worker service")

	return nil
}
