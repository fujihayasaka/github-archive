// Package st provides utilities for handling stack traces in errors.
// In this library, we want to ensure all errors have stack traces based on
// where they were created.
//
// When creating a new error that does not wrap another error, use
// errors.New or errors.Errorf from the github.com/pkg/errors package.
// This will ensure that the stack trace is captured at the point of creation.
// If you need to wrap an existing error, use st.EnsureStackTrace or
// st.EnsureStackTracef to ensure that a stack trace is added if it does not
// already exist.
//
// There may be cases where you want to create an error without a stack trace or you
// want to explicitly override an existing stack trace.
// To create an error without a stack trace, use the standard library's
// errors.New or fmt.Errorf functions.
//
// To override an existing stack trace, use the pkg/errors package's
// errors.WithStack or errors.WithMessage functions.
// However, this is not generally recommended as it can lead to loss
// of context about where the error originated.
package st

import "github.com/pkg/errors"

// stackTracer is a copy of the pkg/errors stackTracer interface.
// It is used to retrieve the stack trace of an error.
type stackTracer interface {
	StackTrace() errors.StackTrace
}

// GetStackTrace gets a stack trace from an error if there is one.
func GetStackTrace(err error) errors.StackTrace {
	if err == nil {
		return nil
	}

	var stackError stackTracer
	if errors.As(err, &stackError) {
		return stackError.StackTrace()
	}

	return nil
}

// EnsureStackTrace checks if the error has a stack trace and adds one if not.
// Use this function instead of errors.Wrap to ensure that the error has a stack trace
// and the stack trace is not replaced by the wrapping process.
// If the error is nil, a new error with the provided message is returned.
func EnsureStackTrace(err error, msg string) error {
	if err == nil {
		return errors.New(msg)
	}

	if GetStackTrace(err) == nil {
		return errors.Wrap(err, msg)
	}

	return errors.WithMessage(err, msg)
}

// EnsureStackTracef checks if the error has a stack trace and adds one if not.
// Use this function instead of errors.Wrapf to ensure that the error has a stack trace
// and the stack trace is not replaced by the wrapping process.
func EnsureStackTracef(err error, msg string, args ...interface{}) error {
	if err == nil {
		return nil
	}

	if GetStackTrace(err) == nil {
		return errors.Wrapf(err, msg, args...)
	}

	return errors.WithMessagef(err, msg, args...)
}
