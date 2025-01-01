// Logic for retrying failed LLM requests.
package provider

import (
	"context"
	"math"
	"sync"
	"time"

	"slices"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// RetryModel wraps a model and retries failed completions with exponential backoff.
type RetryModel struct {
	model         models.HashableModel
	maxTime       time.Duration
	retryDelay    time.Duration
	maxRetryDelay time.Duration
	retryBackoff  float64

	// Mutex to protect the shared state below
	mu             sync.Mutex
	retryAfterTime int64   // UNIX timestamp in milliseconds
	queue          []int64 // Start times of in-flight requests that are waiting
}

var _ models.HashableModel = &RetryModel{} //nolint:exhaustruct

// NewRetryModel creates a new RetryModel with custom retry parameters.
func NewRetryModel(
	model models.HashableModel,
) *RetryModel {
	return &RetryModel{
		model: model,
		/** Max time used trying to get a response, in milliseconds. */
		maxTime: 10 * time.Minute,
		/** Delay between retries, in milliseconds, scaled by backoff factor. */
		retryDelay: 2 * time.Second,
		/** Maximum amount of time to wait between retries, in milliseconds. */
		maxRetryDelay: 20 * time.Second,
		/**
		 * Backoff factor for retry delay.
		 *
		 * On the `i`th retry, we wait `retryDelay * retryBackoff ** (i - 1)` milliseconds.
		 *
		 * With the default values, this means that the wait
		 * - 2 seconds on the first retry
		 * - 3 seconds on the second retry
		 * - 4.5 seconds on the third retry
		 * - 6.8 seconds on the fourth retry
		 * - 10 seconds on the fifth retry
		 * - 15 seconds on the sixth retry
		 * - 20 seconds on every subsequent retry
		 */
		retryBackoff:   1.5,
		mu:             sync.Mutex{},
		retryAfterTime: -1, // Negative value indicates no waiting time
		queue:          []int64{},
	}
}

func (rm *RetryModel) GetModelName() string {
	return "Retry<" + rm.model.GetModelName() + ">"
}

func (rm *RetryModel) GetModelGeneration() string {
	return rm.model.GetModelGeneration()
}

func (rm *RetryModel) GetContextSize() int {
	return rm.model.GetContextSize()
}

func (rm *RetryModel) GetEncodingName() string {
	return rm.model.GetEncodingName()
}

func (rm *RetryModel) GetMaxTokens() int {
	return rm.model.GetMaxTokens()
}

func (rm *RetryModel) GetDefaultCompletionOptions() models.CompletionOptions {
	return rm.model.GetDefaultCompletionOptions()
}

func (rm *RetryModel) Complete(ctx context.Context, prompt []models.ChatMessage) (string, autofix.AutofixError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.RetryModel.Complete")
	defer span.End()

	// Call the complete method with default options
	opts := rm.GetDefaultCompletionOptions()
	return rm.CompleteWithOptions(ctx, prompt, &opts)
}

// Complete attempts to get a completion from the wrapped model, retrying with backoff on retryable errors.
func (rm *RetryModel) CompleteWithOptions(ctx context.Context, prompt []models.ChatMessage, options *models.CompletionOptions) (string, autofix.AutofixError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.RetryModel.CompleteWithOptions")
	defer span.End()

	startTime := time.Now()
	startTimeMs := startTime.UnixNano() / int64(time.Millisecond)

	// Add this request to the queue
	rm.mu.Lock()
	rm.queue = append(rm.queue, startTimeMs)
	// Sort the queue to ensure the oldest request is first
	sortInt64s(rm.queue)
	rm.mu.Unlock()

	iteration := 0
	for {
		// Wait if we need to (rate-limiting)
		for {
			rm.mu.Lock()
			myQueuePosition := indexOf(rm.queue, startTimeMs)
			rm.mu.Unlock()

			now := time.Now().UnixNano() / int64(time.Millisecond)

			rm.mu.Lock()
			myWaitTime := rm.retryAfterTime + int64(myQueuePosition*100)
			rm.mu.Unlock()

			if now >= myWaitTime {
				break
			}

			enhancedctx.Logger(ctx).Debug(
				"Waiting for retry-after delay",
				kvp.Int("gh.autofix.queue_position", myQueuePosition),
				kvp.Int64("gh.autofix.wait_time_ms", myWaitTime-now),
			)

			time.Sleep(time.Duration(myWaitTime-now) * time.Millisecond)
		}

		// Make the request
		result, err := rm.model.CompleteWithOptions(ctx, prompt, options)

		// Check if we've reached maximum retry time or got a successful response
		elapsedTime := time.Since(startTime)
		if elapsedTime > rm.maxTime || (err == nil) {
			// Remove our entry from the queue
			rm.mu.Lock()
			idx := indexOf(rm.queue, startTimeMs)
			if idx >= 0 {
				rm.queue = slices.Delete(rm.queue, idx, idx+1)
			}
			rm.mu.Unlock()

			return result, err
		}

		// Check if the error is retryable
		if !isRetryableError(err) {
			// Non-retryable error, remove from queue and return
			enhancedctx.Logger(ctx).Warn(
				"Aborting request on non-retryable error",
				kvp.String("gh.autofix.error", err.Error()),
			)

			rm.mu.Lock()
			idx := indexOf(rm.queue, startTimeMs)
			if idx >= 0 {
				rm.queue = append(rm.queue[:idx], rm.queue[idx+1:]...)
			}
			rm.mu.Unlock()

			return result, err
		}

		// Log and prepare for retry
		enhancedctx.Logger(ctx).Warn(
			"Retrying LLM request due to error",
			kvp.String("gh.autofix.error", err.Error()),
			kvp.Int("gh.autofix.retry_count", iteration),
		)

		// Check for Retry-After header
		if httpErr, ok := err.(autofix.HTTPStatusError); ok {
			retryDelayMs := int64(httpErr.RetryDelay() / time.Millisecond)
			if retryDelayMs > 0 {
				now := time.Now().UnixNano() / int64(time.Millisecond)

				rm.mu.Lock()
				rm.retryAfterTime = now + retryDelayMs
				rm.mu.Unlock()

				enhancedctx.Logger(ctx).Info(
					"Received retry-after instruction",
					kvp.Int64("gh.autofix.retry_after_ms", retryDelayMs),
				)
			}
		}

		// Always wait some time before retrying
		waitTime := rm.getWaitTime(iteration)
		enhancedctx.Logger(ctx).Debug(
			"Waiting before retry",
			kvp.Int64("gh.autofix.wait_time_ms", int64(waitTime/time.Millisecond)),
			kvp.Int("gh.autofix.retry_count", iteration),
		)
		time.Sleep(waitTime)
		iteration++
	}
}

// getWaitTime calculates the wait time for the current retry iteration using exponential backoff
func (rm *RetryModel) getWaitTime(iteration int) time.Duration {
	delay := time.Duration(float64(rm.retryDelay) * math.Pow(rm.retryBackoff, float64(iteration)))
	if delay > rm.maxRetryDelay {
		return rm.maxRetryDelay
	}
	return delay
}

// isRetryableError determines if an error is retryable based on type and status code
func isRetryableError(err autofix.AutofixError) bool {
	if err == nil {
		return false
	}

	// Check if the error itself advertises retryability
	if err.Retryable() {
		return true
	}

	// Check for HTTP status code retryability
	if httpErr, ok := err.(autofix.HTTPStatusError); ok {
		return isRetryableStatusCode(httpErr.StatusCode)
	}

	return false
}

func (rm *RetryModel) Hash() (string, error) {
	return rm.model.Hash()
}

// Helper functions

// indexOf returns the index of a value in a slice or -1 if not found
func indexOf(slice []int64, value int64) int {
	for i, v := range slice {
		if v == value {
			return i
		}
	}
	return -1
}

// sortInt64s sorts a slice of int64 in ascending order (in-place)
func sortInt64s(a []int64) {
	for i := range a {
		for j := i + 1; j < len(a); j++ {
			if a[i] > a[j] {
				a[i], a[j] = a[j], a[i]
			}
		}
	}
}
