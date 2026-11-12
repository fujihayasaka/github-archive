package jobevents

import (
	"context"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
)

// NoopEmitter is a no-op implementation of the JobEventEmitter interface for testing.
type NoopEmitter struct{}

// EmitJobUpdated does nothing.
func (n *NoopEmitter) EmitJobUpdated(_ context.Context, _ *jobs.Job, _ observability.Exporters) {}

// EmitJobProgress does nothing.
func (n *NoopEmitter) EmitJobProgress(_ context.Context, _ *jobs.Job, _ *ProgressUpdate, _ observability.Exporters) {
}
