package provider

import (
	"context"
	"math"
	"time"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// RetryModel wraps a model and retries failed completions with exponential backoff.
type RetryModel struct {
	model         models.Model
	maxTime       time.Duration
	retryDelay    time.Duration
	maxRetryDelay time.Duration
	retryBackoff  float64
}

var _ models.Model = &RetryModel{} //nolint:exhaustruct // Just testing that the type works.

// NewRetryModel creates a new RetryModel with custom retry parameters.
func NewRetryModel(
	model models.Model,
) *RetryModel {
	return &RetryModel{
		model: model,
		// Max time used trying to get a response, in milliseconds.
		maxTime: 10 * time.Minute,
		// Delay between retries, in milliseconds, scaled by backoff factor.
		retryDelay: 2 * time.Second,
		// Maximum amount of time to wait between retries, in milliseconds.
		maxRetryDelay: 20 * time.Second,
		// Backoff factor for retry delay.
		//
		// On the `i`th retry, we wait `retryDelay * retryBackoff ** (i - 1)` milliseconds.
		//
		// With the default values, this means that the wait
		// - 2 seconds on the first retry
		// - 3 seconds on the second retry
		// - 4.5 seconds on the third retry
		// - 6.8 seconds on the fourth retry
		// - 10 seconds on the fifth retry
		// - 15 seconds on the sixth retry
		// - 20 seconds on every subsequent retry
		retryBackoff: 1.5,
	}
}

// GetModelName returns the name of the wrapped model with retry prefix.
func (rm *RetryModel) GetModelName() string {
	return "Retry<" + rm.model.GetModelName() + ">"
}

// GetProviderName returns the provider name of the wrapped model.
func (rm *RetryModel) GetProviderName() string {
	return rm.model.GetProviderName()
}

// Complete attempts to get a completion from the wrapped model, retrying with backoff on retryable errors.
func (rm *RetryModel) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.RetryModel.Complete")
	defer span.End()

	startTime := time.Now()

	iteration := 0
	for {
		// Make the request
		result, transcript, usage, err := rm.model.Complete(ctx, messages, tools, options)

		// Check if we've reached maximum retry time or got a successful response
		elapsedTime := time.Since(startTime)
		if elapsedTime > rm.maxTime || (err == nil) {
			return result, transcript, usage, err
		}

		// Check if the error is retryable
		if !errors.IsRetryableError(err) {
			// Non-retryable error, return immediately
			enhancedctx.Logger(ctx).Warn(
				"Aborting request on non-retryable error",
				kvp.String("gh.autofix.error", err.Error()),
			)

			return result, transcript, usage, err
		}

		// Log and prepare for retry
		enhancedctx.Logger(ctx).Warn(
			"Retrying LLM request due to error",
			kvp.String("gh.autofix.error", err.Error()),
			kvp.Int("gh.autofix.retry_count", iteration),
		)

		retryAfterTime := time.Duration(0)

		// Check for Retry-After header
		if httpErr, ok := err.(errors.HTTPStatusError); ok {
			retryAfterTime = httpErr.RetryDelay()
		}

		// Always wait some time before retrying
		waitTime := rm.getWaitTime(iteration, retryAfterTime)
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
func (rm *RetryModel) getWaitTime(iteration int, retryAfterTime time.Duration) time.Duration {
	delay := time.Duration(float64(rm.retryDelay) * math.Pow(rm.retryBackoff, float64(iteration)))

	// If Retry-After header is provided, and it's greater than the calculated delay, use it
	if retryAfterTime > delay {
		return retryAfterTime
	}

	// Cap the delay at maxRetryDelay
	if delay > rm.maxRetryDelay {
		return rm.maxRetryDelay
	}

	return delay
}
