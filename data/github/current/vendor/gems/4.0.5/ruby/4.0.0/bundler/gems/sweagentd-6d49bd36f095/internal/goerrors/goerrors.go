// Package goerrors defines utilities for go error reporting at github
package goerrors

import (
	"errors"
	"fmt"
	"iter"
	"runtime"
)

const maxStackSize = 1028

// New generates a new error and wraps it with a stacktrace, analogous to `errors.New`
func New(s string) error {
	return WithStackOffset(errors.New(s), 1) //nolint:goerrorslint // Fundamental to the working of goerrors
}

// Errorf takes a format string and a number of arguments and ensures that the resulting error contains a stacktrace.  If any of the arguments are errors that already have a stacktrace, then no additional stacktraces are generated.
func Errorf(s string, args ...any) error {
	for _, arg := range args {
		err, ok := arg.(error)
		if !ok {
			continue
		}

		var stacktrace StacktraceError
		if errors.As(err, &stacktrace) {
			// Already contains stack trace, do not wrap
			return fmt.Errorf(s, args...) //nolint:goerrorslint // Fundamental to the working of goerrors
		}
	}
	return WithStackOffset(fmt.Errorf(s, args...), 1) //nolint:goerrorslint // Fundamental to the working of goerrors
}

// WithStack adds a stacktrace to the current error.  This should be called when
// creating new errors, and at API boundaries between sweagentd and other
// libraries.
func WithStack(err error) error {
	// Helper function for the stack offset
	return WithStackOffset(err, 1)
}

// WithStackOffset adds a stacktrace to an error, with the start of the stack offset a number of stack frames.  0 offsets us to "the caller of this function", as if you had called "WithStack".  An offset of 1 or 2 may be useful if you are using a helper function to generate an error.
func WithStackOffset(err error, offset int) error {
	pc := make([]uintptr, maxStackSize)
	size := runtime.Callers(2+offset, pc)

	return &ProgramCounterStacktraceError{
		pc:      pc[:size],
		wrapped: err,
	}
}

// GetStacks gets all the stacktraces associated with an error.
func GetStacks(err error) []StacktraceError {
	var stackTrace StacktraceError
	stacks := []StacktraceError{}
	next := err
	for errors.As(next, &stackTrace) {
		stacks = append(stacks, stackTrace)
		var unwrappableError interface{ Unwrap() error }
		if !errors.As(stackTrace, &unwrappableError) {
			break
		}

		next = unwrappableError.Unwrap()
	}

	return stacks
}

// Frame represents a single line of a stacktrace
type Frame struct {
	Function   string
	LineNumber int
	FileName   string
}

// StacktraceError is an error containing a stack trace
type StacktraceError interface {
	error
	Frames() iter.Seq[*Frame]
}

// ProgramCounterStacktraceError represents an error that wraps another error with a stacktrace, represented by an array of program counters
type ProgramCounterStacktraceError struct {
	pc      []uintptr
	wrapped error
}

// Frames returns the stack frames associated with StacktraceError's stack trace
func (s *ProgramCounterStacktraceError) Frames() iter.Seq[*Frame] {
	frames := runtime.CallersFrames(s.pc)
	return func(yield func(*Frame) bool) {
		for {
			goframe, more := frames.Next()

			frame := &Frame{
				Function:   goframe.Function,
				LineNumber: goframe.Line,
				FileName:   goframe.File,
			}

			if !yield(frame) {
				return
			}

			if !more {
				return
			}
		}
	}
}

// Error returns the error message associated with this StacktraceError
func (s *ProgramCounterStacktraceError) Error() string {
	return s.wrapped.Error()
}

// Unwrap returns the wrapped error
func (s *ProgramCounterStacktraceError) Unwrap() error {
	return s.wrapped
}
