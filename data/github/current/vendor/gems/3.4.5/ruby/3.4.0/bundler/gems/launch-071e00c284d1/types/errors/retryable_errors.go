package errors

import "time"

type retryableError struct {
	msg string
}

// NewRetryable returns an error that returns true for IsRetryable().
func NewRetryable(message string) error {
	return &retryableError{message}
}

func (r *retryableError) Error() string {
	return r.msg + " (retryable)"
}

func (r *retryableError) IsRetryable() bool {
	return true
}

// based on pkg/error's withMessage and Wrap functions.
type retryableWithMessage struct {
	cause error
	msg   string
}

// WrapAsRetryable returns an error that returns true for IsRetryable(), and wraps the provided error.
func WrapAsRetryable(err error, message string) error {
	return &retryableWithMessage{
		cause: err,
		msg:   message,
	}
}

func (w *retryableWithMessage) Error() string {
	return w.msg + " (retryable): " + w.cause.Error()
}

func (w *retryableWithMessage) Cause() error {
	return w.cause
}

// Unwrap provides compatibility for Go 1.13 error chains.
func (w *retryableWithMessage) Unwrap() error {
	return w.cause
}

func (w *retryableWithMessage) IsRetryable() bool {
	return true
}

// implements the exported RetryableForDurationError interface
type retryableForDurationError struct {
	retryableError
	retryDuration time.Duration
}

func NewRetryableDuration(message string, retryDuration time.Duration) RetryableDurationError {
	return &retryableForDurationError{retryableError{message}, retryDuration}
}

func (r *retryableForDurationError) RetryDuration() time.Duration {
	return r.retryDuration
}
