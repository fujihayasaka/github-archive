// Package pkgerrors implements a stacktracer using the pkg/errors library.
package pkgerrors

import (
	"fmt"
	"strings"

	"github.com/github/go-exceptions"

	//nolint:depguard // we want to use the pkg/errors library
	"github.com/pkg/errors"
)

type unwrappable interface {
	Unwrap() error
}
type stackTracer interface {
	StackTrace() errors.StackTrace
}

// NewStackTracer returns a structured stacktracer function using the
// pkg/errors library, suitable for use inside the go-exceptions
// `WithStacktraceFunc` option.
func NewStackTracer() func(err error) ([]exceptions.StackTrace, string) {
	fn := func(err error) ([]exceptions.StackTrace, string) {
		// unwrap github.com/pkg/errors to find the wrapper with
		// the stack trace closest to the originating error
		current := err
		var innermostWithTrace stackTracer
		for {
			//nolint:errorlint // we want to use the pkg/errors library
			if nextST, ok := current.(stackTracer); ok {
				innermostWithTrace = nextST
			}

			//nolint:errorlint // we want to use the pkg/errors library
			unwrappableErr, ok := current.(unwrappable)
			if !ok {
				break
			}

			unwrappedErr := unwrappableErr.Unwrap()
			current = unwrappedErr
		}

		var st stackTracer
		if innermostWithTrace != nil {
			st = innermostWithTrace
		} else {
			err = newUnwrappedError(err) // We don't have a wrapped error so lets wrap it
			//nolint:errorlint // we want to use the pkg/errors library
			st, _ = err.(stackTracer) // Ignore the check as we know newUnwrappedError returns a stackTracer
		}

		trace := st.StackTrace()

		var rollupInfo string
		//nolint:errorlint // we want to use the pkg/errors library
		roller, ok := err.(interface{ RollupInfo() string })
		if ok {
			rollupInfo = roller.RollupInfo()
		} else {
			rollupInfo = getRollup(trace)
		}

		return getStackTrace(err, trace), rollupInfo
	}

	return fn
}

func getStackTrace(err error, trace errors.StackTrace) []exceptions.StackTrace {
	frames := []exceptions.StackFrame{}

	// Reverse the stack, that's how Sentry wants it ordered
	for i := len(trace) - 1; i >= 0; i-- {
		line := trace[i]

		// Per pkg/errors docs, formatting an error with `%+s` returns
		// "<funcname>\n\t<path>" so we are splitting on that here, and
		// assuming we'll get 2 strings back, then use the path portion.
		d := strings.Split(fmt.Sprintf("%+s", line), "\n\t")
		if len(d) != 2 { // This should not happen, but extra safety
			continue
		}
		frames = append(frames, exceptions.StackFrame{
			FileName:   fmt.Sprintf("%s", line),
			AbsPath:    d[1],
			LineNumber: fmt.Sprintf("%d", line),
			Function:   fmt.Sprintf("%n", line),
		})
	}

	return []exceptions.StackTrace{{
		// prevent Sentry errors being named as '*errors.withStack' most of the
		// time. Better would be maybe providing part of the error message
		// (i.e: err.Error()) as part of the Type, so Sentry can group entries
		// based on the type + value.
		Type:   fmt.Sprintf("%T", errors.Cause(err)),
		Value:  err.Error(),
		Frames: frames,
	}}
}

func getRollup(trace errors.StackTrace) string {
	var s strings.Builder
	for _, frame := range trace {
		_, _ = fmt.Fprintf(&s, "%+v:%n\n", frame, frame)
	}
	return s.String()
}

type unwrappedError struct {
	err error
}

func newUnwrappedError(err error) error {
	return &unwrappedError{err: errors.Wrap(err, "Unwrapped error")}
}
func (e *unwrappedError) Error() string                     { return e.err.Error() }
func (e *unwrappedError) Cause() error                      { return e.err }
func (e *unwrappedError) Rollup(_ errors.StackTrace) string { return e.Error() }
func (e *unwrappedError) StackTrace() errors.StackTrace {
	//nolint:errorlint // we want to use the pkg/errors library
	if st, ok := e.err.(stackTracer); ok {
		return st.StackTrace()
	}
	return nil
}

type withRollupInfoError struct {
	err  error
	info string
}

func (e *withRollupInfoError) RollupInfo() string { return e.info }
func (e *withRollupInfoError) Error() string      { return e.err.Error() }
func (e *withRollupInfoError) Cause() error       { return e.err }
func (e *withRollupInfoError) Unwrap() error      { return e.err }
func (e *withRollupInfoError) StackTrace() errors.StackTrace {
	//nolint:errorlint // we want to use the pkg/errors library
	if st, ok := e.err.(stackTracer); ok {
		return st.StackTrace()
	}
	return nil
}

// WithRollupInfo wraps err with rollup info to be used in lieu of the stack trace.
func WithRollupInfo(err error, info string) error {
	if err == nil {
		return nil
	}
	return &withRollupInfoError{
		err:  err,
		info: info,
	}
}
