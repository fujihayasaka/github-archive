package logger

import (
	"bytes"
	"context"
	"io"
	"testing"

	"github.com/stretchr/testify/assert"
)

// testExporter is just pared down from the examples in the go-exceptions library for testing.
// It will write to the passed in writer.
type testExporter struct {
	w io.Writer
}

// Export exports the given data
func (e *testExporter) Export(ctx context.Context, data []byte) error {
	_, err := e.w.Write(data)
	return err
}

func TestQueuedExporter(t *testing.T) {
	var buf bytes.Buffer
	bufferedExporter := &testExporter{&buf}

	errorHandler := func(err error) {
		t.Error(err)
	}
	queuedExporter := newQueuedExporter(bufferedExporter, errorHandler, 10)

	queuedExporter.Export(context.Background(), []byte("hello world"))

	queuedExporter.Close() // Closing here empties the queue, avoiding a data race in the test

	assert.Equal(t, "hello world", buf.String())
}

func TestQueuedExporter_QueueLength(t *testing.T) {
	var buf bytes.Buffer
	bufferedExporter := &testExporter{
		w: &buf,
	}

	startChan := make(chan bool, 1)
	queuedExporter := &queuedExporter{
		exporter:    bufferedExporter,
		queueLength: 2,
		errorHandler: func(err error) {
			panic(err)
		},
		startQueue: func() {
			<-startChan // Don't start the queue until this is written to
		},
	}

	queuedExporter.Export(context.Background(), []byte("hello1 "))
	queuedExporter.Export(context.Background(), []byte("hello2 "))
	queuedExporter.Export(context.Background(), []byte("hello3 ")) // Should be dropped
	queuedExporter.Export(context.Background(), []byte("hello4 ")) // Should be dropped

	startChan <- true      // Start the queue
	queuedExporter.Close() // Closing here empties the queue, avoiding a data race in the test

	assert.Equal(t, "hello1 hello2 ", buf.String())
}
