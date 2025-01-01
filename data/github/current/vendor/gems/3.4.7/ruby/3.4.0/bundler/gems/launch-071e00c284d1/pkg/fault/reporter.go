package fault

import "context"

// Reporter receives events from faults to use for logging, stats, and other custom reporting.
type Reporter interface {
	Report(ctx context.Context, name string, state InjectorState)
}

// NoopReporter is a reporter that does nothing.
type NoopReporter struct{}

// NewNoopReporter returns a new NoopReporter.
func NewNoopReporter() *NoopReporter {
	return &NoopReporter{}
}

// Report does nothing.
func (r *NoopReporter) Report(_ context.Context, _ string, _ InjectorState) {}
