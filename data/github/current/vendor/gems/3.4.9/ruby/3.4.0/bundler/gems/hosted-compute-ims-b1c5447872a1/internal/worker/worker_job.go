package worker

import (
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
)

const retryAttemptHeader = "retry_attempt"

type workerJob struct {
	logger          *telemetry.ReportingLogger
	receiveResult   aqueduct.ReceiveResult
	maxRetriesCount int
}

type workerJobResult struct {
	Succeeded   bool
	ShouldRetry bool
	Result      error
}

func (j *workerJob) successResult() workerJobResult {
	j.logger.Info(
		"worker job finished",
		kvp.String("result", "success"),
		kvp.Int("attempt", j.getCurrentAttempt()),
	)

	return workerJobResult{Succeeded: true, ShouldRetry: false, Result: nil}
}

func (j *workerJob) nonRetryableErrorResult(err error) workerJobResult {
	return j.errorResult(
		&promotion.PromotionError{
			Err:              err,
			UserErrorDetails: "",
			NonRetryable:     true,
		},
	)
}

func (j *workerJob) errorResult(jobError *promotion.PromotionError) workerJobResult {
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

	j.logger.ErrorWithReport("worker job finished", jobError.Err,
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
