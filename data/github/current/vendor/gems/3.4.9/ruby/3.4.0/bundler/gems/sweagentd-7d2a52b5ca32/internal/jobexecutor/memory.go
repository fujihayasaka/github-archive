package jobexecutor

import (
	"time"

	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
)

type TestJobExecutor struct {
	AgentJobExecutor

	Service  *jobservice.Service
	Launcher *launcher.NoopLauncher
}

var _ JobExecutor = (*TestJobExecutor)(nil)

func NewTestJobExecutor(obsv observability.Exporters, ffClient featureflags.Client, jobsStore db.JobsStore, ghFactory github.ClientFactoryInterface, ghTwirp githubtwirp.ClientInterface, capiClient capi.Client, limiter *jobLimiter.JobLimiter, service *jobservice.Service) *TestJobExecutor {
	launcher := launcher.NewNoopLauncher(obsv)
	memoryClient := aqueduct.NewMemoryClient(obsv)
	if limiter == nil {
		limiter = jobLimiter.NewJobLimiter(jobsStore, 10, time.Hour)
	}
	if service == nil {
		service = jobservice.New(obsv, ffClient, jobsStore, capiClient, ghFactory, ghTwirp, memoryClient, limiter, nil, nil, "test@example.com", nil)
	}

	return &TestJobExecutor{
		AgentJobExecutor: AgentJobExecutor{
			obsv:      obsv,
			ffClient:  ffClient,
			ghFactory: ghFactory,
			ghTwirp:   ghTwirp,
			launcher:  launcher,
			service:   service,
		},
		Service:  service,
		Launcher: launcher,
	}
}

func (n *TestJobExecutor) LaunchAgentCalls() []launcher.LaunchAgentOpts {
	return n.Launcher.LaunchAgentCalls
}

func (n *TestJobExecutor) TerminateAgentCalls() []launcher.TerminateAgentOpts {
	return n.Launcher.TerminateAgentCalls
}

func (n *TestJobExecutor) TerminateAgentError() error {
	return n.Launcher.TerminateAgentError
}
