// Package twerrors provides Twirp-compatible errors that also have stack traces
// In should be used in preference over creating errors with the Twirp library directly
package twerrors

import (
	"github.com/pkg/errors"

	"github.com/twitchtv/twirp"
)

type twirpError struct {
	error
	st errors.StackTrace
}

// Interface from the errors package
type stackTracer interface {
	StackTrace() errors.StackTrace
}

func create(e twirp.Error, stripFrames int) twirp.Error {
	if e == nil {
		return nil
	}

	tempErr := errors.New("")
	var s stackTracer
	if !errors.As(tempErr, &s) {
		// This should never happen
		return e
	}

	return twirp.WrapError(e, &twirpError{error: e, st: s.StackTrace()[1+stripFrames:]})
}

func (e *twirpError) StackTrace() errors.StackTrace {
	return e.st
}

// NewError builds a twirp.Error. The code must be one of the valid predefined constants.
// To add metadata, use .WithMeta(key, value) method after building the error.
func NewError(code twirp.ErrorCode, msg string) twirp.Error {
	return create(twirp.NewError(code, msg), 1)
}

// NewErrorf builds a twirp.Error with a formatted msg.
// The format may include "%w" to wrap other errors. Examples:
//
//	twirp.NewErrorf(twirp.Internal, "Oops: %w", originalErr)
//	twirp.NewErrorf(twirp.NotFound, "resource with id: %q", resourceID)
func NewErrorf(code twirp.ErrorCode, msgFmt string, a ...interface{}) twirp.Error {
	return create(twirp.NewErrorf(code, msgFmt, a...), 1)
}

// NotFoundError is a convenience constructor for NotFound errors.
func NotFoundError(msg string) twirp.Error {
	return create(twirp.NotFoundError(msg), 1)
}

// InvalidArgumentError is a convenience constructor for InvalidArgument errors.
// The argument name is included on the "argument" metadata for convenience.
func InvalidArgumentError(argument string, validationMsg string) twirp.Error {
	return create(twirp.InvalidArgumentError(argument, validationMsg), 1)
}

// RequiredArgumentError builds an InvalidArgument error.
// Useful when a request argument is expected to have a non-zero value.
func RequiredArgumentError(argument string) twirp.Error {
	return create(twirp.RequiredArgumentError(argument), 1)
}

// InternalErrorWith makes an internal error, wrapping the original error and using it
// for the error message, and with metadata "cause" with the original error type.
// This function is used by Twirp services to wrap non-Twirp errors as internal errors.
//
// Since this is just a wrapper it does not create a new stack trace but relies on the passed-in
// error to have one. Because of this, it would actually be ok to use twirp.InternalErrorWith
// from the library and we just provide it here for convenience
func InternalErrorWith(err error) twirp.Error {
	return twirp.InternalErrorWith(err)
}

// InternalError is a convenience constructor for Internal errors.
func InternalError(msg string) twirp.Error {
	return create(twirp.InternalError(msg), 1)
}
