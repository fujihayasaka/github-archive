package testutil

import (
	"bytes"
	"context"
	"database/sql/driver"
	"fmt"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/stretchr/testify/require"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// Matches any time.Time instance in a sqlmock arguments list
type AnyTime struct{}

// Match satisfies sqlmock.Argument interface
func (a AnyTime) Match(v driver.Value) bool {
	_, ok := v.(time.Time)
	return ok
}

// Matches any time later than the given one
type AfterTime struct {
	time.Time
}

// Match satisfies sqlmock.Argument interface
func (a AfterTime) Match(v driver.Value) bool {
	t, ok := v.(time.Time)
	return ok && t.After(a.Time)
}

func MatchTimeAfter(t time.Time) sqlmock.Argument {
	return AfterTime{t}
}

func CreateTestConfig(t *testing.T) *config.Config {
	t.Helper()

	cfg, err := config.Load("test_run_fake_build_commit")
	require.NoError(t, err)

	cfg.DB = "dependency_snapshots_test"
	return cfg
}

// Compile-time assertion that TestLogger implements log.Logger
var _ log.Logger = (*TestLogger)(nil)

// TestLogger is a minimal implementation of the Logger interface for capturing logs in tests.
type TestLogger struct {
	Buffer *bytes.Buffer
	level  log.Level
}

func NewTestLogger() *TestLogger {
	return &TestLogger{
		Buffer: &bytes.Buffer{},
		level:  log.DebugLevel,
	}
}

func (l *TestLogger) Log(level log.Level, msg string, fields ...kvp.Field) {
	fmt.Fprintf(l.Buffer, "[%s] %s", level.String(), msg)
	if len(fields) > 0 {
		fmt.Fprintf(l.Buffer, " ")
		for _, f := range fields {
			fmt.Fprintf(l.Buffer, "%v ", f)
		}
	}
	l.Buffer.WriteByte('\n')
}

func (l *TestLogger) Debug(msg string, fields ...kvp.Field) { l.Log(log.DebugLevel, msg, fields...) }
func (l *TestLogger) Info(msg string, fields ...kvp.Field)  { l.Log(log.InfoLevel, msg, fields...) }
func (l *TestLogger) Warn(msg string, fields ...kvp.Field)  { l.Log(log.WarnLevel, msg, fields...) }
func (l *TestLogger) Error(msg string, fields ...kvp.Field) { l.Log(log.ErrorLevel, msg, fields...) }
func (l *TestLogger) Fatal(msg string, fields ...kvp.Field) { l.Log(log.FatalLevel, msg, fields...) }

func (l *TestLogger) WithFields(fields ...kvp.Field) log.Logger  { return l }
func (l *TestLogger) WithError(err error) log.Logger             { return l }
func (l *TestLogger) WithContext(ctx context.Context) log.Logger { return l }
func (l *TestLogger) Named(name string) log.Logger               { return l }
func (l *TestLogger) WithLevel(level log.Level) log.Logger       { l.level = level; return l }
func (l *TestLogger) Sync() error                                { return nil }
func (l *TestLogger) Level() log.Level                           { return l.level }

// OperationCallCount counts how many times a specific operation was logged in the provided log buffer.
// It looks for lines that contain "Ending <operationName>" to determine the count. The operationName
// should match the argument passed to the contextlogger.LogStartAndStop function.
func OperationCallCount(logBuffer *bytes.Buffer, operationName string) int {
	lines := bytes.Split(logBuffer.Bytes(), []byte("\n"))
	count := 0
	for _, line := range lines {
		if bytes.Contains(line, []byte("Ending "+operationName)) {
			count++
		}
	}
	return count
}
