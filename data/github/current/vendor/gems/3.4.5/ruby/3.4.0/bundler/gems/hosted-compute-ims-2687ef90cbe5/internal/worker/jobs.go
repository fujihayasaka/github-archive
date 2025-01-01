package worker

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/worker/queue"
)

type (
	workerJobDefinition struct {
		handler         func(ctx context.Context, w *WorkerPool, job *workerJob) workerJobResult
		maxRetriesCount int
		jobName         string
	}
)

var QueueToJobMapping = map[string]workerJobDefinition{
	queue.QueueName_ProvisionImageVersion: {
		handler:         processProvisionImageVersionJob,
		maxRetriesCount: 5,
		jobName:         "ProvisionImageVersionJob",
	},
	queue.QueueName_DeleteImageDefinition: {
		handler:         processDeleteImageDefinitionJob,
		maxRetriesCount: 5,
		jobName:         "DeleteImageDefinitionJob",
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
		return job.nonRetryableErrorResult(ctx, fmt.Errorf("failed to unmarshal job payload: %w", err))
	}

	decryptedSourceVhdUrl, err := wp.decryptString(jobPayload.SourceVhdUrlEncoded, jobPayload.SourceVhdUrlSalt)
	if err != nil {
		return job.nonRetryableErrorResult(ctx, fmt.Errorf("failed to decrypt source vhd url: %w", err))
	}

	ctx = stash.WithLoggingFields(ctx,
		kvp.Uint64("image_version_id", jobPayload.ImageVersionId),
	)

	promoErr := wp.promotionClient.ProvisionImageVersion(ctx, jobPayload.ImageVersionId, decryptedSourceVhdUrl, jobPayload.WorkflowOwnerId)
	if promoErr == nil || promoErr.Err == nil {
		return job.successResult(ctx)
	}

	jobResult := job.errorResult(ctx, promoErr)

	if !jobResult.ShouldRetry {
		if err = wp.promotionClient.ProvisionImageVersionFailedAfterMaxRetries(ctx, jobPayload.ImageVersionId, promoErr); err != nil {
			logger.ErrorWithReport(ctx, "failed to finalize image version promotion after max retries exceed", err)
		}
	}

	return jobResult
}

func processDeleteImageDefinitionJob(ctx context.Context, wp *WorkerPool, job *workerJob) workerJobResult {
	var jobPayload queue.DeleteImageDefinitionJobPayload
	if err := json.Unmarshal(job.receiveResult.Payload, &jobPayload); err != nil {
		return job.nonRetryableErrorResult(ctx, fmt.Errorf("failed to unmarshal job payload: %w", err))
	}

	ctx = stash.WithLoggingFields(ctx,
		kvp.Uint64("image_definition_id", jobPayload.ImageDefinitionId),
	)

	promoErr := wp.promotionClient.DeleteImageDefinitionWithAllVersions(ctx, jobPayload.ImageDefinitionId)
	if promoErr == nil || promoErr.Err == nil {
		return job.successResult(ctx)
	}

	return job.errorResult(ctx, promoErr)
}

func processDeleteImageVersionJob(ctx context.Context, wp *WorkerPool, job *workerJob) workerJobResult {
	var jobPayload queue.DeleteImageVersionJobPayload
	if err := json.Unmarshal(job.receiveResult.Payload, &jobPayload); err != nil {
		return job.nonRetryableErrorResult(ctx, fmt.Errorf("failed to unmarshal job payload: %w", err))
	}

	ctx = stash.WithLoggingFields(ctx,
		kvp.Uint64("image_version_id", jobPayload.ImageVersionId),
	)

	promoErr := wp.promotionClient.DeleteImageVersion(ctx, jobPayload.ImageVersionId)
	if promoErr == nil || promoErr.Err == nil {
		return job.successResult(ctx)
	}

	return job.errorResult(ctx, promoErr)
}

func processProvisionCleanupJob(ctx context.Context, wp *WorkerPool, job *workerJob) workerJobResult {
	var jobPayload queue.ProvisionCleanupJobPayload
	if err := json.Unmarshal(job.receiveResult.Payload, &jobPayload); err != nil {
		return job.nonRetryableErrorResult(ctx, fmt.Errorf("failed to unmarshal job payload: %w", err))
	}

	ctx = stash.WithLoggingFields(ctx,
		kvp.Uint64("image_version_id", jobPayload.ImageVersionId),
	)

	promoErr := wp.promotionClient.CleanupImageVersionResources(ctx, jobPayload.ImageVersionId)
	if promoErr == nil || promoErr.Err == nil {
		return job.successResult(ctx)
	}

	return job.errorResult(ctx, promoErr)
}
