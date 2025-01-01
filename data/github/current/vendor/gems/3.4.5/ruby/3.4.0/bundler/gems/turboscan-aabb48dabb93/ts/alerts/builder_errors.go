package alerts

import (
	"strings"

	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/transforms"
	"github.com/pkg/errors"
)

var ErrRuleNotFound = buildWarning("could not find rule")

// JoinErrors returns an error which contains all the errors provided
func JoinErrors(errs []error) error {
	if len(errs) == 0 {
		return nil
	}
	return joinedErrors(errs)
}

// SplitErrors returns a list of errors from err. A list of errors can be joined together using JoinErrors.
func SplitErrors(err error) []error {
	if err == nil {
		return nil
	}

	var errs joinedErrors
	if errors.As(err, &errs) {
		return errs
	}

	return []error{err}
}

// joinedErrors is a collection of errors that were joined together.
type joinedErrors []error

func (errs joinedErrors) Error() string {
	return strings.Join(transforms.Map(errs, error.Error), ", ")
}

// buildError describes an error which may be recoverable
// when https://github.com/golang/go/issues/53435 is implemented this interface can be removed and
// the error types can be expressed using errors.Wrap
// until then, this allows us to differentiate between errors that should fail the processing pipeline and
// errors that should be displayed to the user as warnings
type buildError interface {
	error
	IsRecoverable() bool
}

var _ buildError = (*buildWarning)(nil)

// buildWarning is a recoverable build error
type buildWarning string

func (b buildWarning) Error() string {
	return string(b)
}

func (buildWarning) IsRecoverable() bool {
	return true
}

var _ buildError = (*limits.LimitError)(nil)

// isUnrecoverableError checks if an error implements IsRecoverable() == true
func isUnrecoverableError(err error) bool {
	if err == nil {
		return false
	}

	var buildErr buildError
	if !errors.As(err, &buildErr) {
		return true
	}

	return !buildErr.IsRecoverable()
}

// UnrecoverableError returns any errors that do not implement IsRecoverable() == true
func UnrecoverableError(err error) error {
	return JoinErrors(transforms.Filter(SplitErrors(err), isUnrecoverableError))
}

// UnrecoverableArchivalError returns any errors that are not expected during the unarchival process
// We intentionally exclude invalid location errors as we have historical physical alerts that were saved
// with an empty file path.
func UnrecoverableArchivalError(err error) error {
	return JoinErrors(transforms.Filter(SplitErrors(err), func(err error) bool {
		return !strings.Contains(err.Error(), "locationFromSarifResult") && isUnrecoverableError(err)
	}))
}

// LimitErrors returns any errors of type LimitError that are present in err
func LimitErrors(err error) []limits.LimitError {
	return transforms.FilterMap(SplitErrors(err), func(err error) (limits.LimitError, bool) {
		var limitErr limits.LimitError
		ok := errors.As(err, &limitErr)
		return limitErr, ok
	})
}
