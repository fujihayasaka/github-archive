// Package mock implements a Mock Exporter to be used with tests.
package mock

import (
	"context"
	"sync"
)

// Exporter defines a Mock Exporter to be used with tests for projects using
// the exceptions-go.Exporter interface.
type Exporter struct {
	exportFn      func(ctx context.Context, data []byte) error
	exportInvoked bool

	mu sync.Mutex // protects invoked booleans
}

// NewExporter returns a new Exporter that satisfies `go-exceptions.Exporter` interface. The given function is used to mock calls for the export() function.
func NewExporter(fn func(ctx context.Context, data []byte) error) *Exporter {
	return &Exporter{
		exportFn: fn,
	}
}

// IsInvoked exports back whether the export function was executed or not.
func (e *Exporter) IsInvoked() bool {
	e.mu.Lock()
	invoked := e.exportInvoked
	e.mu.Unlock()

	return invoked
}

// Export exports the given exception via the given mock function.
func (e *Exporter) Export(ctx context.Context, data []byte) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.exportInvoked = true
	return e.exportFn(ctx, data)
}
