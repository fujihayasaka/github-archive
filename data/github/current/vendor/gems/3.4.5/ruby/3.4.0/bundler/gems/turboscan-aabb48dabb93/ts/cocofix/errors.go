package cocofix

import (
	"github.com/pkg/errors"
)

type TransientError struct {
	Err error
}

func (e *TransientError) Error() string {
	return e.Err.Error()
}

func (e *TransientError) Unwrap() error {
	return e.Err
}

func IsTransientError(err error) bool {
	var te *TransientError
	return errors.As(err, &te)
}

// NonRetriableError are errors from cocofix that should not be attempted to
// be retried. Probably a bad input or output. When that is caused,
// there is no point in the job retrying the call.
// i.e.: a bad cocofix binary
type NonRetriableError struct {
	Err error
}

func (c *NonRetriableError) Error() string {
	return c.Err.Error()
}

func (c *NonRetriableError) Unwrap() error {
	return c.Err
}

func IsNonRetriableError(err error) bool {
	var nre *NonRetriableError
	return errors.As(err, &nre)
}
