// Package exceptions provides exception reporting to our internal exception service via different exporters.
package exceptions

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/github/exception-filters/go/rules"
)

// NullReporter is a reporter instance that discards all input. It's similar to
// log.NullLogger or stats.NullStatter and is useful to be used in tests or
// anywhere else where you don't care about the reporter output.
var NullReporter = newNullReporter(&nullExporter{})

// ErrorLoggerFunc defines the function used to log errors during reporting.
// It logs the error during a report. reportErr is the error returned from
// reporter.Report(...) call. exceptionErr and payload are the same values
// passed to reporter.
//
//	import (
//	   "github.com/github/go-log"
//	   "github.com/github/go-kvp"
//	)
//
//	 errorLogger := func(reportErr, exception error, payload map[string]string) {
//	 	logger.Error("reporter.Report has failed",
//	 		kvp.Err(reportErr),
//	 		kvp.String("exception_err", exception.Error()),
//	 	)
//	 }
//
//	reporter, err := NewReporter(
//		WithExporter(writer.NewExporter(os.Stdout),
//	   WithErrorLogger(errorLogger),
//		...
//	)
type ErrorLoggerFunc func(reportErr, exceptionErr error, payload map[string]string)

// CustomRedactionFunc is a function used to redact values in the payload before they are
// dispatched via an exporter. Useful for allowing user to redact service-specific secrets or
// sensitive values that might not be caught by:
type CustomRedactionFunc func(value string) string

var specialKeys = map[string]bool{
	"app":        true,
	"host":       true,
	"message":    true,
	"created_at": true,
	"rollup":     true,
	"backtrace":  true,
}

// Exporter exports the underlying exception in JSON format.
type Exporter interface {
	Export(ctx context.Context, p []byte) error
}

type multiExporter struct {
	exporters []Exporter
}

func (m *multiExporter) Export(ctx context.Context, data []byte) error {
	for _, r := range m.exporters {
		err := r.Export(ctx, data)
		if err != nil {
			return err
		}
	}
	return nil
}

// MultiExporter creates a exporter that duplicates all export writes to all
// the provided exporters. Each data is written to each listed exporter, one
// at a time. This is useful if you want to export with multiple exporter to
// multiple locations, such as http and stdout. Note that ff a listed exporter
// returns an error, that overall export operation stops and returns the error;
// it does not continue down the list.
func MultiExporter(exporters ...Exporter) Exporter {
	allExporters := make([]Exporter, 0, len(exporters))
	for _, r := range exporters {
		// make sure we handle the case if someone passes a multiexporter to
		// create another multiexporter to flatten out the list of exporters
		if mr, ok := r.(*multiExporter); ok {
			allExporters = append(allExporters, mr.exporters...)
		} else {
			allExporters = append(allExporters, r)
		}
	}

	return &multiExporter{exporters: allExporters}
}

// Option function that allows us to configure the reporter.
type Option func(opts *options) error

// options defines the configuration for the reporter.
type options struct {
	exporter Exporter

	// hostname is the name of this machine. It will be reported as "host" on
	// all exception payloads.
	hostname string

	// app is the name of this application. It will be reported on all exception
	// payloads.
	app string

	// catalogService is the associated catalog service of the application.
	catalogService string

	// backtraceFn is used to return a custom backtrace and rollup value for
	// the given error. Useful to provide custom function for various error
	// packages, such as pkg/errors
	// DEPRECATED - will be removed in a future major version
	backtraceFn func(exception error) (backtrace string, rollup string)

	// stacktraceFn is used to return a custom structured stacktrace for
	// the given error. Useful to provide custom function for various error
	// packages, such as pkg/errors, Sentry will render these structured
	// in a useful way
	stacktraceFn func(exception error) (stacktrace []StackTrace, rollup string)

	// redactFn is used to redact values in the payload before they are
	// dispatched via exporter. Useful for allowing user to redact
	// service-specific secrets or sensitive values that might not be
	// caught by:
	//
	// 1. The built-in reaction in go-exceptions provided by github/exception-filters
	// 2. The redaction that failbotg does on receipt of the payload.
	//
	// Configured via `WithCustomRedaction` on the Reporter.
	//
	// This function will not be applied to any values included in the sensitive
	// payload, these will still be submitted to the exporter as-is when using
	// `ReportSensitive`.
	redactFn CustomRedactionFunc

	rollupInfoFn rollupInfoFunc

	// handler is used to call the next handler when the client is used
	// as an http.Handler to recover from panics.
	handler http.Handler

	// values contains static values that are injected into the payload for
	// each report.
	values map[string]string

	// sensitiveValues contains static values that are injected into the
	// sensitive payload for each report.
	sensitiveValues map[string]string

	// logger is used to log internal errors
	logger ErrorLoggerFunc
}

