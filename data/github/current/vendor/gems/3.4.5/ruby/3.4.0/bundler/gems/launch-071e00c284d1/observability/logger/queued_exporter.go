package logger

import (
	"context"
	"fmt"
	"sync"

	"github.com/github/go-exceptions"
)

type needle struct {
	ctx  context.Context
	data []byte
}

// queuedExporter wraps an exporter, but queuing the Export calls instead of them being syncronous.
type queuedExporter struct {
	exporter     exceptions.Exporter
	queueLength  int // Max queue length, after this needles are dropped
	errorHandler func(error)

	needles    chan needle
	once       sync.Once
	done       chan struct{}
	startQueue func() // A function that is run before starting to work the queue. Used for testing mostly, default func is no-op
}

func newQueuedExporter(ex exceptions.Exporter, errorHandler func(error), q int) *queuedExporter {
	return &queuedExporter{
		exporter:     ex,
		queueLength:  q,
		errorHandler: errorHandler,
	}
}

// Close shuts down the exporter. Calling Report after Close will panic.
func (e *queuedExporter) Close() {
	if e.needles != nil {
		close(e.needles)
	}
	if e.done != nil {
		<-e.done
	}
}

// Export submits the given needle to the async reporting queue, and returns
// immediately. Errors when submitting the needle will be silently ignored.  If
// the needles queue is full, the needle will also be silently dropped.
func (e *queuedExporter) Export(ctx context.Context, data []byte) error {
	e.once.Do(e.async)

	select {
	case e.needles <- needle{ctx, data}:
	default:
	}
	return nil
}

func (e *queuedExporter) async() {
	if e.queueLength == 0 {
		e.queueLength = 16
	}
	e.needles = make(chan needle, e.queueLength)
	e.done = make(chan struct{})

	go func() {
		if e.startQueue != nil { // Zero value of a function is nil
			e.startQueue()
		}
		for needle := range e.needles {
			if err := e.exporter.Export(needle.ctx, needle.data); err != nil {
				if e.errorHandler != nil {
					e.errorHandler(err)
				} else {
					fmt.Printf("error reporting haystack needle: %s", err)
				}
			}
		}

		close(e.done)
	}()
}
