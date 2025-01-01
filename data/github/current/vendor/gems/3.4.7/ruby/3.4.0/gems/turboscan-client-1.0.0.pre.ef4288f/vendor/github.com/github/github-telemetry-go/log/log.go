// Package log provides a structured logging interface for GitHub services.
package log

import (
	"context"
	"errors"
	"fmt"
	"io"
	"reflect"
	"sync"
	"syscall"
	"time"

	"go.uber.org/zap/zapio"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-config"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

// LogfmtError logs an error in logfmt format.
// Should be used for logging errors before the logger is initialized so they appear nicely in splunk.
func LogfmtError(body string, err error) {
	timestamp := time.Now().UTC().Format("2006-01-02T15:04:05.999999Z")
	errorMessage := err.Error()
	errorType := fmt.Sprintf("%T", err)
	severity := "ERROR"

	fmt.Printf("%s=%s %s=%q %s=%s exception.message=%q exception.type=%q\n",
		OtelFieldTimestamp, timestamp,
		OtelFieldBody, body,
		OtelFieldSeverityText, severity,
		errorMessage,
		errorType)
}

// internalLogger is the type you log through.  You are encouraged to use methods such as With, WithLevel,
// and Named to produce customized child loggers. If you need no customizations, then you can use
// the module-level functions such as Debug, Info, etc. to log with the default (unconfigured)
// logger instead.
type logger struct {
	config    *Config
	zapLogger *zap.Logger
	zapLevel  zap.AtomicLevel
}

// Logger is the interface that the Logger type implements. You should use this interface
// in function signatures wherever possible.
type Logger interface { //nolint:interfacebloat // This is a logging library, so we need to expose a lot of methods
	Log(level Level, msg string, fields ...kvp.Field)
	Debug(msg string, fields ...kvp.Field)
	Info(msg string, fields ...kvp.Field)
	Warn(msg string, fields ...kvp.Field)
	Error(msg string, fields ...kvp.Field)
	Fatal(msg string, fields ...kvp.Field)
	WithFields(fields ...kvp.Field) Logger
	WithError(err error) Logger
	WithContext(ctx context.Context) Logger
	Named(name string) Logger
	WithLevel(level Level) Logger
	Sync() error
	Level() Level
}

// NewFromEnv is an entrypoint for logging. It returns the configured logger.
// If you want to use this as a global logger, pass it to SetDefault.
// If other forms of telemetry are desired, use telemetry.NewFromEnv instead.
func NewFromEnv(opts ...Option) (Logger, error) {
	var cfg Config

	if err := config.Load(&cfg); err != nil {
		return nil, fmt.Errorf("error loading configuration: %w", err)
	}

	logger, err := processConfig(&cfg, opts...)
	if err != nil {
		return nil, fmt.Errorf("error configuring logging: %w", err)
	}
	return logger, nil
}

// NewFromConfig is an entrypoint for logging that takes in a configuration struct.
// It returns the configured logger. If you want to use this as a global logger,
// pass it to SetDefault.
// If other forms of telemetry are desired, use telemetry.NewFromEnv instead.
func NewFromConfig(cfg Config, opts ...Option) (Logger, error) { //nolint:gocritic // gocritic wants us to pass the config by pointer, which would be a breaking change
	logger, err := processConfig(&cfg, opts...)
	if err != nil {
		return nil, fmt.Errorf("error configuring logging: %w", err)
	}
	return logger, nil
}

// ToWriter allows you to turn a log into a Writer
// This is especially useful for process logging as you can redirect stdout
// and stderr to a log without having to process the output.
type ToWriter interface {
	Writer() io.WriteCloser
}

var _ ToWriter = &logger{}

func (l *logger) Writer() io.WriteCloser {
	return &zapio.Writer{Log: l.zapLogger, Level: toZapCoreLevel(l.config.level)}
}

// ---------------------------------------------------------------------------
// Logging methods
//
// Log logs a message at the provided level (note: this still respects the set log level)
//
// msg should be a fixed string (do not construct a dynamic string with fmt.Sprintf)
//
// Any number of kvp.Field arguments can be provided for your dynamic information (do not put them
// in the msg argument). Please see https://github.com/github/github-semantic-conventions/blob/main/go/README.md for
// helper functions to construct kvp.Field arguments.
func (l *logger) Log(level Level, msg string, fields ...kvp.Field) {
	l.zapLogger.Log(toZapCoreLevel(level), msg, fields...)
}

// Debug logs a message with the "SeverityText" field set to "debug" when the logging level is set to
// debug or lower.
//
// msg should be a fixed string (do not construct a dynamic string with fmt.Sprintf)
//
// Any number of kvp.Field arguments can be provided for your dynamic information (do not put them
// in the msg argument). Please see https://github.com/github/github-semantic-conventions/blob/main/go/README.md for
// helper functions to construct kvp.Field arguments.
//
// See `log.WithLevel()` function for details on how to configure logging level for the log library.
func (l *logger) Debug(msg string, fields ...kvp.Field) {
	l.zapLogger.Debug(msg, fields...)
}

// Info logs a message with the "SeverityText" field set to "info" when the logging level is set to
// info or lower.
//
// msg should be a fixed string (do not construct a dynamic string with fmt.Sprintf)
//
// Any number of kvp.Field arguments can be provided for your dynamic information (do not put them
// in the msg argument). Please see https://github.com/github/github-semantic-conventions/blob/main/go/README.md for
// helper functions to construct kvp.Field arguments.
//
// See `log.WithLevel()` function for details on how to configure logging level for the log library.
func (l *logger) Info(msg string, fields ...kvp.Field) {
	l.zapLogger.Info(msg, fields...)
}

// Warn logs a message with the "SeverityText" field set to "warn" when the logging level is set to
// warn or lower.
//
// msg should be a fixed string (do not construct a dynamic string with fmt.Sprintf)
//
// Any number of kvp.Field arguments can be provided for your dynamic information (do not put them
// in the msg argument). Please see https://github.com/github/github-semantic-conventions/blob/main/go/README.md for
// helper functions to construct kvp.Field arguments.
//
// See `log.WithLevel()` function for details on how to configure logging level for the log library.
func (l *logger) Warn(msg string, fields ...kvp.Field) {
	l.zapLogger.Warn(msg, fields...)
}

// Error logs a message with the "SeverityText" field set to "error" when the logging level is set to
// error or lower.
//
// msg should be a fixed string (do not construct a dynamic string with fmt.Sprintf)
//
// Any number of kvp.Field arguments can be provided for your dynamic information (do not put them
// in the msg argument). Please see https://github.com/github/github-semantic-conventions/blob/main/go/README.md for
// helper functions to construct kvp.Field arguments.
//
// See `log.WithLevel()` function for details on how to configure logging level for the log library.
func (l *logger) Error(msg string, fields ...kvp.Field) {
	l.zapLogger.Error(msg, fields...)
}

// Fatal logs a message with the "SeverityText" field set to "fatal" when the logging level is set to
// fatal or lower, and then calls `os.Exit(1)`.
//
// msg should be a fixed string (do not construct a dynamic string with fmt.Sprintf)
//
// Any number of kvp.Field arguments can be provided for your dynamic information (do not put them
// in the msg argument). Please see https://github.com/github/github-semantic-conventions/blob/main/go/README.md for
// helper functions to construct kvp.Field arguments.
//
// See `log.WithLevel()` function for details on how to configure logging level for the log library.
func (l *logger) Fatal(msg string, fields ...kvp.Field) {
	l.zapLogger.Fatal(msg, fields...)
}

// ---------------------------------------------------------------------------
// Utility Methods

// ignoreSyncErorr is a helper to help us ignore an internal go sys error we can't handle
//
// We're ignoreing syscall.EINVAL because:
// See https://github.com/uber-go/zap/issues/370
// and https://github.com/github/github-telemetry-go/issues/203
func ignoreSyncErorr(err error) error {
	// Ignoring EINVAL for Linux and EBADF for Mac and ENOTTY for Unix
	if errors.Is(err, syscall.EINVAL) || errors.Is(err, syscall.EBADF) || errors.Is(err, syscall.ENOTTY) {
		return nil
	}
	return err
}

// Sync flushes any buffered log entries. Applications should take care to call Sync before exiting.
func (l *logger) Sync() error {
	return ignoreSyncErorr(l.zapLogger.Sync())
}

// ---------------------------------------------------------------------------
// Configuration Methods that return new loggers

// Named returns a named *Logger. The name is included on all logged messages as an appended segment
// under the `InstrumentationScope` key. This method can be chained with other configuration
// methods.
//
// Loggers created via other methods will be unnamed by default. When Named function is used it will
// return a logger that can be used as a normal logger. Messages emitted from within the logging
// library itself will use the name `Telemetry`.
//
// Calling `Named` repeatedly creates a dot-separated name. For example:
// ```
// logger = log.Named("app")
// logger.Info("started")
// sublogger := logger.Named("subcomponent")
// sublogger.Info("processing")
// ```
// Will produce the output:
// ```
// Timestamp=2022-04-08T17:09:21.653Z SeverityText=INFO InstrumentationScope=app Body=started
// Timestamp=2022-04-08T17:09:21.653Z SeverityText=INFO InstrumentationScope=app.subcomponent Body=processing
// ```
func (l *logger) Named(name string) Logger {
	return &logger{
		config:    l.config,
		zapLogger: l.zapLogger.Named(name),
	}
}

// WithFields returns a *Logger configured to always output a set of kvp.Field arguments. This method
// should be used for short-lived loggers (for example logging across the span of a single request),
// not for loggers that live the life of an application. To log startup resources, instead just log
// them once at startup. Use the service id included in every log message to find your startup log
// messages later if needed. This method can be chained with other configuration methods.
//
// Example:
//
// ```
// logger := log.WithFields(fields.HttpServer.ClientIp(client_ip), fields.Http.Url(http_url))
// logger.Info("Begin processing request")
// ```
// Will produce console output that would look like this:
// ```
// Timestamp=2022-04-08T17:23:17.662Z SeverityText=INFO http.client_ip=1.2.3.4 http.url=https://myendpoint/whatever Body="Begin processing request"
// ```
func (l *logger) WithFields(fields ...kvp.Field) Logger {
	return &logger{
		config:    l.config,
		zapLogger: l.zapLogger.With(fields...),
	}
}

// WithLevel returns a *Logger configured with a specific log level. This method can be chained with
// other configuration methods.
//
// If the level is *not* set explicitly with this method, it will be set (in order of decreasing
// priority). Valid values in environment variables are: debug, info, warn, error, fatal.
// - The (nested) level value present in the OTEL_RESOURCE_ATTRIBUTES env var
// - The value in the GITHUB_TELEMETRY_LOGS_LEVEL env var
// - Default to info
//
// Valid values of level for this method are (in order of increasing level):
// - log.DebugLevel - all messages are output
// - log.InfoLevel  - info level messages and above are output
// - log.WarnLevel  - warn level messages and above are output
// - log.ErrorLevel - error level messages and above are output
// - log.FatalLevel - fatal level messages and above are output
func (l *logger) WithLevel(level Level) Logger {
	return configureLogger(l.config, WithLogLevel(level))
}

func (l *logger) SetLevel(level Level) {
	l.zapLevel.SetLevel(toZapCoreLevel(level))
}

// returns the current logging level for the logger
func (l *logger) Level() Level {
	return l.config.level
}

// WithError returns a logger with a set of configured semantic key fields for representing a Go
// error type.
//
// Unlike other configuration methods, WithError is intended to only be used for a single log entry
// (presumably of error level, but it could conceivably be at another log level). For example:
//
//	if err != nil {
//	    myLogger.WithError(err).Error("failed to retrieve the widget")
//	    // other error handling
//	}
//
// The reason we're using this configuration pattern instead of adding an error fields is that a
// single error expands into three separate entries:
// - exception.message: the message for the error or string representation of Error()
// - exception.type: the specific type of error this is, useful with wrapped errors
// - exception.stacktrace: the stack trace if the error implements the Stack() []byte interface (for example, one created by github.com/go-errors/errors)
func (l *logger) WithError(err error) Logger {
	if err == nil {
		return l
	}

	return l.WithFields(extractErrorFields(err)...)
}

func extractErrorFields(err error) []kvp.Field {
	f := make([]kvp.Field, 0, 3)
	f = append(f, kvp.String("exception.message", err.Error()), kvp.String("exception.type", reflect.TypeOf(err).String()))

	// if the error carries a stack trace, add it to the fields
	switch errWithStack := err.(type) { //nolint:errorlint // We're not worried abut wrapped errors here, but do need the type info
	// match the interface of github.com/go-errors/errors
	case interface{ Stack() []byte }:
		f = append(f, kvp.String("exception.stacktrace", string(errWithStack.Stack())))
	// match the interface of github.com/pkg/errors, as well as other 3rd-party
	// error libraries that use the convention of rendering stack traces via the Format method
	case fmt.Formatter:
		f = append(f, kvp.String("exception.stacktrace", fmt.Sprintf("%+v", errWithStack)))
	}

	return f
}

// WithContext returns a logger with a spanId, traceId and traceFlags appended in logger fields
// which are fetched from provided context.
//
// WithContext is useful when you want to use logger in the span.
// The usage would look like
// If no Span is currently set in ctx or if it's nil an implementation of a Span that
// performs no operations is returned.
//
//	log.WithContext(ctx).Info("This is a sample info message with context")
func (l *logger) WithContext(ctx context.Context) Logger {
	flds := make([]kvp.Field, 0)

	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		spanContext := span.SpanContext()

		if spanContext.IsValid() {
			spanID := kvp.String(OtelFieldSpanId, spanContext.SpanID().String())
			traceID := kvp.String(OtelFieldTraceId, spanContext.TraceID().String())
			traceFlags := kvp.Int(OtelFieldTraceFlags, int(spanContext.TraceFlags())) // byte converted to Int so it can be stored
			flds = append(flds, []kvp.Field{spanID, traceID, traceFlags}...)
		} else {
			l.Debug("Found spanContext but is not valid")
		}
	} else {
		l.Debug("No active span found in the provided context")
	}

	// TODO: https://github.com/github/frameworks-services/issues/382
	// https://opentelemetry.io/docs/reference/specification/logs/data-model/#example-log-records
	// For example, all 3 fields here should be top-level fields in otel JSON
	return l.WithFields(flds...)
}