// StackFrame defines the structure that failbot uses for posting an individual
// structured stack frame to Sentry, as part of a StrackTrace.
type StackFrame struct {
	FileName     string `json:"filename,omitempty"`
	AbsPath      string `json:"abs_path,omitempty"`
	LineNumber   string `json:"lineno,omitempty"`
	ColumnNumber string `json:"colno,omitempty"`
	Function     string `json:"function,omitempty"`
}

// StackTrace defines the structure that failbot uses for posting structures
// stack traces to sentry.
type StackTrace struct {
	Type   string       `json:"type,omitempty"`
	Value  string       `json:"value,omitempty"`
	Frames []StackFrame `json:"stacktrace,omitempty"`
}

// Reporter defines a reporter that reports exceptions.
type Reporter struct {
	exporter Exporter

	// hostname is the name of this machine. It will be reported as "host" on
	// all exception payloads.
	hostname string

	// app is the name of this application. It will be reported on all exception
	// payloads.
	app string

	// catalogService is the associated catalog service of the application.
	catalogService string

	// backtraceFn is used to return a custom backtrace and rollup value for
	// the given error. Useful to provide custom function for various error
	// packages, such as pkg/errors
	// DEPRECATED - will be removed in a future major version
	backtraceFn func(exception error) (backtrace string, rollup string)

	rollupInfoFn rollupInfoFunc

	// stacktraceFn is used to return a custom structured stacktrace for
	// the given error. Useful to provide custom function for various error
	// packages, such as pkg/errors
	stacktraceFn func(exception error) (stacktrace []StackTrace, rollup string)

	// redactFn is used to redact values in the payload before they are
	// dispatched via exporter. Useful for allowing user to redact
	// service-specific secrets or sensitive values that might not be
	// caught by:
	//
	// 1. The built-in reaction in go-exceptions provided by github/exception-filters
	// 2. The redaction that failbotg does on receipt of the payload.
	//
	// Enabled via `WithCustomRedaction`.
	//
	// This function will not be applied to any values included in the sensitive
	// payload, these will still be submitted to the exporter as-is when using
	// `ReportSensitive`.
	redactFn CustomRedactionFunc

	// handler is used to call the next handler when the client is used
	// as an http.Handler to recover from panics.
	handler http.Handler

	// values contains static values that are injected into the payload for
	// each report.
	values map[string]string

	// sensitiveValues contains static values that are injected into the
	// sensitive payload for each report.
	sensitiveValues map[string]string

	// now is used to add the current time during reporting of an
	// exception. It's a function to make testing easier.
	now func() time.Time

	// logger is used to log internal errors
	logger ErrorLoggerFunc
}

// WithExporter sets the exporter.
func WithExporter(exporter Exporter) Option {
	return func(opts *options) error {
		opts.exporter = exporter
		return nil
	}
}

// WithHostname sets the hostname. It will be added as "host" on all exception
// payloads.
func WithHostname(hostname string) Option {
	return func(opts *options) error {
		opts.hostname = hostname
		return nil
	}
}

// WithApplication sets the application name. It will be added as "app" on all
// exception payloads.
func WithApplication(app string) Option {
	return func(opts *options) error {
		opts.app = app
		if opts.catalogService == "" {
			opts.catalogService = app
		}
		return nil
	}
}

