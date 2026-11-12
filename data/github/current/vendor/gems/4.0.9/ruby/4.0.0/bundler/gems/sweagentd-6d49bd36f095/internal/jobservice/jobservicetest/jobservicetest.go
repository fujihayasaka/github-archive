// Package jobservicetest provides utilities for testing the jobservice package.
package jobservicetest

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
)

// TestService wraps the jobservice.Service and provides additional utilities for testing.
type TestService struct {
	jobservice.Service

	Limiter     *limiter.JobLimiter
	Store       db.JobsStore
	CAPI        capi.Client
	Experiments *experiments.MockClient
	Aqueduct    *aqueduct.MemoryClient
}

// New creates a new TestService with the provided dependencies or default test implementations.
func New(
	t *testing.T,
	obsv observability.Exporters,
	ffs featureflags.Client,
	store db.JobsStore,
	capiClt capi.Client,
	ghf github.ClientFactoryInterface,
	twirp githubtwirp.ClientInterface,
	aq *aqueduct.MemoryClient,
	exp *experiments.MockClient,
	customAgentSvc *customagent.Service,
	appProvider *agenticapp.Provider,
) *TestService {
	t.Helper()

	jobStore := store
	if jobStore == nil {
		jobStore = memory.NewStore()
	}
	capiClient := capiClt
	if capiClient == nil {
		capiClient = capi.NewNoopClient()
	}
	aqueductClient := aq
	if aqueductClient == nil {
		aqueductClient = aqueduct.NewMemoryClient(obsv)
	}
	experimentsClient := exp
	if experimentsClient == nil {
		experimentsClient = &experiments.MockClient{}
	}
	customAgentService := customAgentSvc
	if customAgentService == nil {
		spokes := spokestest.NewClient(t)
		customAgentService = customagent.NewService(obsv, spokes, twirp, ffs)
	}
	ap := appProvider
	if ap == nil {
		ap = agenticapptest.NewTestProvider(t)
	}

	countTracker := limiter.NewJobCountMemoryTracker(10, time.Hour)
	jobLimiter := limiter.NewJobLimiter(jobStore, countTracker, nil) // will be used in an upcoming PR
	spokes := spokestest.NewClient(t)
	service := jobservice.New(obsv, ffs, jobStore, capiClient, ghf, twirp, aqueductClient, jobLimiter, experimentsClient, customAgentService, "test_name", "test@example.com", spokes, ap, nil)

	return &TestService{
		Service:     *service,
		Limiter:     jobLimiter,
		Store:       jobStore,
		CAPI:        capiClient,
		Experiments: experimentsClient,
		Aqueduct:    aqueductClient,
	}
}

// QueuedJobs retrieves all queued jobs from the Aqueduct memory client.
func (n *TestService) QueuedJobs() []*aqueductJobs.AgentJob {
	var agentJobs []*aqueductJobs.AgentJob

	jobs := n.Aqueduct.QueuedJobs(aqueductJobs.AgentJobQueueName)

	for _, job := range jobs {
		var agentJob aqueductJobs.AgentJob
		err := agentJob.Unmarshal(job.Payload)
		if err != nil {
			continue
		}
		agentJobs = append(agentJobs, &agentJob)
	}

	return agentJobs
}
