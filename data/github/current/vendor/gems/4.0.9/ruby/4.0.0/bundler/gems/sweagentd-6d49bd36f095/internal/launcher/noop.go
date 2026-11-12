package launcher

import (
	"context"

	"github.com/github/sweagentd/internal/observability"
)

// NoopLauncher is a launcher that does nothing, used for testing.
type NoopLauncher struct {
	obsv                observability.Exporters
	LaunchAgentCalls    []LaunchAgentOpts
	TerminateAgentCalls []TerminateAgentOpts
	LaunchAgentError    error
	TerminateAgentError error
}

// Ensure that NoopLauncher implements AgentLauncher
var _ AgentLauncher = &NoopLauncher{}

// NewNoopLauncher creates a new NoopLauncher.
func NewNoopLauncher(obsv observability.Exporters) *NoopLauncher {
	return &NoopLauncher{
		obsv: obsv,
	}
}

// LauncherType returns the type of launcher.
func (d *NoopLauncher) LauncherType() Type {
	return TypeActions
}

// LaunchAgent simulates launching an agent.
func (d *NoopLauncher) LaunchAgent(ctx context.Context, opts *LaunchAgentOpts) (*LaunchResult, error) {
	d.LaunchAgentCalls = append(d.LaunchAgentCalls, *opts)
	if d.LaunchAgentError != nil {
		return nil, d.LaunchAgentError
	}
	// Simulate successful launch with no custom setup
	// Use a numeric compute ID since it's parsed as uint64 in UpdateJobForLaunched
	return &LaunchResult{
		ComputeID:        "999999",
		CustomSetupSteps: false,
		RunsOn:           "",
	}, nil
}

// TerminateAgent simulates terminating an agent.
func (d *NoopLauncher) TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error {
	d.TerminateAgentCalls = append(d.TerminateAgentCalls, opts)
	return d.TerminateAgentError
}