// WithCatalogService sets the catalog service name. It will be added as
// "catalog_service" on all exception payloads.
func WithCatalogService(service string) Option {
	return func(opts *options) error {
		opts.catalogService = service
		return nil
	}
}

// WithHandler sets the HTTP middleware to be used when the client is
// used as an http.Handler.
func WithHandler(handler http.Handler) Option {
	return func(opts *options) error {
		if handler == nil {
			return errors.New("handler cannot be set to nil")
		}
		opts.handler = handler
		return nil
	}
}

// WithHandlerFunc sets the HTTP middleware that to be used when the
// client is used as an http.Handler.
func WithHandlerFunc(handler http.HandlerFunc) Option {
	return WithHandler(handler)
}

// WithBacktraceFunc sets the backtrace function that is used to populate the
// "backtrace" and "rollup" keys. This is useful to setup a function that makes
// use of the stacktrace feature of some popular error packages, such as
// "pkg/errors". As an example this is how to us the `pkg/errors` package:
//
//	import "github.com/pkg/errors"
//
//	backtraceFn := func(err error) (string, string) {
//		bt, ok := err.(errors.StackTrace)
//		if !ok {
//			return "", ""
//		}
//
//		backtrace := fmt.Sprintf("%+v", bt)
//
//		top := bt[0]
//		rollup := fmt.Sprintf("%+s:%d:%n", top, top, top)
//
//		return backtrace, rollup
//	}
//
//	reporter, err := NewReporter(
//		WithExporter(writer.NewExporter(os.Stdout),
//		WithBacktraceFunc(backtraceFn),
//		...
//	)
//
// # Empty strings are not added to the payload and will be neglected
//
// Deprecated: WithBacktraceFunc is deprecated and will be removed in a future release,
// it is better to use WithStacktraceFunc for better structure.
//
//nolint:dupword // false positive in code
func WithBacktraceFunc(fn func(err error) (backtrace string, rollup string)) Option {
	return func(opts *options) error {
		opts.backtraceFn = fn
		return nil
	}
}

// WithStacktraceFunc sets the structured backtrace function that is used to populate the
// "exception_detail" key, which has been added to failbot to improve upon the pure text
// backtrace (see WithBacktraceFunc). This is useful to setup a function that makes
// use of the stacktrace feature of some popular error packages. If you are using
// `pkg/errors` for your error types, you can import the pre-defined stacktrace
// function below, otherwise look at the source to see what it is doing:
//
//	import "github.com/github/go-exceptions/stacktracers/pkgerrors"
//
//	reporter, err := NewReporter(
//		WithExporter(writer.NewExporter(os.Stdout),
//		WithStacktraceFunc(pkgerrors.NewStackTracer()),
//		...
//	)
func WithStacktraceFunc(fn func(err error) (stacktrace []StackTrace, rollup string)) Option {
	return func(opts *options) error {
		opts.stacktraceFn = fn
		return nil
	}
}

// WithRollupInfoFunc sets the function that is used to group similar exceptions. When ok == true
// info is used as this exception's rollup info. When ok is false Reporter will set the rollup
// the same as it would have if this option were not set.
func WithRollupInfoFunc(fn func(exception error) (info string, ok bool)) Option {
	return func(opts *options) error {
		opts.rollupInfoFn = fn
		return nil
	}
}

// WithValues sets default values to be added to the payload. Useful if
// you want to inject static custom values, such as the environment of the
// applications or git commit SHA of the application it was built on.
func WithValues(values map[string]string) Option {
	return func(opts *options) error {
		for k := range values {
			if specialKeys[k] {
				return fmt.Errorf("payload key %q is a special key and cannot be overridden", k)
			}
		}

		opts.values = values
		return nil
	}
}

