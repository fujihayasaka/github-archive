// Package worker provides a worker that processes events from the aqueduct queue.
package worker

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-core/cryptography"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/github/hosted-compute-ims/internal/telemetry/tracer"
	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
	"github.com/github/hosted-compute-ims/internal/worker/queue"
	"go.opentelemetry.io/otel/codes"
)

// Worker pool creates worker instances which process events from the aqueduct queue.
type WorkerPool struct {
	config             *Config
	aqueductClient     aqueduct.Client
	promotionClient    promotion.IImagePromotionClient
	cryptographyClient *cryptography.CryptoClient
	allQueueNames      []string
}

type WorkerInstance = aqueduct.Worker

func NewWorkerPool(ctx context.Context, cfg *Config, promotionclient promotion.IImagePromotionClient) (*WorkerPool, error) {
	logger.Info(ctx, "creating aqueduct client", kvp.String("addr", cfg.Aqueduct.Addr))

	aqueductClient, err := aqueduct.NewAqueductClient(ctx, &cfg.Aqueduct)
	if err != nil {
		return nil, fmt.Errorf("failed to create aqueduct client: %w", err)
	}

	cryptoClient := cryptography.NewCryptoClient(cfg.Aqueduct.EncryptionKeyList)

	return &WorkerPool{
		config:             cfg,
		aqueductClient:     aqueductClient,
		promotionClient:    promotionclient,
		cryptographyClient: cryptoClient,
		allQueueNames:      queue.QueueNames,
	}, nil
}

func (w *WorkerPool) NewWorker() (*WorkerInstance, error) {
	worker, err := aqueduct.NewWorker(
		w.aqueductClient,
		w.config.Aqueduct.AppName,
		w.allQueueNames,
		w.handler,
		aqueduct.WithPool("general"), // we don't have different pools for IMS queues yet
		aqueduct.WithLogger(logger.GetBaseLogger()),
		aqueduct.WithReceiveTimeout(w.config.JobReceiveTimeout),
		aqueduct.WithJobErrorPolicy(aqueduct.NackJobErr), // Set ACK on job failures, so that it's not redelivered
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create aqueduct worker: %w", err)
	}

	return worker, nil
}

func (w *WorkerPool) handler(ctx context.Context, rr aqueduct.ReceiveResult) error {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("worker_job_id", rr.Job.ID),
		kvp.String("worker_queue", rr.Job.Queue),
	)
	ctx = stash.WithStatterFields(ctx,
		kvp.String("worker_queue", rr.Job.Queue),
	)

	logger.Info(ctx, "processing worker job")
	statter.Increment(ctx, "worker.job.started", kvp.String("queue", rr.Job.Queue)) // TODO: should we include queue to statter fields?

	var (
		job          *workerJob
		jobResult    workerJobResult
		jobStartTime = time.Now()
	)

	jobDefinition, jobFound := QueueToJobMapping[rr.Job.Queue]
	if jobFound {
		spanCtx, span := tracer.StartSpan(ctx, fmt.Sprintf("Worker.%s", jobDefinition.jobName))
		defer span.End()

		job = &workerJob{
			receiveResult:   rr,
			maxRetriesCount: jobDefinition.maxRetriesCount,
		}

		jobResult = jobDefinition.handler(spanCtx, w, job)
		if !jobResult.Succeeded {
			span.SetStatus(codes.Error, jobResult.Result.Error())
		}
	} else {
		job = &workerJob{}
		jobResult = job.nonRetryableErrorResult(ctx, fmt.Errorf("failed to process worker job from unknown queue"))
	}

	if jobResult.ShouldRetry {
		if err := w.queueJobRetry(ctx, job); err != nil {
			return fmt.Errorf("failed to queue job retry: %w", err)
		}
	}

	jobResultFields := []kvp.Field{
		kvp.Bool("result", jobResult.Succeeded),
		kvp.Int("attempt", job.getCurrentAttempt()),
		kvp.Bool("will_retry", jobResult.ShouldRetry),
	}
	statter.Increment(ctx, "worker.job.finished", jobResultFields...)
	statter.DistributionMs(ctx, "worker.job.duration", time.Since(jobStartTime), jobResultFields...)

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
