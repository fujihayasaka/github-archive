// Package kvperrors provides a wrapper around pkg/errors that adds the
// ability to associate a kvp type context with the error.
package kvperrors

import (
	"github.com/github/go-kvp"
	"github.com/pkg/errors"
)

func New(message string) error {
	return errors.New(message)
}

// With creates a new error with an associated kvp context.
func With(message string, fields ...kvp.Field) error {
	return WrapWith(errors.New(message), fields...)
}

// WrapWith returns an error with an associated kvp context.
func WrapWith(err error, fields ...kvp.Field) error {
	return _error{
		err: err,
		ctx: kvp.KVPs(fields...),
	}
}

// Context returns the associated kvp context, if possible.
func Context(err error) *kvp.KVP {
	type contexter interface {
		Context() *kvp.KVP
	}

	ctxer, ok := err.(contexter)
	if !ok {
		return nil
	}

	return ctxer.Context()
}

func FindContext(err error) []kvp.Field {
	type contexter interface {
		Context() *kvp.KVP
	}

	// First try using go 1.13's error chains.
	var ctxer contexter
	if errors.As(err, &ctxer) {
		ctx := ctxer.Context()
		if ctx == nil {
			return nil
		}
		return ctx.Fields()
	}

	// Fallback to searching ourselves using the causer interface.
	type causer interface {
		Cause() error
	}

	var ctx *kvp.KVP
	for {
		ctx = Context(err)
		if ctx != nil {
			break
		}

		cause, ok := err.(causer)
		if !ok {
			break
		}
		err = cause.Cause()
	}

	if ctx == nil {
		return nil
	}

	return ctx.Fields()
}

func Cause(err error) error {
	return errors.Cause(err)
}

func Wrap(err error, message string) error {
	return errors.Wrap(err, message)
}

// _error is an error implementation returned by the methods that add a kvp
// context.
type _error struct {
	err error
	ctx *kvp.KVP
}

// Error returns the underlying error's Error().
func (e _error) Error() string {
	return e.err.Error()
}

// Context returns the kvp context.
func (e _error) Context() *kvp.KVP {
	return e.ctx
}

func (e _error) Cause() error {
	return e.err
}

// Unwrap provides compatibility for Go 1.13 error chains.
func (e _error) Unwrap() error {
	return e.err
}

// StackTrace allows the wrapped errors to use the underlying errors package's
// stack trace capabilities. When returning the stacktrace, we chop off the top
// two frames, which will be errs package constructors.
func (e _error) StackTrace() errors.StackTrace {
	type stackTracer interface {
		StackTrace() errors.StackTrace
	}

	if err, ok := e.err.(stackTracer); ok {
		st := err.StackTrace()
		if len(st) > 2 {
			return st[2 : len(st)-1]
		}

		return st
	}

	return nil
}
