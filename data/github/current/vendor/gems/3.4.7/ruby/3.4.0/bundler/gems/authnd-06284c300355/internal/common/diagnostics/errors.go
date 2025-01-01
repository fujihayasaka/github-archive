package diagnostics

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-ctxutil"
	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/pkg/errors"
)

type (
	causer interface {
		Cause() error
	}
	unwrapper interface {
		Unwrap() error
	}
	stackTracer interface {
		StackTrace() errors.StackTrace
	}
)

// A MultiError is a collection of multiple errors aggregated into a single error.
type MultiError []error

func (e MultiError) Error() string {
	s := fmt.Sprintf("%d error(s) occured:\n", len(e))
	for _, err := range e {
		s += "* " + err.Error() + " "
	}

	return s
}

func (e MultiError) ErrorOrNil() error {
	if e == nil {
		return nil
	}

	if len(e) == 0 {
		return nil
	}

	return e
}

// Error fields must use semantic convention: https://thehub.github.com/epd/engineering/dev-practicals/observability/semantic-conventions/user-guide/.
// ReportError reports the provided error, with the provided log message and payload,
// to both the current logger (in the context) and the current error reporter (also in the context).
func ReportError(ctx context.Context, errOrPanic interface{}, logMessage string, params map[string]string) {
	// Report each error in a MutliError separately
	if me, ok := errOrPanic.(MultiError); ok {
		for _, e := range me {
			ReportError(ctx, e, logMessage, params)
		}
		return
	}

	err, ok := errOrPanic.(error)
	if !ok {
		// It's a panic, wrap it in an error
		err = errors.Errorf("panic: %v", errOrPanic)
	}

	if errors.Is(err, context.Canceled) {
		// Cancelled contexts are not reported as errors, they just mean we got shut down.
		return
	}

	logger := Logger(ctx)
	reporter := Reporter(ctx)

	stack := ""
	stackError := unwrapToStackTrace(err)
	_, ok = stackError.(stackTracer)
	if !ok {
		// We couldn't figure out a stack trace for the error.
		// Wrap it in a new error that uses the current location's stack trace
		err = errors.Wrap(err, "wrapped error with no stack trace")

		// Then use that to get a stack trace
		stackError = unwrapToStackTrace(err)
	}

	if st, ok := stackError.(stackTracer); ok {
		stack = fmt.Sprintf("%+v", st.StackTrace())
	}

	fields := []kvp.Field{kvp.String("stack", stack)}

	for k, v := range params {
		fields = append(fields, kvp.String(k, v))
	}

	logger.WithError(err).Error(logMessage, fields...)

	// detach the context so parent cancellation doesn't cancel our
	// report to Sentry
	reportErr := reporter.Report(ctxutil.DetachedCancel(ctx), err, params)
	if reportErr != nil {
		logger.WithError(errors.WithStack(reportErr)).Error("error reporting error", kvp.Any("original.err", err))
	}
}

// NewStackTracer returns a stacktracer function that understands how to unwrap
// errors and find the stack trace in them
func NewStackTracer() func(err error) ([]exceptions.StackTrace, string) {
	defaultStackTracer := pkgerrors.NewStackTracer()
	return func(err error) ([]exceptions.StackTrace, string) {
		trace, str := defaultStackTracer(unwrapToStackTrace(err))
		if trace == nil {
			return defaultStackTracer(errors.New("call site stack trace"))
		}
		return trace, str
	}
}

// unwrapToStackTrace attempts to continuously unwrap the error in the hopes that the cause
// will meet the stackTrace interface. If unwrapping fails, the original
// error is returned unaltered.
func unwrapToStackTrace(original error) error {
	current := original

	for {
		switch e := current.(type) {
		case stackTracer:
			return current
		case unwrapper:
			current = e.Unwrap()
		case causer:
			current = e.Cause()
		default:
			// Can't go any further, let's stop
			return original
		}
	}
}
