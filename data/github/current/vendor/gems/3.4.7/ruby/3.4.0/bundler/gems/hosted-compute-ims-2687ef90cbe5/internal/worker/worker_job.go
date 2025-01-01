package worker

import (
	"context"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
)

const retryAttemptHeader = "retry_attempt"

type workerJob struct {
	receiveResult   aqueduct.ReceiveResult
	maxRetriesCount int
}

type workerJobResult struct {
	Succeeded   bool
	ShouldRetry bool
	Result      error
}

func (j *workerJob) successResult(ctx context.Context) workerJobResult {
	logger.Info(ctx, "worker job finished",
		kvp.String("result", "success"),
		kvp.Int("attempt", j.getCurrentAttempt()),
	)

	return workerJobResult{Succeeded: true, ShouldRetry: false, Result: nil}
}

func (j *workerJob) nonRetryableErrorResult(ctx context.Context, err error) workerJobResult {
	return j.errorResult(ctx,
		&promotion.PromotionError{
			Err:              err,
			UserErrorDetails: "",
			NonRetryable:     true,
		},
	)
}

func (j *workerJob) errorResult(ctx context.Context, jobError *promotion.PromotionError) workerJobResult {
	var (
		retryableError bool
		willRetry      bool
		currentAttempt = j.getCurrentAttempt()
	)

	if jobError.NonRetryable || jobError.IsSharedDevImagesError() {
		retryableError = false
		willRetry = false
	} else {
		retryableError = true
		willRetry = currentAttempt < j.maxRetriesCount
	}

	logger.ErrorWithReport(ctx, "worker job finished", jobError.Err,
		kvp.String("result", "failure"),
		kvp.Int("attempt", currentAttempt),
		kvp.Bool("retryable_error", retryableError),
		kvp.Bool("will_retry", willRetry),
	)

	return workerJobResult{Succeeded: false, ShouldRetry: willRetry, Result: jobError.Err}
}

func (j *workerJob) getCurrentAttempt() int {
	headerValue, found := j.receiveResult.Headers[retryAttemptHeader]
	if found {
		attempt, err := strconv.Atoi(headerValue)
		if err == nil {
			return attempt
		}
	}

	// if header is not found, assume it is first attempt
	return 1
}
