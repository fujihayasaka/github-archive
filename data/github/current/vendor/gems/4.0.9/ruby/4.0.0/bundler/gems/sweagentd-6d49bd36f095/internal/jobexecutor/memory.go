package jobexecutor

import (
	"time"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
)

// TestJobExecutor is a test implementation of JobExecutor that uses a memory-backed service.
type TestJobExecutor struct {
	AgentJobExecutor

	Service  *jobservice.Service
	Launcher *launcher.NoopLauncher
}

var _ JobExecutor = (*TestJobExecutor)(nil)

// NewTestJobExecutor creates a new TestJobExecutor for testing with customizable dependencies.
func NewTestJobExecutor(obsv observability.Exporters, ffClient featureflags.Client, jobsStore db.JobsStore, ghFactory github.ClientFactoryInterface, ghTwirp githubtwirp.ClientInterface, capiClient capi.Client, limiter *jobLimiter.JobLimiter, service *jobservice.Service) *TestJobExecutor {
	noop := launcher.NewNoopLauncher(obsv)
	memoryClient := aqueduct.NewMemoryClient(obsv)
	if limiter == nil {
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter = jobLimiter.NewJobLimiter(jobsStore, countTracker, nil)
	}
	// Create a test copilot directly without requiring *testing.T
	copilot := agenticapp.NewCopilot(
		1,
		"github-copilot",
		2,
		"github-copilot-bot",
		"commit-login",
		"commit@email.com",
	)
	appProvider := agenticapp.NewProvider(copilot, nil)
	if service == nil {
		service = jobservice.New(obsv, ffClient, jobsStore, capiClient, ghFactory, ghTwirp, memoryClient, limiter, nil, nil, "test_name", "test@example.com", nil, appProvider, nil)
	}

	return &TestJobExecutor{
		AgentJobExecutor: AgentJobExecutor{
			obsv:           obsv,
			ffClient:       ffClient,
			ghFactory:      ghFactory,
			ghTwirp:        ghTwirp,
			launchers:      launcher.NewStaticBuilder(noop),
			service:        service,
			appProvider:    appProvider,
			customAgentSvc: customagent.NewService(obsv, nil, githubtwirp.NewNoopClient(), ffClient),
		},
		Service:  service,
		Launcher: noop,
	}
}

// LaunchAgentCalls returns the list of LaunchAgent calls made during testing.
func (n *TestJobExecutor) LaunchAgentCalls() []launcher.LaunchAgentOpts {
	return n.Launcher.LaunchAgentCalls
}

// TerminateAgentCalls returns the list of TerminateAgent calls made during testing.
func (n *TestJobExecutor) TerminateAgentCalls() []launcher.TerminateAgentOpts {
	return n.Launcher.TerminateAgentCalls
}

// TerminateAgentError returns any error that was set for TerminateAgent calls during testing.
func (n *TestJobExecutor) TerminateAgentError() error {
	return n.Launcher.TerminateAgentError
}
