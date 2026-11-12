package launcher

import (
	"context"

	"github.com/github/sweagentd/internal/observability"
)

type NoopLauncher struct {
	obsv                observability.Exporters
	LaunchAgentCalls    []LaunchAgentOpts
	TerminateAgentCalls []TerminateAgentOpts
	TerminateAgentError error
}

// Ensure that NoopLauncher implements AgentLauncher
var _ AgentLauncher = &NoopLauncher{}

func NewNoopLauncher(obsv observability.Exporters) *NoopLauncher {
	return &NoopLauncher{
		obsv: obsv,
	}
}

func (d *NoopLauncher) LauncherType() LauncherType {
	return LauncherTypeActions
}

func (d *NoopLauncher) LaunchAgent(ctx context.Context, opts LaunchAgentOpts) (string, error) {
	d.LaunchAgentCalls = append(d.LaunchAgentCalls, opts)
	return "0", nil
}

func (d *NoopLauncher) TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error {
	d.TerminateAgentCalls = append(d.TerminateAgentCalls, opts)
	return d.TerminateAgentError
}
