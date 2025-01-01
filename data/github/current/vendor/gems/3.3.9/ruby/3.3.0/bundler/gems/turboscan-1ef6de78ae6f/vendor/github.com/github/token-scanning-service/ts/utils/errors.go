package utils

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/avast/retry-go"
	"github.com/twitchtv/twirp"
)

// ScanError represents an error in the scan
type ScanError interface {
	// Error returns a string of a given type representing a user readable message
	Error() string

	// IsFatal identifies if the given error type is fatal or not.
	IsFatal() bool
}

type ScanCancelledError struct {
	Msg string
}

func (m *ScanCancelledError) Error() string {
	return fmt.Sprintf("scan was cancelled because: %s", m.Msg)
}

func (m *ScanCancelledError) IsFatal() bool {
	return true
}

type PartnerValidityWorkerError struct {
	Msg string
}

func (m *PartnerValidityWorkerError) Error() string {
	return fmt.Sprintf("partner validity worker errored because: %s", m.Msg)
}

func (m *PartnerValidityWorkerError) IsFatal() bool {
	return true
}

// ErrFlaky is a sentinel error intended to represent a flaky error
// In practice, this will be used to indicate that we should retry the job
// but don't want it ending in the deadletter or tombstone.
var ErrFlaky = errors.New("flaky error")

func FatalError(err error) bool {
	var scanError ScanError
	if errors.As(err, &scanError) {
		return scanError.IsFatal()
	}

	err = UnwrapLastIfRetryError(err)

	var twErr twirp.Error
	if errors.As(err, &twErr) {
		switch twErr.Code() {
		// Note: deadline exceeded errors are returned as fatal due to the assumption that these are true data-shape errors that should not be retried
		case twirp.NotFound, twirp.DeadlineExceeded, twirp.Canceled:
			return true
		case twirp.Internal:
			// note: I'm not entirely sure jobs should be dying this way, but this is explicitly following the above pattern where DeadlineExceeded is considered a fatal, not-retryable situation.
			// We should probably re-evaluate this eventually, but for now we need to handle this case:
			// "twirp error internal: failed to do request: context deadline exceeded"
			// we occasionally get twirp internal errors that are wrapping "failed to do request" deadline exceeded errors, specifically when the server encountered a deadline
			// but not the client. The generated twirp client creates an internal error, wrapped with "failed to do request: %w"
			// As far as I can tell since this message is from the server side portion there's not an actual context.DeadlineExceeded error to wrap - e.g.,
			// this error, even though the text is correct, does not satisfy the `errors.Is` of an official deadline exceeded - hence the suffix hack.
			// There may be another way.
			if strings.HasSuffix(twErr.Msg(), context.DeadlineExceeded.Error()) {
				return true
			}

		}
	}

	// default to retryable error as we have no other information
	return false
}

type NoTokensFoundError struct {
	Msg string
}

func (m *NoTokensFoundError) Error() string {
	return fmt.Sprintf("no tokens were found: %s", m.Msg)
}

// IsTwirpError returns true if the given error is a twirp error with the given error code, returns false otherwise
func IsTwirpError(err error, code twirp.ErrorCode) bool {
	var twErr twirp.Error
	if errors.As(err, &twErr) {
		return twErr.Code() == code
	}

	return false
}

// IsTwirpInternalWrappedDeadlineError returns true if the given error is both a twirp internal error, and
// ends with a "context deadline exceeded"
func IsTwirpInternalWrappedDeadlineError(err error) bool {
	var twErr twirp.Error
	if !errors.As(err, &twErr) {
		return false
	}

	if twErr.Code() != twirp.Internal {
		return false
	}

	return strings.HasSuffix(twErr.Msg(), context.DeadlineExceeded.Error())
}

// UnwrapLastIfRetryError unwraps err if it is a `"github.com/avast/retry-go" Error, and returns the last error.
func UnwrapLastIfRetryError(err error) error {
	var retryLibErrors retry.Error
	if errors.As(err, &retryLibErrors) {
		if len(retryLibErrors) == 0 {
			return err
		}
		// go backwards and find the first non-nil error
		for i := len(retryLibErrors) - 1; i >= 0; i-- {
			if retryErr := retryLibErrors[i]; retryErr != nil {
				err = retryErr
			}
		}
	}
	return err
}
