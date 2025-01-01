package errors

import (
	"net/http"
	"time"

	"github.com/hashicorp/go-multierror"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

// RetryableDurationError represents a retryable error that should be retried for a specific duration.
type RetryableDurationError interface {
	Error() string
	IsRetryable() bool
	RetryDuration() time.Duration
}

// IsRetryable indicates an error condition may be transient.
// The queue worker checks the error chain for this interface to determine if its useful to rerun a job.
type isRetryable interface {
	IsRetryable() bool
}

// IsRetryable checks the error chain for an error implementing IsRetryable.
// If an error is found, the value of `IsRetryable()` is returned. Otherwise `false` is returned.
func IsRetryable(err error) bool {
	var irErr isRetryable
	if errors.As(err, &irErr) {
		return irErr.IsRetryable()
	}

	return false
}

// IsUserError indicates an error is an expected error caused by user configuration.
// The queue worker checks the error chain for this interface to determine if the job was processes succesfully or not.
type isUserError interface {
	IsUserError() bool
}

// IsUserError checks if an error is a user error
// This intentionally does not follow the whole chain of errors, only unwrapping any errors that implement Cause.
// If the error is an error group, all errors in the group must be user errors.
func IsUserError(err error) bool {
	if err == nil {
		return false
	}

	if isExplicitUserError(err) {
		return true
	}

	cause := errors.Cause(err)
	if cause != nil && isExplicitUserError(cause) {
		return true
	}

	if errGroup, ok := err.(*multierror.Error); ok {
		if errGroup.ErrorOrNil() == nil {
			return false
		}

		for _, err := range errGroup.Errors {
			if !isExplicitUserError(err) {
				return false
			}
		}

		return true
	}

	return false
}

func isExplicitUserError(err error) bool {
	if iue, ok := err.(isUserError); ok {
		return iue.IsUserError()
	}

	switch err.(type) {
	case *azperrors.AZPSyntaxError, *wfparser.WorkflowParseError:
		return true
	}

	return IsUnreachableCommitError(err)
}

// IsNotFoundError indicates the error chain has some form of Not Found error, possibly marshalled in a network response (e.g. twirp).
func IsNotFoundError(err error) bool {
	if err == nil {
		return false
	}

	var notFoundErr *NotFoundError
	if errors.As(err, &notFoundErr) {
		return true
	}

	var twirpErr twirp.Error
	if errors.As(err, &twirpErr) {
		if twirpErr.Code() == twirp.NotFound {
			return true
		}
	}

	if httpErr := GetHTTPError(err); httpErr != nil {
		if httpErr.MatchStatusCodes(http.StatusNotFound) {
			return true
		}
	}

	// Add more checks here as you find other not found error types.

	return false
}

// FindRetryableDurationErrors unwraps the error chain, calling `f` for each RetryableDurationError found, if any.
func FindRetryableDurationErrors(err error, f func(dErr RetryableDurationError)) {
	if err == nil {
		return
	}

	if dErr, ok := err.(RetryableDurationError); ok {
		f(dErr)
	}

	var dErr RetryableDurationError
	if x, ok := err.(interface{ As(any) bool }); ok && x.As(&dErr) {
		f(dErr)
	}

	uErr := errors.Unwrap(err)
	if uErr != nil {
		FindRetryableDurationErrors(uErr, f)
	}
}

// RateLimited interface is used to indicate that an error is due to rate limiting.
type RateLimited interface {
	RateLimited() bool
}

// IsRateLimitError indicates the error chain includes a RateLimited error that returns true for RateLimited().
func IsRateLimitError(err error) bool {
	var rateLimitErr RateLimited
	if errors.As(err, &rateLimitErr) {
		return rateLimitErr.RateLimited()
	}

	var twirpErr twirp.Error
	if errors.As(err, &twirpErr) {
		if twirpErr.Code() == twirp.ResourceExhausted {
			return true
		}
	}

	return false
}

// IsTwirpError checks that an error is a twirp error.
func IsTwirpError(err error) bool {
	var twirpErr twirp.Error
	return errors.As(err, &twirpErr)
}

// IsRefResolutionError checks that an error is a ref resolution error.
func IsRefResolutionError(err error) bool {
	var refResolutionErr *RefResolutionError
	return errors.As(err, &refResolutionErr)
}

func IsForbiddenError(err error) bool {
	var forbiddenErr *ForbiddenError
	return errors.As(err, &forbiddenErr)
}