// ---------------------------------------------------------------------------
// Global static logging functions

// Debug uses an unconfigured global logger. This is fine to use directly if you don't need any
// special configuration. See the documentation for the (*Logger) method with the same name for more
// details.
func Debug(msg string, fields ...kvp.Field) {
	ensureInitialized().Debug(msg, fields...)
}

// Info uses an unconfigured global logger. This is fine to use directly if you don't need any
// special configuration. See the documentation for the (*Logger) method with the same name for more
// details.
func Info(msg string, fields ...kvp.Field) {
	ensureInitialized().Info(msg, fields...)
}

// Warn uses an unconfigured global logger. This is fine to use directly if you don't need any
// special configuration. See the documentation for the (*Logger) method with the same name for more
// details.
func Warn(msg string, fields ...kvp.Field) {
	ensureInitialized().Warn(msg, fields...)
}

// Error uses an unconfigured global logger. This is fine to use directly if you don't need any
// special configuration. See the documentation for the (*Logger) method with the same name for more
// details.
func Error(msg string, fields ...kvp.Field) {
	ensureInitialized().Error(msg, fields...)
}

// Fatal uses an unconfigured global logger. This is fine to use directly if you don't need any
// special configuration. See the documentation for the (*Logger) method with the same name for more
// details.
func Fatal(msg string, fields ...kvp.Field) {
	ensureInitialized().Fatal(msg, fields...)
}

