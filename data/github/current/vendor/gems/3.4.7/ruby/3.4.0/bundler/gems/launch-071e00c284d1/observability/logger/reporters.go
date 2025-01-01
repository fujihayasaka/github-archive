package logger

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/github/go-exceptions"
	http_exporter "github.com/github/go-exceptions/exporters/http"
	writer_exporter "github.com/github/go-exceptions/exporters/writer"
	legacylog "github.com/github/go-log"
	"github.com/pkg/errors"
)

const appModule = "github.com/github/launch"

func newReporter(app, url, hostname string, errorHandler func(error), q int) (*exceptions.Reporter, error) {
	var exporters []exceptions.Exporter

	if len(url) > 0 {
		httpExporter, err := http_exporter.NewExporter(http_exporter.WithURL(url))
		if err != nil {
			return nil, err
		}
		exporters = append(exporters, newQueuedExporter(httpExporter, errorHandler, q))
	}

	if legacylog.IsTerminal() || len(url) == 0 {
		exporters = append(exporters, writer_exporter.NewExporter(os.Stderr))
	}

	r, err := exceptions.NewReporter(
		exceptions.WithHostname(hostname),
		exceptions.WithApplication(app),
		exceptions.WithStacktraceFunc(stacktraceFn),
		exceptions.WithExporter(exceptions.MultiExporter(exporters...)),
		exceptions.WithRollupInfoFunc(exceptions.RollupInfo),
	)
	if err != nil {
		return nil, err
	}

	return r, nil
}

// NullReporter does nothing with the reports passed in
func NullReporter() *exceptions.Reporter {
	r, _ := exceptions.NewReporter(
		exceptions.WithApplication("null-reporter"),
		exceptions.WithExporter(&nullExporter{}),
	)
	return r
}

type nullExporter struct{}

func (e *nullExporter) Export(_ context.Context, _ []byte) error {
	return nil
}

type stackTracer interface {
	StackTrace() errors.StackTrace
}

func stacktraceFn(err error) ([]exceptions.StackTrace, string) {
	st, ok := err.(stackTracer)
	if !ok {
		err = newUnwrappedError(err) // We don't have a wrapped error so lets wrap it
		st, _ = err.(stackTracer)    // Ignore the check as we know newUnwrappedError returns stackTracer
	}

	trace := st.StackTrace()

	return getStackTrace(err, trace), getRollup(err, trace)
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
		absPath := d[1]

		frames = append(frames, exceptions.StackFrame{
			FileName:   fmt.Sprintf("%s", line),
			AbsPath:    absPath,
			LineNumber: fmt.Sprintf("%d", line),
			Function:   fmt.Sprintf("%n", line),
		})
	}

	return []exceptions.StackTrace{{
		Type:   fmt.Sprintf("%T", errors.Cause(err)),
		Value:  err.Error(),
		Frames: frames,
	}}
}

func getRollup(err error, trace errors.StackTrace) string {
	type customRollup interface {
		Rollup(errors.StackTrace) string
	}

	if e, ok := err.(customRollup); ok {
		if customRollup := e.Rollup(trace); customRollup != "" {
			return customRollup
		}
	}

	// "auto" will let Sentry to the grouping when there are no stackframes
	if len(trace) == 0 {
		return "auto"
	}

	bestFrame := trace[0]

	// Use the first (last in execution) app line from the stack trace as the
	// rollup. If no lines can be determined to come from the app then use the
	// first line.
	for _, frame := range trace {
		s := fmt.Sprintf("%+s", frame)
		if strings.HasPrefix(s, appModule) && !strings.HasPrefix(s, fmt.Sprintf("%s/observability/kvperrors", appModule)) {
			bestFrame = frame
			break
		}
	}

	// Use the error message and the stacktrace for rollup. Requires that the error message
	// not have unique-per-request data in it
	return fmt.Sprintf("%s:%+v", err.Error(), bestFrame)
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
	if st, ok := e.err.(stackTracer); ok {
		return st.StackTrace()
	}
	return nil
}
