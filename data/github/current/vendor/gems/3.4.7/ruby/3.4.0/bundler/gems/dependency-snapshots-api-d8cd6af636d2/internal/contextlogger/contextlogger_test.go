package contextlogger

import (
	"context"
	"fmt"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/log/logtest"
	"go.uber.org/zap/zapcore"
	"strings"
	"testing"

	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/stretchr/testify/require"
)

func TestContextLogger_Basic(t *testing.T) {
	originalCtx := context.Background()
	testLogger, buffer := logtest.NewTestLogger(t)
	log.SetDefault(testLogger)
	logger := Get(originalCtx)
	logger.Info("Sample log message")

	requireLogLevel(t, buffer, log.InfoLevel)
	requireBody(t, buffer, "Sample log message")
}

func TestContextLogger_ExpectedCommonFields(t *testing.T) {
	originalCtx := context.Background()
	testLogger, buffer := logtest.NewTestLogger(t)
	log.SetDefault(testLogger)
	originalCtx = requestid.WithGitHubRequestID(originalCtx, "samplerequestid")
	logger := Get(originalCtx)
	logger.Info("Sample log message")

	requireFields(t, buffer, kvp.String("request_id", "samplerequestid"))
}

func TestContextLogger_NoRequestIDWhenUnknown(t *testing.T) {
	originalCtx := context.Background()
	testLogger, buffer := logtest.NewTestLogger(t)
	log.SetDefault(testLogger)
	logger := Get(originalCtx)

	logger.Info("Sample log message")
	require.NotContains(t, buffer.String(), "samplerequestid")
}

func TestContextLogger_ChainedFields(t *testing.T) {
	originalCtx := context.Background()
	testLogger, buffer := logtest.NewTestLogger(t)
	log.SetDefault(testLogger)
	interimField := kvp.String("some", "field")
	interimCtx := ContextWithFields(originalCtx, interimField)
	interimCommonFields := commonFields(interimCtx)
	lastField1 := kvp.String("some", "thingelse")
	lastField2 := kvp.String("other", "field")
	lastCtx := ContextWithFields(originalCtx, lastField1, lastField2)
	lastCommonFields := commonFields(lastCtx)

	interimLogger := Get(interimCtx)

	interimLogger.Info("Sample log message")

	requireBody(t, buffer, "Sample log message")
	requireLogLevel(t, buffer, log.InfoLevel)
	requireFields(t, buffer, append(interimCommonFields, interimField)...)

	lastLogger := Get(lastCtx)

	lastLogger.Info("Sample log message 1")

	requireBody(t, buffer, "Sample log message 1")
	requireLogLevel(t, buffer, log.InfoLevel)
	requireFields(t, buffer, append(lastCommonFields, lastField1, lastField2)...)

	// Make sure interim context still outputs the same thing, as a CYA
	interimLogger = Get(interimCtx)
	interimLogger.Info("Sample log message 2")

	requireBody(t, buffer, "Sample log message 2")
	requireLogLevel(t, buffer, log.InfoLevel)
	requireFields(t, buffer, append(interimCommonFields, interimField)...)
}

func requireLogLevel(t *testing.T, buffer *logtest.Buffer, level log.Level) {
	t.Helper()
	require.Contains(t, buffer.String(), fmt.Sprintf("SeverityText=%s", strings.ToUpper(level.String())))
}

func requireFields(t *testing.T, buffer *logtest.Buffer, fields ...kvp.Field) {
	t.Helper()
	for _, field := range fields {
		var value interface{}
		switch field.Type {
		case zapcore.Int32Type, zapcore.Int16Type, zapcore.Int64Type, zapcore.Int8Type:
			value = field.Integer
		case zapcore.StringType:
			value = field.String
		default:
			value = field.Interface
		}
		require.Contains(t, buffer.String(), fmt.Sprintf("%s=%v", field.Key, value))
	}
}

func requireBody(t *testing.T, buffer *logtest.Buffer, body string) {
	t.Helper()
	require.Contains(t, buffer.String(), fmt.Sprintf("Body=\"%s\"", body))
}
