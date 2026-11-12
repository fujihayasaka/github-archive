package jobservice

import (
	"context"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/jobs"
	jobevents "github.com/github/sweagentd/internal/jobs/jobevents"
	"github.com/github/sweagentd/internal/observability"
)

// JobEventEmitter defines the interface for emitting job-related events.
// This interface can be mocked for testing to verify event emissions without
// needing a full Hydro client setup.
type JobEventEmitter interface {
	// EmitJobUpdated emits a JobUpdated event for the given job.
	EmitJobUpdated(ctx context.Context, job *jobs.Job, obsv observability.Exporters)
	// EmitJobProgress emits a JobProgress event for the given job.
	EmitJobProgress(ctx context.Context, job *jobs.Job, progress *jobevents.ProgressUpdate, obsv observability.Exporters)
}

// HydroJobEventEmitter is the default implementation of JobEventEmitter
// that publishes events to Hydro.
type HydroJobEventEmitter struct {
	publisher *hydro.Publisher
}

// NewHydroJobEventEmitter creates a new HydroJobEventEmitter with the given Hydro publisher.
func NewHydroJobEventEmitter(publisher *hydro.Publisher) *HydroJobEventEmitter {
	return &HydroJobEventEmitter{publisher: publisher}
}

// EmitJobUpdated emits a JobUpdated event for the given job.
// Errors are logged and intentionally ignored since this is fire-and-forget telemetry.
func (e *HydroJobEventEmitter) EmitJobUpdated(ctx context.Context, job *jobs.Job, obsv observability.Exporters) {
	err := jobevents.EmitJobUpdated(e.publisher, job)
	if err != nil {
		obsv.Logger.WithError(err).Warn("failed to emit JobUpdated event")
	}
}

// EmitJobProgress emits a JobProgress event for the given job.
// Errors are logged and intentionally ignored since this is fire-and-forget telemetry.
func (e *HydroJobEventEmitter) EmitJobProgress(ctx context.Context, job *jobs.Job, progress *jobevents.ProgressUpdate, obsv observability.Exporters) {
	err := jobevents.EmitJobProgress(e.publisher, job, progress)
	if err != nil {
		obsv.Logger.WithError(err).Warn("failed to emit JobProgress event")
	}
}

// noopJobEventEmitter is a no-op implementation of JobEventEmitter
// that discards all events. Used as a default when no emitter is provided.
type noopJobEventEmitter struct{}

// EmitJobUpdated is a no-op implementation.
func (e *noopJobEventEmitter) EmitJobUpdated(_ context.Context, _ *jobs.Job, _ observability.Exporters) {
}

// EmitJobProgress is a no-op implementation.
func (e *noopJobEventEmitter) EmitJobProgress(_ context.Context, _ *jobs.Job, _ *jobevents.ProgressUpdate, _ observability.Exporters) {
}