// ---------------------------------------------------------------------------
// Global utility functions

// Sync flushes any buffered log entries. Applications should take care to call Sync before exiting.
func Sync() error {
	return ensureInitialized().Sync()
}

// SetDefault sets the default (global) logger to a specific value.
func SetDefault(l Logger) {
	defaultLoggerLock.Lock()
	defaultLogger = l
	defaultLoggerLock.Unlock()
}

// ---------------------------------------------------------------------------
// Global configuration functions (that return new loggers)

// Named has the same behavior as the (*Logger) method of the same name. Please see that
// documentation for more details.
//
// Note: This function returns a new logger--it does *not* configure the global logger.
func Named(name string) Logger {
	return ensureInitialized().Named(name)
}

// NewNullLogger returns a logger which will ignore all log output.
func NewNullLogger() Logger {
	return nullLogger
}

// WithFields has the same behavior as the (*Logger) method of the same name. Please see that
// documentation for more details.
//
// Note: This function returns a new logger--it does *not* configure the global logger.
func WithFields(fields ...kvp.Field) Logger {
	return ensureInitialized().WithFields(fields...)
}

// WithLevel has the same behavior as the (*Logger) method of the same name. Please see that
// documentation for more details.
//
// Note: This function returns a new logger--it does *not* configure the global logger.
func WithLevel(level Level) Logger {
	return ensureInitialized().WithLevel(level)
}

// WithError has the same behavior as the (*Logger) method of the same name. Please see that
// documentation for more details.
//
// Note: This function returns a new logger--it does *not* configure the global logger.
func WithError(err error) Logger {
	return ensureInitialized().WithError(err)
}

// WithContext has the same behavior as the (*Logger) method of the same name. Please see that
// documentation for more details.
//
// Note: This function returns a new logger--it does *not* configure the global logger.
func WithContext(ctx context.Context) Logger {
	return ensureInitialized().WithContext(ctx)
}

// ---------------------------------------------------------------------------
// Helpers

// Anything that wishes to set defaultLogger must acquire a lock first. Use log.SetDefault which
// will do it for you!
var defaultLoggerLock sync.Mutex
var defaultLogger Logger

var nullLogger = &logger{
	config:    &Config{},
	zapLogger: zap.NewNop(),
}

// Ensure the global logger is initialized
func ensureInitialized() Logger {
	defaultLoggerLock.Lock()
	defer defaultLoggerLock.Unlock()
	if defaultLogger == nil {
		defaultLogger = nullLogger
	}
	return defaultLogger
}
