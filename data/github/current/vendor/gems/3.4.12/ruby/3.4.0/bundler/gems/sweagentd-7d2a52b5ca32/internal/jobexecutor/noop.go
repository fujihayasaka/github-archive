package jobexecutor

import (
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/observability"
)

type NoopJobExecutor struct {
	AgentJobExecutor
	Launcher *launcher.NoopLauncher
}

var _ JobExecutor = (*NoopJobExecutor)(nil)

func NewNoopJobExecutor(obsv observability.Exporters) *NoopJobExecutor {
	launcher := launcher.NewNoopLauncher(obsv)
	service := jobservice.New(obsv, nil, nil, nil, nil, nil, nil, nil, nil, nil, "", nil)
	return &NoopJobExecutor{
		Launcher: launcher,
		AgentJobExecutor: AgentJobExecutor{
			obsv:     obsv,
			launcher: launcher,
			service:  service,
		},
	}
}

func (n *NoopJobExecutor) LaunchAgentCalls() []launcher.LaunchAgentOpts {
	return n.Launcher.LaunchAgentCalls
}

func (n *NoopJobExecutor) TerminateAgentCalls() []launcher.TerminateAgentOpts {
	return n.Launcher.TerminateAgentCalls
}

func (n *NoopJobExecutor) TerminateAgentError() error {
	return n.Launcher.TerminateAgentError
}
