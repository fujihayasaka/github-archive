package jobexecutor

import (
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/observability"
)

// NoopJobExecutor is a no-op implementation of JobExecutor for testing purposes.
type NoopJobExecutor struct {
	AgentJobExecutor

	Launcher *launcher.NoopLauncher
}

var _ JobExecutor = (*NoopJobExecutor)(nil)

// NewNoopJobExecutor creates a new NoopJobExecutor for testing.
func NewNoopJobExecutor(obsv observability.Exporters) *NoopJobExecutor {
	launcher := launcher.NewNoopLauncher(obsv)
	service := jobservice.New(obsv, nil, nil, nil, nil, nil, nil, nil, nil, nil, "", nil, nil, nil)
	return &NoopJobExecutor{
		Launcher: launcher,
		AgentJobExecutor: AgentJobExecutor{
			obsv:     obsv,
			launcher: launcher,
			service:  service,
		},
	}
}

// LaunchAgentCalls returns the list of LaunchAgent calls made during testing.
func (n *NoopJobExecutor) LaunchAgentCalls() []launcher.LaunchAgentOpts {
	return n.Launcher.LaunchAgentCalls
}

// TerminateAgentCalls returns the list of TerminateAgent calls made during testing.
func (n *NoopJobExecutor) TerminateAgentCalls() []launcher.TerminateAgentOpts {
	return n.Launcher.TerminateAgentCalls
}

// TerminateAgentError returns any error that was set for TerminateAgent calls during testing.
func (n *NoopJobExecutor) TerminateAgentError() error {
	return n.Launcher.TerminateAgentError
}
