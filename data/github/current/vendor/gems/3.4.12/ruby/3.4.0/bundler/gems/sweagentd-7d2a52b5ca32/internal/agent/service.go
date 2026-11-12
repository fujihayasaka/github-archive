package agent

import (
	"context"
	"errors"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
)

type jobstore interface {
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)
}

type Service struct {
	store          jobstore
	cpf            github.ClientFactoryInterface
	customAgentSvc *customagent.Service
	obsv           observability.Exporters
	ff             featureflags.Client
	ghtwirp        githubtwirp.ClientInterface
}

// NewService creates a new Service instance with the provided GitHub client factory.
func NewService(
	store jobstore,
	cpf github.ClientFactoryInterface,
	customAgentSvc *customagent.Service,
	obsv observability.Exporters,
	ff featureflags.Client,
	ghtwirp githubtwirp.ClientInterface,
) *Service {
	return &Service{
		store:          store,
		cpf:            cpf,
		customAgentSvc: customAgentSvc,
		obsv:           obsv,
		ff:             ff,
		ghtwirp:        ghtwirp,
	}
}

func (s *Service) GetJob(ctx context.Context, id string) (*jobs.Job, error) {
	jobID, err := NewJobID(id)
	if err != nil {
		return nil, err
	}

	job, err := s.store.GetJob(ctx, jobID.Owner, jobID.Repo, jobID.Value)
	if err != nil {
		return nil, err
	}
	if job == nil {
		return nil, ErrJobNotFound
	}

	return job, nil
}

// ListAgents is a passthrough to customagent.Service.ListAgents for the given user and job's repository.
// However, in this use of the API we will always omit agents with parsing errors.
func (s *Service) ListAgents(ctx context.Context, userInfo *requestctx.UserInfo, job *jobs.Job) ([]sweagentd.CustomAgent, error) {
	return s.customAgentSvc.ListAgents(ctx, userInfo.ID, job.RepoOwner, job.RepoName, true)
}

// GetAgent is mainly a passthrough to customagent.Service.GetAgent for the given user and job's repository.
func (s *Service) GetAgent(ctx context.Context, userInfo *requestctx.UserInfo, repoOwner, repoName, agentName, version string) (sweagentd.CustomAgent, error) {
	return s.customAgentSvc.GetAgent(ctx, userInfo.ID, repoOwner, repoName, agentName, version)
}

// CustomAgentsEnabledForRepoByName is a passthrough to customagent.Service.CustomAgentsEnabledForRepoByName which checks if custom agents are enabled for the given repository.
func (s *Service) CustomAgentsEnabledForRepoByName(ctx context.Context, userID int64, repoOwner, repoName string) (bool, error) {
	return s.customAgentSvc.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
}

// GetOrganizationCustomInstructions fetches organization custom instructions for a job.
// Returns empty string if feature flag is disabled or if the job has no organization (OwnerID == 0).
func (s *Service) GetOrganizationCustomInstructions(ctx context.Context, userID int64, job *jobs.Job) (string, error) {
	ownerID := int64(job.OwnerID)
	repoID := job.RepoID

	if ownerID == 0 {
		return "", nil
	}

	if !s.ff.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentOrganizationCustomInstructions, userID, repoID) {
		return "", nil
	}

	req := &sweagentdv1.GetOrganizationCustomInstructionsRequest{
		OrganizationId: uint64(ownerID),
	}

	resp, err := s.ghtwirp.SweagentdAPI().GetOrganizationCustomInstructions(ctx, req)
	if err != nil {
		s.obsv.Logger.WithContext(ctx).Info("failed to get organization custom instructions")
		return "", err
	}

	return resp.OrganizationCustomInstructions, nil
}

var (
	ErrInvalidJobIDFormat = errors.New("invalid job ID format")
	ErrInvalidJobIDOwner  = errors.New("invalid owner in job ID")
	ErrInvalidJobIDRepo   = errors.New("invalid repo in job ID")
	ErrJobNotFound        = errors.New("job not found")
)