// WithSensitiveValues sets default values to be added to the sensitive payload.
// Useful if you want to inject static custom sensitive values, such as branch names
// or repository names.
func WithSensitiveValues(values map[string]string) Option {
	return func(opts *options) error {
		for k := range values {
			if specialKeys[k] {
				return fmt.Errorf("payload key %q is a special key and cannot be overridden", k)
			}
		}

		opts.sensitiveValues = values
		return nil
	}
}

// WithErrorLogger sets a logger that used to log any reporting errors. Useful
// if you don't want to check and log the error returned from the
// reporter.Report() call. As an example this is how to us with our go-log package:
//
//	import (
//	   "github.com/github/go-log"
//	   "github.com/github/go-kvp"
//	)
//
//	 errorLogger := func(reportErr, exception error, payload map[string]string) {
//	 	logger.Error("reporter.Report has failed",
//	 		kvp.Err(reportErr),
//	 		kvp.String("exception_err", exception.Error()),
//	 	)
//	 }
//
//	reporter, err := NewReporter(
//		WithExporter(writer.NewExporter(os.Stdout),
//	   WithErrorLogger(errorLogger),
//		...
//	)
func WithErrorLogger(logger ErrorLoggerFunc) Option {
	return func(opts *options) error {
		opts.logger = logger
		return nil
	}
}

// WithCustomRedaction sets a function that is used to redact values in the payload before they are
// dispatched via an exporter. Useful for allowing user to redact service-specific secrets or
// sensitive values that might not be caught by the built-in redaction in go-exceptions or the
// redaction that failbotg does on receipt of the payload.
//
// This function will not be applied to any values included in the sensitive payload, these will
// still be submitted to the exporter as-is when using `ReportSensitive`.
//
// See docs on The Hub for more guidance on redacting sensitive values:
// https://thehub.github.com/epd/engineering/dev-practicals/observability/exception-tracking/sensitive-content-filtering/
//
// Example use:
//
// // Contrived example. Likely your function would use regex or something else more complex
// // to find and redact sensitive values.
//
//	myCustomRedacter := func(value string) string {
//		if strings.Contains(value, "my-secret-value") {
//			return "REDACTED"
//		}
//		return value
//	}
//
//	reporter, err := NewReporter(
//		WithCustomRedaction(myCustomRedacter),
//	   ...all the other configured options...
//	)
func WithCustomRedaction(redactFn CustomRedactionFunc) Option {
	return func(opts *options) error {
		opts.redactFn = redactFn
		return nil
	}
}

// NewReporter returns a new reporter with the given options.
func NewReporter(opts ...Option) (*Reporter, error) {
	hostname, err := os.Hostname()
	if err != nil {
		return nil, err
	}

	// defaults
	clientOpts := &options{
		catalogService: os.Getenv("OTEL_SERVICE_NAME"),
		app:            os.Getenv("FAILBOT_APP_OVERRIDE"),
		hostname:       hostname,
	}

	for _, opt := range opts {
		if err := opt(clientOpts); err != nil {
			return nil, err
		}
	}

	if clientOpts.app == "" {
		return nil, errors.New("app name is not set")
	}

	if clientOpts.exporter == nil {
		return nil, errors.New("exporter is not set")
	}

	if clientOpts.catalogService == "" {
		return nil, errors.New("catalog service is not set")
	}

	return &Reporter{
		exporter:        clientOpts.exporter,
		app:             clientOpts.app,
		catalogService:  clientOpts.catalogService,
		hostname:        clientOpts.hostname,
		backtraceFn:     clientOpts.backtraceFn,
		stacktraceFn:    clientOpts.stacktraceFn,
		rollupInfoFn:    clientOpts.rollupInfoFn,
		redactFn:        clientOpts.redactFn,
		handler:         clientOpts.handler,
		logger:          clientOpts.logger,
		values:          clientOpts.values,
		sensitiveValues: clientOpts.sensitiveValues,
		now:             time.Now,
	}, nil
}

