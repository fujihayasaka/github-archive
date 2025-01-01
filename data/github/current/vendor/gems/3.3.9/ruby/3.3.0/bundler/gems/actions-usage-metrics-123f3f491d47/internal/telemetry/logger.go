package telemetry

import (
	"context"
	"fmt"
	"sync/atomic"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

type logMetrics struct {
	client     stats.Client
	debugCount atomic.Int64
	infoCount  atomic.Int64
	warnCount  atomic.Int64
	errorCount atomic.Int64
	fatalCount atomic.Int64
}

type Logger struct {
	base    log.Logger
	errors  []error
	done    chan struct{}
	metrics *logMetrics
}

var _ log.Logger = &Logger{}

func NewLogger(base log.Logger, statsClient stats.Client) (*Logger, error) {
	l := &Logger{
		base:   base,
		errors: nil,
		done:   make(chan struct{}),
		metrics: &logMetrics{
			client: statsClient,
		},
	}

	// Set up metrics collection
	go func() {
		ticker := time.NewTicker(time.Second * 10)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				l.publishMetrics()
			case <-l.done:
				ticker.Stop()
				return
			}
		}
	}()

	return l, nil
}

func (l *Logger) Shutdown() {
	close(l.done)
}

func (l *Logger) Log(level log.Level, msg string, fields ...kvp.Field) {
	switch level {
	case log.DebugLevel:
		l.metrics.debugCount.Add(1)
	case log.InfoLevel:
		l.metrics.infoCount.Add(1)
	case log.WarnLevel:
		l.metrics.warnCount.Add(1)
	case log.ErrorLevel:
		l.metrics.errorCount.Add(1)
	case log.FatalLevel:
		l.metrics.fatalCount.Add(1)
	}

	l.logAnyErrors(level)
	l.base.Log(level, msg, fields...)
}

func (l *Logger) Level() log.Level {
	return l.base.Level()
}

func (l *Logger) Debug(msg string, fields ...kvp.Field) {
	l.Log(log.DebugLevel, msg, fields...)
}

func (l *Logger) Info(msg string, fields ...kvp.Field) {
	l.Log(log.InfoLevel, msg, fields...)
}

func (l *Logger) Warn(msg string, fields ...kvp.Field) {
	l.Log(log.WarnLevel, msg, fields...)
}

func (l *Logger) Error(msg string, fields ...kvp.Field) {
	l.Log(log.ErrorLevel, msg, fields...)
}

func (l *Logger) Fatal(msg string, fields ...kvp.Field) {
	l.Log(log.FatalLevel, msg, fields...)
}

func (l *Logger) WithFields(fields ...kvp.Field) log.Logger {
	return l.with(l.base.WithFields(fields...))
}

func (l *Logger) WithError(err error) log.Logger {
	if err != nil {
		// err can't be nil when we report, see logAnyErrors and https://github.com/github/go-exceptions/blob/ae84717fe9d56a9c2716b017357f7a094bfb06fa/exceptions.go#L488
		l.errors = append(l.errors, err)
	}
	return l.with(l.base.WithError(err))
}

func (l *Logger) WithContext(ctx context.Context) log.Logger {
	// Extract any of our own logging fields from the context added via AddLoggingFields
	var fields []kvp.Field
	if contextFields, ok := FieldsFromContext(ctx); ok {
		fields = contextFields
	}

	// Produce a new github-telemetry-go logger, which has tracing fields extracted from the context
	// and any of our customer fields
	newLogger := l.base.WithContext(ctx)
	if len(fields) > 0 {
		newLogger = newLogger.WithFields(fields...)
	}

	// Produce a new AUM telemetry.Logger wrapper
	return l.with(newLogger)
}

func (l *Logger) WithLevel(level log.Level) log.Logger {
	return l.with(l.base.WithLevel(level))
}

func (l *Logger) Named(name string) log.Logger {
	return l.with(l.base.Named(name))
}

func (l *Logger) Sync() error {
	return l.base.Sync()
}

func ToLogLevel(level string, defaultLevel log.Level) log.Level {
	switch level {
	case log.DebugLevel.String():
		return log.DebugLevel
	case log.InfoLevel.String():
		return log.InfoLevel
	case log.WarnLevel.String():
		return log.WarnLevel
	case log.ErrorLevel.String():
		return log.ErrorLevel
	case log.FatalLevel.String():
		return log.FatalLevel
	default:
		log.Error(fmt.Sprintf("invalid log level %s", level))
		return defaultLevel
	}
}

func (l *Logger) logAnyErrors(level log.Level) {
	if len(l.errors) > 0 && (level == log.ErrorLevel || level == log.FatalLevel) {
		for _, err := range l.errors {
			reportError := Report(context.Background(), err)
			if reportError != nil {
				l.base.WithError(reportError).Error("failed to report error")
			}
		}
		l.errors = nil
	}
}

func (l *Logger) publishMetrics() {
	if l.metrics.client == nil {
		return
	}

	sendStats(l.metrics.client, log.DebugLevel, &l.metrics.debugCount)
	sendStats(l.metrics.client, log.InfoLevel, &l.metrics.infoCount)
	sendStats(l.metrics.client, log.WarnLevel, &l.metrics.warnCount)
	sendStats(l.metrics.client, log.ErrorLevel, &l.metrics.errorCount)
	sendStats(l.metrics.client, log.FatalLevel, &l.metrics.fatalCount)
}

func sendStats(client stats.Client, level log.Level, counter *atomic.Int64) {
	value := counter.Swap(0)
	if value > 0 {
		client.Counter("log.message.count", stats.Tags{"level": level.String()}, value)
	}
}

func (l *Logger) with(logger log.Logger) log.Logger {
	// metrics stats from derived loggers will be wrapped up into the parent logger
	return &Logger{
		base:    logger,
		errors:  l.errors,
		metrics: l.metrics,
	}
}
