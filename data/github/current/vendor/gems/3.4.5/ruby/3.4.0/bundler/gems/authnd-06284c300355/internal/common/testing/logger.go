package testing

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/log"
)

type testLogWriter struct {
	t *testing.T
}

func (w *testLogWriter) Write(p []byte) (n int, err error) {
	s := string(p)
	// write to test logs (i.e. `t.Log`)
	w.t.Log(s)
	return len(s), nil
}

func (w *testLogWriter) Sync() error {
	return nil
}

// NewLogger creates a new logger for unit/integration tests.  By default, logs are
// discarded. However, it writes to Go test logs when the `-v` flag is provided.
func NewLogger(t *testing.T) log.Logger {
	if testing.Verbose() {
		logger, err := log.NewFromConfig(
			log.Config{LogLevel: "debug"},
			log.WithWriteSyncer(&testLogWriter{t}),
		)
		if err != nil {
			panic(fmt.Sprintf("failed to construct test logger: %v", err))
		}
		return logger
	}

	return log.NewNullLogger()
}

// NewLoggerContext creates context with an attached logger.  By default, logs are
// discarded. However, it writes to Go test logs when the `-v` flag is provided.
func NewLoggerContext(t *testing.T) context.Context {
	return diagnostics.WithLogger(context.Background(), NewLogger(t))
}
