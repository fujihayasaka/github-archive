package launcher

import (
	"errors"
	"net/http"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/limiter"
)

// LaunchError represents an error that occurred during agent launch with
// explicit retriability information.
type LaunchError struct {
	// Err is the underlying error.
	Err error
	// Retriable indicates whether this error is transient and the operation
	// should be retried by the queue consumer.
	Retriable bool
}

// Error implements the error interface.
func (e *LaunchError) Error() string {
	return e.Err.Error()
}

// Unwrap returns the underlying error for errors.Is/As support.
func (e *LaunchError) Unwrap() error {
	return e.Err
}

// IsRetriable returns whether this error should trigger a retry.
func (e *LaunchError) IsRetriable() bool {
	return e.Retriable
}

// NonRetriableLaunchError creates a LaunchError that should not be retried.
// Use this for configuration errors, validation errors, and other permanent failures.
func NonRetriableLaunchError(err error) error {
	return &LaunchError{
		Err:       err,
		Retriable: false,
	}
}

// RetriableLaunchError creates a LaunchError that should be retried.
// Use this for transient errors like rate limits, network timeouts, and service unavailability.
func RetriableLaunchError(err error) error {
	return &LaunchError{
		Err:       err,
		Retriable: true,
	}
}

// ClassifyLaunchError examines an error and wraps it in a LaunchError with
// appropriate retriability based on the error type.
func ClassifyLaunchError(err error, message string) error {
	if err == nil {
		return nil
	}

	wrappedErr := goerrors.Errorf("%s: %w", message, err)

	// Check for rate limit errors - these are retriable
	if limiter.IsAnyRateLimitError(err) {
		return RetriableLaunchError(wrappedErr)
	}

	// Check for GitHub API errors
	var ghAPIErr *github.GitHubAPIError
	if errors.As(err, &ghAPIErr) {
		if ghAPIErr.Response != nil {
			switch ghAPIErr.Response.StatusCode {
			case http.StatusTooManyRequests, http.StatusInternalServerError, http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusGatewayTimeout:
				// 429, 500, 502, 503, 504 - Transient errors that should be retried
				return RetriableLaunchError(wrappedErr)
			case http.StatusBadRequest, http.StatusUnauthorized, http.StatusForbidden, http.StatusNotFound, http.StatusUnprocessableEntity:
				// 400, 401, 403, 404, 422 - Client errors - not retriable
				return NonRetriableLaunchError(wrappedErr)
			}
		}
	}

	// Default to retriable for unknown errors - the queue has retry limits
	// so we're safe from infinite loops, and it's better to retry than fail permanently
	return RetriableLaunchError(wrappedErr)
}

// IsRetriableLaunchError checks if an error is a retriable LaunchError.
func IsRetriableLaunchError(err error) bool {
	var launchErr *LaunchError
	if errors.As(err, &launchErr) {
		return launchErr.IsRetriable()
	}
	// If it's not a LaunchError, check for common retriable error types
	return limiter.IsAnyRateLimitError(err)
}
