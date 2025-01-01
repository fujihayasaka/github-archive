// Package worker provides a worker that processes events from the aqueduct queue.
package worker

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/cryptography"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
	"go.opentelemetry.io/otel/codes"
)

// Worker pool creates worker instances which process events from the aqueduct queue.
type WorkerPool struct {
	config             *Config
	aqueductClient     aqueduct.Client
	telem              *telemetry.Telemetry
	promotionClient    promotion.IImagePromotionClient
	cryptographyClient *cryptography.CryptoClient
	allQueueNames      []string
}

type WorkerInstance = aqueduct.Worker

func NewWorkerPool(cfg *Config, promotionclient promotion.IImagePromotionClient, telem *telemetry.Telemetry) (*WorkerPool, error) {
	telem.Logger.Info("creating aqueduct client", kvp.String("addr", cfg.Aqueduct.Addr))

	aqueductClient, err := aqueduct.NewAqueductClient(&cfg.Aqueduct)
	if err != nil {
		return nil, fmt.Errorf("failed to create aqueduct client: %w", err)
	}

	cryptoClient := cryptography.NewCryptoClient(cfg.Aqueduct.EncryptionKeyList)

	return &WorkerPool{
		config:             cfg,
		aqueductClient:     aqueductClient,
		telem:              telem,
		promotionClient:    promotionclient,
		cryptographyClient: cryptoClient,
		allQueueNames:      utils.GetMapKeys(queueToJobMapping),
	}, nil
}

func (w *WorkerPool) NewWorker() (*WorkerInstance, error) {
	worker, err := aqueduct.NewWorker(
		w.aqueductClient,
		w.config.Aqueduct.AppName,
		w.allQueueNames,
		w.handler,
		aqueduct.WithLogger(w.telem.Logger),
		aqueduct.WithReceiveTimeout(w.config.JobReceiveTimeout),
		aqueduct.WithJobErrorPolicy(aqueduct.NackJobErr), // Set ACK on job failures, so that it's not redelivered
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create aqueduct worker: %w", err)
	}

	return worker, nil
}

func (w *WorkerPool) handler(ctx context.Context, rr aqueduct.ReceiveResult) error {
	queue := rr.Job.Queue
	jobLogger := utils.NewLoggerWithFields(
		w.telem.Logger,
		kvp.String("queue", queue),
		kvp.String("job_id", rr.Job.ID),
	)

	jobLogger.Info("processing worker job")
	w.telem.Logger.Statter.Counter("worker.job.started", stats.Tags{"queue": queue}, 1)

	var (
		job          *workerJob
		jobResult    workerJobResult
		jobStartTime = time.Now()
	)

	jobDefinition, jobFound := queueToJobMapping[queue]
	if jobFound {
		spanCtx, span := w.telem.Tracer.Tracer.Start(ctx, fmt.Sprintf("Worker.%s", jobDefinition.jobName))
		defer span.End()

		job = &workerJob{
			logger:          jobLogger,
			receiveResult:   rr,
			maxRetriesCount: jobDefinition.maxRetriesCount,
		}

		jobResult = jobDefinition.handler(spanCtx, w, job)
		if !jobResult.Succeeded {
			span.SetStatus(codes.Error, jobResult.Result.Error())
		}
	} else {
		job = &workerJob{logger: jobLogger}
		jobResult = job.nonRetryableErrorResult(fmt.Errorf("failed to process worker job from unknown queue"))
	}

	if jobResult.ShouldRetry {
		if err := w.queueJobRetry(ctx, job); err != nil {
			return fmt.Errorf("failed to queue job retry: %w", err)
		}
	}

	statterTags := stats.Tags{
		"queue":      queue,
		"result":     fmt.Sprint(jobResult.Succeeded),
		"attempt":    fmt.Sprint(job.getCurrentAttempt()),
		"will_retry": fmt.Sprint(jobResult.ShouldRetry),
	}
	w.telem.Stats.Counter("worker.job.finished", statterTags, 1)
	w.telem.Stats.DistributionMs("worker.job.duration", statterTags, time.Since(jobStartTime))

	return jobResult.Result
}

func (w *WorkerPool) queueJobRetry(ctx context.Context, workerJob *workerJob) error {
	// add retry attempt header
	currentAttempt := workerJob.getCurrentAttempt()
	headers := map[string]string{
		retryAttemptHeader: fmt.Sprintf("%d", currentAttempt+1),
	}

	// calculate new deliverAt based on retry attempt
	baseBackoff := float64(w.config.RetriesBaseBackoff)
	baseFactor := w.config.RetriesExponentialFactor
	factor := math.Pow(baseFactor, float64(currentAttempt))
	backoff := time.Duration(baseBackoff * factor)
	deliverAt := time.Now().Add(backoff)

	job := aqueduct.Job{
		App:       workerJob.receiveResult.App,
		Queue:     workerJob.receiveResult.Queue,
		Payload:   workerJob.receiveResult.Payload,
		Headers:   headers,
		DeliverAt: deliverAt,
	}

	if _, err := w.aqueductClient.Send(ctx, job); err != nil {
		return fmt.Errorf("failed to send job to aqueduct for retry: %w", err)
	}

	return nil
}

func (w *WorkerPool) decryptString(encryptedString []byte, salt []byte) (string, error) {
	decryptedString, err := w.cryptographyClient.Decrypt(encryptedString, salt)
	if err != nil {
		return "", fmt.Errorf("failed to decrypt string: %w", err)
	}

	return string(decryptedString), nil
}
