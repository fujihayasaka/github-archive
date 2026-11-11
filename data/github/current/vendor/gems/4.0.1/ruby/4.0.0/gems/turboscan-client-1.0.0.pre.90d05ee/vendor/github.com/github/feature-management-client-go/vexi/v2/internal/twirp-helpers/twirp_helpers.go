// Package twirphelpers contains helper functions for twirp.
package twirphelpers

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/avast/retry-go/v4"
	"github.com/twitchtv/twirp"
)

// WithRetry retries the given function until it succeeds or the timeout is reached.
func WithRetry(ctx context.Context, retryAttempts uint, timeout time.Duration, retryAction string, funcToCall func(context.Context) (interface{}, error)) (interface{}, error) {
	ctxWithTimeout, cancel := context.WithTimeoutCause(ctx, timeout, RequestTimeoutError{})
	defer cancel()

	resp, retryErr := retry.DoWithData[interface{}](
		func() (interface{}, error) {
			return funcToCall(ctxWithTimeout)
		},
		retry.Attempts(retryAttempts),
		retry.Context(ctxWithTimeout),
		retry.RetryIf(retry.RetryIfFunc(isRetryable)),
	)

	if retryErr != nil {
		// Check if the error is a vexi configured timeout.
		if errors.Is(context.Cause(ctxWithTimeout), &RequestTimeoutError{}) {
			return nil, NewRequestTimeoutError(retryErr)
		}
	}

	return resp, retryErr
}

// isRetryable returns true if the error is retryable.
func isRetryable(err error) bool {
	var twerr twirp.Error
	// Only retry on 500s and 503s
	if errors.As(err, &twerr) && (twerr.Code() == twirp.Unavailable || twerr.Code() == twirp.Internal) {
		return true
	}
	return false
}

// RequestTimeoutError is an error that is returned when the vexi configured timeout is exceeded.
type RequestTimeoutError struct {
	InnerError error
}

// NewRequestTimeoutError creates a new RequestTimeoutError.
func NewRequestTimeoutError(innerError error) *RequestTimeoutError {
	return &RequestTimeoutError{
		InnerError: innerError,
	}
}

// Error returns the error message.
func (e RequestTimeoutError) Error() string {
	return fmt.Errorf("%s: %w", "request timeout", e.InnerError).Error()
}

// Unwrap returns the inner error.
func (e RequestTimeoutError) Unwrap() error {
	return e.InnerError
}

// Is returns true if the target error is a RequestTimeoutError.
func (e RequestTimeoutError) Is(target error) bool {
	_, ok := target.(*RequestTimeoutError)
	return ok
}