// Report submits the given exception upstream with the "message" field. This
// function blocks until the exception has been successfully sent, and returns an
// error otherwise.
//
// The keys and values passed in payload map will be added to the exceptions's
// payload before sending. It errors if the payload contains a key that
// overrides any of the default payload keys, such as "app", "host" or
// "message". DO NOT PROVIDE SENSITIVE VALUES IN THE payload map.
//
// See ReportSensitive if you have sensitive values to provide.
func (r *Reporter) Report(ctx context.Context, exception error, payload map[string]string) error {
	reportErr := r.report(ctx, exception, payload, nil)
	if reportErr != nil && r.logger != nil {
		r.logger(reportErr, exception, payload)
	}
	return reportErr
}

// ReportSensitive submits the given exception upstream with the "message" field. This
// function blocks until the exception has been successfully sent, and returns an
// error otherwise.
//
// The keys and values passed in payload map will be added to the exceptions's
// payload before sending. It errors if the payload contains a key that
// overrides any of the default payload keys, such as "app", "host" or
// "message". DO NOT PROVIDE SENSITIVE VALUES IN THE payload map.
//
// Sensitive values may be provided in the sensitive_payload map.
func (r *Reporter) ReportSensitive(ctx context.Context, exception error, payload, sensitivePayload map[string]string) error {
	reportErr := r.report(ctx, exception, payload, sensitivePayload)
	if reportErr != nil && r.logger != nil {
		r.logger(reportErr, exception, payload)
	}
	return reportErr
}

// ReportRaw reports a problem that doesn't necessarily correspond to
// a go error, or where you want more direct control over setting
// the message, stacktrace, etc. The rollup is simply set to
// the message passed in. Note that this method ignores
// backtraceFn, stacktraceFn, and rollupFn.
func (r *Reporter) ReportRaw(ctx context.Context, message string, payload map[string]string, stacktraces []StackTrace) error {
	data := r.failbotData(message)

	anyData, err := r.mergePayload(payload, data)

	if err != nil {
		return err
	}

	anyData["exception_detail"] = stacktraces

	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(anyData); err != nil {
		return err
	}

	err = r.exporter.Export(ctx, buf.Bytes())

	if err != nil && r.logger != nil {
		r.logger(err, errors.New(message), payload)
	}
	return err
}

func (r *Reporter) report(ctx context.Context, exception error, payload, sensitivePayload map[string]string) error {
	if exception == nil {
		return errors.New("exception cannot be nil")
	}

	data := r.failbotData(exception.Error())

	// add backtrace and update rollup if it exists
	if r.backtraceFn != nil {
		backtrace, rp := r.backtraceFn(exception)
		if backtrace != "" {
			data["backtrace"] = backtrace
		}

		if rp != "" {
			data["rollup"] = rollup(rp)
		}
	}

	anyData, err := r.mergePayload(payload, data)
	if err != nil {
		return err
	}

	// add stacktrace if it exists
	if r.stacktraceFn != nil {
		stacktrace, rp := r.stacktraceFn(exception)
		if len(stacktrace) > 0 {
			anyData["exception_detail"] = stacktrace
		}

		if rp != "" {
			anyData["rollup"] = rollup(rp)
		}
	}

	// merge in static sensitive payload data
	if sensitivePayload == nil && r.sensitiveValues != nil {
		sensitivePayload = make(map[string]string)
	}
	for k, v := range r.sensitiveValues {
		sensitivePayload[k] = v
	}

	// Add sensitive context if it exists
	if sensitivePayload != nil {
		anyData["sensitive_context"] = sensitivePayload
	}

	if r.rollupInfoFn != nil {
		rp, ok := r.rollupInfoFn(exception)
		if ok {
			anyData["rollup"] = rollup(rp)
		}
	}

	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(anyData); err != nil {
		return err
	}

	return r.exporter.Export(ctx, buf.Bytes())
}

