package testutils

import (
	"sync"

	"github.com/github/github-telemetry-go/log/logtest"

	"github.com/github/launch/observability/logger"
)

// NewRecordingLogger returns a logger which records its log messages
func NewRecordingLogger() RecordingLogger {
	var buffer logtest.Buffer
	r := RecordingLogger{
		builder: &threadSafeBuilder{buf: &buffer},
	}
	r.Logger = logger.New(&logger.Config{
		Writer:   &buffer,
		Debug:    true,
		Reporter: logger.NullReporter(),
	})
	return r
}

type RecordingLogger struct {
	builder *threadSafeBuilder
	Logger  logger.Logger
}

func (r *RecordingLogger) String() string {
	r.builder.Lock()
	defer r.builder.Unlock()
	return r.builder.buf.String()
}

func (r *RecordingLogger) Reset() {
	r.builder.Lock()
	defer r.builder.Unlock()
	r.builder.buf.Reset()
}

type threadSafeBuilder struct {
	sync.Mutex
	buf *logtest.Buffer
}

func (t *threadSafeBuilder) Write(p []byte) (n int, err error) {
	t.Lock()
	defer t.Unlock()
	return t.buf.Write(p)
}
