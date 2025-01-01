package common

import (
	"context"
	"fmt"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

// WithRetries performs the provided operation function once, and then retries up to `retryAttempts` times if it returns any of the `retryableErrors` provided.
// If no retryableErrors are provided, then all errors are considered retryable (with the exception of context.Canceled)
//
// Errors are compared with `retryableErrors` using `errors.Is`. Errors of type context.Canceled will never be retryable.
// The `authnd.retries.result.count` metric is emitted for each operation, describing the number of attempts and if it succeeded in the end.
func WithRetries(ctx context.Context, operationName string, operation func(ctx context.Context) error, retryAttempts int, retryableErrors ...error) error {
	// add 1 to retryAttempts to cover for the initial attempt
	maxAttempts := retryAttempts + 1
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.operation.retry", operationName), kvp.Int("gh.authnd.operation.retry.max_attempts", maxAttempts))

	var operationErr error
	attempt := 0
	for attempt < maxAttempts {
		attempt += 1
		ctx = diagnostics.WithLoggerFields(ctx, kvp.Int("gh.authnd.operation.retry.attempt", attempt))

		isRetry := attempt > 1
		if isRetry {
			diagnostics.Logger(ctx).Info("[Retries] Beginning retry operation: " + operationName)
		}

		operationErr = operation(ctx)
		if operationErr == nil || !isRetryable(operationErr, retryableErrors) {
			break
		}
	}

	resultTag := "success"
	if operationErr != nil {
		resultTag = "failure"
	}
	diagnostics.Statter(ctx).Counter(
		"retries.result.count",
		stats.Tags{
			"operation":    operationName,
			"result":       resultTag,
			"attempts":     fmt.Sprint(attempt),
			"max_attempts": fmt.Sprint(maxAttempts),
		},
		1,
	)
	return operationErr
}

func isRetryable(theErr error, retryableErrors []error) bool {
	// context cancelation should never be retryable
	if errors.Is(theErr, context.Canceled) {
		return false
	}

	// if there are no retryable errors defined, we
	// allow any error to be retryable
	if len(retryableErrors) == 0 {
		return true
	}

	for _, retryableError := range retryableErrors {
		if errors.Is(theErr, retryableError) {
			return true
		}
	}
	return false
}