// mergePayload copies the values from the payload into the base
// failbot data, erroring out if the payload tries to overwrite
// the host or created_at fields in baseData.
//
// Additionally, it redacts the values using the built-in redaction
// rules, and applies the user's redaction function if configured.
func (r *Reporter) mergePayload(payload, data map[string]string) (map[string]interface{}, error) {
	for k, v := range payload {
		// only check for these keys, everything else should be customizable to
		// allow flexibility for various use cases
		switch k {
		case "host", "created_at":
			_, ok := data[k]
			if ok {
				return nil, fmt.Errorf("payload key %q already exist and cannot be overridden", k)
			}
		}

		data[k] = v
	}

	if r.values != nil {
		for k, v := range r.values {
			data[k] = v
		}
	}

	anyData := map[string]interface{}{}
	// redact values and don't leak any sensitive information
	for k, v := range data {
		val := rules.RedactValue(v)
		// Where configured, apply the user's redaction function.
		if r.redactFn != nil {
			val = r.redactFn(val)
		}
		anyData[k] = val
	}
	return anyData, nil
}

// failbotData initializes the payload we'll send to failbot using
// the given message.
func (r *Reporter) failbotData(message string) map[string]string {
	return map[string]string{
		"app":             r.app,
		"catalog_service": r.catalogService,
		"host":            r.hostname,
		"message":         message,
		"created_at":      r.now().UTC().Format(time.RFC3339),
		"rollup":          rollup(message),

		// failbotg excepts the class to be available for the title. We're using
		// the error message instead of the type, because in Go the error type
		// is usually standard `errors.New()` which doesn't carry a lot of information.
		// User's can pass a different class from outside if they wish to
		// provide a custom title.
		"class": message,
	}
}

// ServeHTTP implements an http.Handler that recovers from a panic, reports the
// panic with the configured exporter and writes http.StatusInternalServerError
// (500) with a redacted message.
func (r *Reporter) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	defer func() { //nolint:contextcheck // Linter thinks we should pass in context from through ServeHTTP and into this function...but not going to change the function signature on the linter's whim. Maybe evaluate it deeper later.
		if err := recover(); err != nil {
			_ = r.Report(req.Context(), fmt.Errorf("panic: %+v", err), map[string]string{
				"method": req.Method,
				"url":    req.URL.String(),
			})

			http.Error(w, "exception handler has recovered from panic", http.StatusInternalServerError)
			return
		}
	}()

	if r.handler == nil {
		http.Error(w, "exception handler is not configured", http.StatusInternalServerError)
		return
	}

	r.handler.ServeHTTP(w, req)
}

func rollup(info string) string {
	hash := sha256.New()
	_, _ = io.WriteString(hash, info)
	return fmt.Sprintf("%x", hash.Sum(nil))
}

func newNullReporter(exporter Exporter) *Reporter {
	reporter, _ := NewReporter(
		WithExporter(exporter),
		WithApplication("nullreporter"),
	)

	return reporter
}

type nullExporter struct{}

func (n *nullExporter) Export(ctx context.Context, data []byte) error {
	return nil
}

// WithRollupInfo wraps err with rollup info to be used in grouping like exceptions.
func WithRollupInfo(err error, info string) error {
	if err == nil {
		return nil
	}
	return &withRollupInfoError{
		err:  err,
		info: info,
	}
}

type withRollupInfoError struct {
	err  error
	info string
}

func (w *withRollupInfoError) Error() string      { return w.err.Error() }
func (w *withRollupInfoError) Cause() error       { return w.err }
func (w *withRollupInfoError) Unwrap() error      { return w.err }
func (w *withRollupInfoError) RollupInfo() string { return w.info }

type rollupInfoFunc func(exception error) (info string, ok bool)

// RollupInfoer is an interface that can be implemented by exceptions to provide rollup information.
type RollupInfoer interface {
	// RollupInfo returns rollup info for exception.
	RollupInfo() string
}

// RollupInfo returns rollup info for exception if exception has a method `RollupInfo() string`.
func RollupInfo(exception error) (info string, ok bool) {
	if exception == nil {
		return "", false
	}
	var roller RollupInfoer
	ok = errors.As(exception, &roller)
	if !ok {
		return "", false
	}
	return roller.RollupInfo(), true
}
