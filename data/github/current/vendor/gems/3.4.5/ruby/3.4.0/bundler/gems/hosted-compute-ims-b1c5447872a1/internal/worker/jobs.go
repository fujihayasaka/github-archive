package worker

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/worker/queue"
)

type (
	workerJobDefinition struct {
		handler         func(ctx context.Context, w *WorkerPool, job *workerJob) workerJobResult
		maxRetriesCount int
		jobName         string
	}
)

var queueToJobMapping = map[string]workerJobDefinition{
	queue.QueueName_ProvisionImageVersion: {
		handler:         processProvisionImageVersionJob,
		maxRetriesCount: 5,
		jobName:         "ProvisionImageVersionJob",
	},
	queue.QueueName_DeleteImageVersion: {
		handler:         processDeleteImageVersionJob,
		maxRetriesCount: 5,
		jobName:         "DeleteImageVersionJob",
	},
	queue.QueueName_ProvisionCleanup: {
		handler:         processProvisionCleanupJob,
		maxRetriesCount: 3,
		jobName:         "ProvisionCleanupJob",
	},
}

func processProvisionImageVersionJob(ctx context.Context, wp *WorkerPool, job *workerJob) workerJobResult {
	var jobPayload queue.ProvisionImageVersionJobPayload
	if err := json.Unmarshal(job.receiveResult.Payload, &jobPayload); err != nil {
		return job.nonRetryableErrorResult(fmt.Errorf("failed to unmarshal job payload: %w", err))
	}

	decryptedSourceVhdUrl, err := wp.decryptString(jobPayload.SourceVhdUrlEncoded, jobPayload.SourceVhdUrlSalt)
	if err != nil {
		return job.nonRetryableErrorResult(fmt.Errorf("failed to decrypt source vhd url: %w", err))
	}

	job.logger = utils.NewLoggerWithFields(
		job.logger,
		kvp.Uint64("image_version_id", jobPayload.ImageVersionId),
	)

	promoErr := wp.promotionClient.ProvisionImageVersion(ctx, job.logger, jobPayload.ImageVersionId, decryptedSourceVhdUrl)
	if promoErr == nil || promoErr.Err == nil {
		return job.successResult()
	}

	jobResult := job.errorResult(promoErr)

	if !jobResult.ShouldRetry {
		if err = wp.promotionClient.ProvisionImageVersionFailedAfterMaxRetries(ctx, job.logger, jobPayload.ImageVersionId, promoErr); err != nil {
			job.logger.ErrorWithReport("failed to finalize image version promotion after max retries exceed", err, kvp.Uint64("image_version_id", jobPayload.ImageVersionId))
		}
	}

	return jobResult
}

func processDeleteImageVersionJob(ctx context.Context, wp *WorkerPool, job *workerJob) workerJobResult {
	var jobPayload queue.DeleteImageVersionJobPayload
	if err := json.Unmarshal(job.receiveResult.Payload, &jobPayload); err != nil {
		return job.nonRetryableErrorResult(fmt.Errorf("failed to unmarshal job payload: %w", err))
	}

	job.logger = utils.NewLoggerWithFields(
		job.logger,
		kvp.Uint64("image_version_id", jobPayload.ImageVersionId),
	)

	promoErr := wp.promotionClient.DeleteImageVersion(ctx, job.logger, jobPayload.ImageVersionId)
	if promoErr == nil || promoErr.Err == nil {
		return job.successResult()
	}

	return job.errorResult(promoErr)
}

func processProvisionCleanupJob(ctx context.Context, wp *WorkerPool, job *workerJob) workerJobResult {
	var jobPayload queue.ProvisionCleanupJobPayload
	if err := json.Unmarshal(job.receiveResult.Payload, &jobPayload); err != nil {
		return job.nonRetryableErrorResult(fmt.Errorf("failed to unmarshal job payload: %w", err))
	}

	job.logger = utils.NewLoggerWithFields(
		job.logger,
		kvp.Uint64("image_version_id", jobPayload.ImageVersionId),
	)

	promoErr := wp.promotionClient.CleanupImageVersionResources(ctx, job.logger, jobPayload.ImageVersionId)
	if promoErr == nil || promoErr.Err == nil {
		return job.successResult()
	}

	return job.errorResult(promoErr)
}
