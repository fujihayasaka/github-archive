package errors

import (
	"errors"
	"fmt"
	"strings"

	"github.com/github/notifyd/internal/pkg/o11y/tags"
)

// Error defines a struct that implements the Go's error interface. It includes information about
// whether an error is retriable or not.
//
// By default errors are not retriable.
type Error struct {
	error
	retriable bool
	transient bool
	panic     bool
}

// Option defines a function that can be used to mutate an error.
type Option func(*Error)

// With receives a list of Option functions that mutate the error in which they are called.
func (err *Error) With(opts ...Option) *Error {
	for _, o := range opts {
		o(err)
	}

	return err
}

// Unwrap implements the unwrapping of Error as specified by Go errors.Unwrap()
//
// NOTE: Be aware that unwrapping an Error removes all the customizations.
func (err *Error) Unwrap() error {
	return errors.Unwrap(err.error)
}

// MarkRetriable is an option that marks an error as retriable. It pairs with IsRetriable that
// indicates whether an error is retriable or not.
func MarkRetriable() Option {
	return func(e *Error) {
		e.retriable = true
		e.transient = true
	}
}

// IsRetriable returns true when err is an Error and when it is
// marked as retriable.
func IsRetriable(err error) bool {
	if err == nil {
		return false
	}

	var e *Error
	if errors.As(err, &e) {
		return e.retriable
	}

	return false
}

// MarkTransient marks an error as transient. It pairs with IsTransient that
// indicates whether an error is transient or not.
func MarkTransient() Option {
	return func(e *Error) {
		e.transient = true
	}
}

// IsTransient returns true when an Error is a transient error.
func IsTransient(err error) bool {
	if err == nil {
		return false
	}

	var e *Error
	if errors.As(err, &e) {
		return e.transient
	}

	return false
}

// MarkPanic is an option that marks the error as a recovered panic error. It pairs with IsPanic that
// indicates whether an error was recovered from a panic.
func MarkPanic() Option {
	return func(e *Error) {
		e.panic = true
	}
}

// IsPanic returns true when an Error is a panic error.
func IsPanic(err error) bool {
	if err == nil {
		return false
	}

	var e *Error
	if errors.As(err, &e) {
		return e.panic
	}

	return false
}

// Type returns the type of error as a string
func Type(err error) string {
	switch {
	case IsRetriable(err):
		return "retriable"
	case IsTransient(err):
		return "transient"
	case IsPanic(err):
		return "panic"
	default:
		return "normal"
	}
}

// New returns a new Error that conforms to Go's standards
func New(msg string) *Error {
	return &Error{error: fmt.Errorf("%s", msg)}
}

// Newf returns a new Error that conforms to Go's standards, you can use the same formatting verbs
// you would use with fmt.Sprintf() for it.
func Newf(msg string, a ...interface{}) *Error {
	return &Error{error: fmt.Errorf(msg, a...)}
}

// Wrap returns an Error that adds extra information to the given one. It implements Unwrap
//
// NOTE: Be aware that unwrapping an Error removes all the customizations.
func Wrap(err error, msg string) *Error {
	if err == nil {
		return nil
	}

	var w *Error
	if errors.As(err, &w) {
		w.error = fmt.Errorf("%s: %w", msg, w.error)
		return w
	}

	return &Error{error: fmt.Errorf("%s: %w", msg, err)}
}

// Wrapf acts as Wrap and in addition allows to format the given message with the same verbs as
// fmt.Sprintf()
//
// NOTE: Be aware that unwrapping an Error removes all the customizations.
func Wrapf(err error, msg string, a ...interface{}) *Error {
	if err == nil {
		return nil
	}

	formattedMsg := fmt.Sprintf(msg, a...)

	var w *Error
	if errors.As(err, &w) {
		w.error = fmt.Errorf("%s: %w", formattedMsg, w.error)
		return w
	}

	return &Error{error: fmt.Errorf("%s: %w", formattedMsg, err)}
}

// Unwrap is a proxy function to Go's standard errors.Unwrap so that we only have to import an
// errors package.
//
// NOTE: Be aware that unwrapping an Error removes all the customizations.
var Unwrap = errors.Unwrap

// Is is a proxy function to Go's standard errors.Is
var Is = errors.Is

// As is a proxy function to Go's standard errors.As
var As = errors.As

// FormatAsTag takes the last error message in the stack and formats it according to DataDog requirements
// for tags, replacing spaces with underscores, see stats.CleanTag() for more info, see
// stats.CleanTag() for more info.
func FormatAsTag(err error) string {
	if err == nil {
		return "no_error"
	}

	msgs := strings.Split(err.Error(), ":")
	if len(msgs) < 1 {
		return "no_error"
	}

	if msgs[0] == "" {
		return "no_error"
	}

	return tags.CleanTag(msgs[0])
}

/*
IsType checks if an error has an instance of the type T in its chain.
This is essentially the same as As, but it handles the initialization of a zero value target instance for you.

So, instead of doing this:

	var target *ErrSomething
	ok := error.As(err, &target)

You can do this:

	ok := IsType[ErrSomething](err)
*/
func IsType[T any](err error) bool {
	var target *T // zero value of T
	return As(err, &target)
}
