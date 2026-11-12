package enhancedctx

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// MockLogger is a lightweight in-memory implementation of the telemetry logger
// interface used for tests; it records log lines into a string builder.
type MockLogger struct {
	Builder *strings.Builder
	level   log.Level
	Fields  []kvp.Field
	Name    string
}

// NewMockLogger constructs a new MockLogger with an empty buffer and info level.
func NewMockLogger() *MockLogger {
	return &MockLogger{
		Builder: &strings.Builder{},
		level:   log.InfoLevel,
		Fields:  []kvp.Field{},
		Name:    "",
	}
}

func (l *MockLogger) logLine(level log.Level, msg string, fields ...kvp.Field) {
	name := l.Name
	var nameStr string
	if name != "" {
		nameStr = "<" + name + "> "
	}

	fmt.Fprintf(l.Builder, "[%s] %s%s", level.String(), nameStr, msg)
	if len(fields) > 0 {
		for _, f := range fields {
			fmt.Fprintf(l.Builder, "; %s=%v", f.Key, f.String)
		}
	}
	if len(l.Fields) > 0 {
		for _, f := range l.Fields {
			fmt.Fprintf(l.Builder, "; %s=%v", f.Key, f.String)
		}
	}
	if l.Name != "" {
		fmt.Fprintf(l.Builder, "; logger=%s", l.Name)
	}
	l.Builder.WriteString("\n")
}

// Log logs a message at the provided level.
func (l *MockLogger) Log(level log.Level, msg string, fields ...kvp.Field) {
	l.logLine(level, msg, fields...)
}

// Debug logs a debug level message.
func (l *MockLogger) Debug(msg string, fields ...kvp.Field) {
	l.logLine(log.DebugLevel, msg, fields...)
}

// Info logs an info level message.
func (l *MockLogger) Info(msg string, fields ...kvp.Field) { l.logLine(log.InfoLevel, msg, fields...) }

// Warn logs a warning level message.
func (l *MockLogger) Warn(msg string, fields ...kvp.Field) { l.logLine(log.WarnLevel, msg, fields...) }
func (l *MockLogger) Error(msg string, fields ...kvp.Field) {
	l.logLine(log.ErrorLevel, msg, fields...)
}

// Fatal logs a fatal level message.
func (l *MockLogger) Fatal(msg string, fields ...kvp.Field) {
	l.logLine(log.FatalLevel, msg, fields...)
}

// WithFields returns a shallow copy of the logger with additional structured fields.
func (l *MockLogger) WithFields(fields ...kvp.Field) log.Logger {
	newLogger := *l
	newLogger.Fields = append(append([]kvp.Field{}, l.Fields...), fields...)
	return &newLogger
}

// WithError attaches an error to the logger (no-op for the mock implementation).
func (l *MockLogger) WithError(err error) log.Logger {
	newLogger := *l
	return &newLogger
}

// WithContext attaches a context to the logger (no-op for the mock implementation).
func (l *MockLogger) WithContext(ctx context.Context) log.Logger {
	newLogger := *l
	return &newLogger
}

// Named returns a new logger with the given component name appended.
func (l *MockLogger) Named(name string) log.Logger {
	newLogger := *l
	if l.Name != "" {
		newLogger.Name = l.Name + "." + name
	} else {
		newLogger.Name = name
	}
	return &newLogger
}

// WithLevel returns a copy of the logger with a different minimum log level.
func (l *MockLogger) WithLevel(level log.Level) log.Logger {
	newLogger := *l
	newLogger.level = level
	return &newLogger
}

// Sync flushes buffered logs (no-op for the mock implementation).
func (l *MockLogger) Sync() error { return nil }

// Level returns the current log level.
func (l *MockLogger) Level() log.Level { return l.level }
