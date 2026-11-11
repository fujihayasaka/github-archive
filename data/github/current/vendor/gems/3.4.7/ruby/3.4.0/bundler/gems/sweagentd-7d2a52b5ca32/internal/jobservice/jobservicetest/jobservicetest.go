package jobservicetest

import (
	"testing"
	"time"

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

type TestService struct {
	jobservice.Service

	Limiter     *limiter.JobLimiter
	Store       db.JobsStore
	CAPI        capi.Client
	Experiments *experiments.MockClient
	Aqueduct    *aqueduct.MemoryClient
}

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

	jobLimiter := limiter.NewJobLimiter(jobStore, 10, time.Hour) // will be used in an upcoming PR
	spokes := spokestest.NewClient(t)
	service := jobservice.New(obsv, ffs, jobStore, capiClient, ghf, twirp, aqueductClient, jobLimiter, experimentsClient, customAgentService, "test@example.com", spokes)

	return &TestService{
		Service:     *service,
		Limiter:     jobLimiter,
		Store:       jobStore,
		CAPI:        capiClient,
		Experiments: experimentsClient,
		Aqueduct:    aqueductClient,
	}
}

func (n *TestService) QueuedJobs() []*aqueductJobs.AgentJob {
	var agentJobs []*aqueductJobs.AgentJob

	jobs := n.Aqueduct.QueuedJobs(aqueductJobs.AgentJobQueueName)

	for _, job := range jobs {
		var agentJob aqueductJobs.AgentJob
		if err := agentJob.Unmarshal(job.Payload); err != nil {
			continue
		}
		agentJobs = append(agentJobs, &agentJob)
	}

	return agentJobs
}
