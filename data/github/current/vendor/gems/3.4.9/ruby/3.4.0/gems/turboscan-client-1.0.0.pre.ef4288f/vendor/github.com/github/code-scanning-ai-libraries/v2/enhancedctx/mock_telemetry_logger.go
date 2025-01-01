package enhancedctx

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// MockLogger is a simple in-memory logger used for tests.
type MockLogger struct {
	Builder *strings.Builder
	level   log.Level
	Fields  []kvp.Field
	Name    string
}

// NewMockLogger creates a new MockLogger writing to an internal strings.Builder.
func NewMockLogger() *MockLogger {
	return &MockLogger{
		Builder: &strings.Builder{},
		level:   log.InfoLevel,
		Fields:  []kvp.Field{},
		Name:    "",
	}
}

func (l *MockLogger) logLine(level log.Level, msg string, fields ...kvp.Field) {
	// build a single log line in the builder; errors are ignored in tests
	name := l.Name
	var nameStr string
	if name != "" {
		nameStr = "<" + name + "> "
	}
	_, _ = fmt.Fprintf(l.Builder, "[%s] %s%s", level.String(), nameStr, msg)
	if len(fields) > 0 {
		for _, f := range fields {
			_, _ = fmt.Fprintf(l.Builder, "; %s=%v", f.Key, f.String)
		}
	}
	if len(l.Fields) > 0 {
		for _, f := range l.Fields {
			_, _ = fmt.Fprintf(l.Builder, "; %s=%v", f.Key, f.String)
		}
	}
	if l.Name != "" {
		_, _ = fmt.Fprintf(l.Builder, "; logger=%s", l.Name)
	}
	_, _ = l.Builder.WriteString("\n")
}

// Log logs a message at the provided level.
func (l *MockLogger) Log(level log.Level, msg string, fields ...kvp.Field) {
	l.logLine(level, msg, fields...)
}

// Debug logs a message at Debug level.
func (l *MockLogger) Debug(msg string, fields ...kvp.Field) {
	l.logLine(log.DebugLevel, msg, fields...)
}

// Info logs a message at Info level.
func (l *MockLogger) Info(msg string, fields ...kvp.Field) { l.logLine(log.InfoLevel, msg, fields...) }

// Warn logs a message at Warn level.
func (l *MockLogger) Warn(msg string, fields ...kvp.Field) { l.logLine(log.WarnLevel, msg, fields...) }
func (l *MockLogger) Error(msg string, fields ...kvp.Field) {
	l.logLine(log.ErrorLevel, msg, fields...)
}

// Fatal logs a message at Fatal level.
func (l *MockLogger) Fatal(msg string, fields ...kvp.Field) {
	l.logLine(log.FatalLevel, msg, fields...)
}

// WithFields returns a copy of the logger with additional fields.
func (l *MockLogger) WithFields(fields ...kvp.Field) log.Logger {
	newLogger := *l
	newLogger.Fields = append(append([]kvp.Field{}, l.Fields...), fields...)
	return &newLogger
}

// WithError returns a copy of the logger tagged with an error.
func (l *MockLogger) WithError(err error) log.Logger {
	newLogger := *l
	return &newLogger
}

// WithContext returns a copy of the logger associated with a context.
func (l *MockLogger) WithContext(ctx context.Context) log.Logger {
	newLogger := *l
	return &newLogger
}

// Named returns a copy of the logger with a sub-name.
func (l *MockLogger) Named(name string) log.Logger {
	newLogger := *l
	if l.Name != "" {
		newLogger.Name = l.Name + "." + name
	} else {
		newLogger.Name = name
	}
	return &newLogger
}

// WithLevel returns a copy of the logger with a new minimum level.
func (l *MockLogger) WithLevel(level log.Level) log.Logger {
	newLogger := *l
	newLogger.level = level
	return &newLogger
}

// Sync is a no-op for MockLogger.
func (l *MockLogger) Sync() error { return nil }

// Level returns the configured level.
func (l *MockLogger) Level() log.Level { return l.level }
