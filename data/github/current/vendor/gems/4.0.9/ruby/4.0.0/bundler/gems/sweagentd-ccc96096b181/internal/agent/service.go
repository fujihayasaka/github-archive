// Package agent provides services used by the agent while executing jobs.
package agent

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strconv"
	"time"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	jobevents "github.com/github/sweagentd/internal/jobs/jobevents"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
)

// JobEventEmitter defines the interface for emitting job-related events.
type JobEventEmitter interface {
	EmitJobProgress(ctx context.Context, job *jobs.Job, progress *jobevents.ProgressUpdate, obsv observability.Exporters)
}

type jobstore interface {
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)
	GetJobSummariesForAssignmentID(ctx context.Context, owner, repo int64, assignmentID string) ([]*jobs.JobSummary, error)
}

type progressstore interface {
	CreateProgress(ctx context.Context, progress *progress.Progress) (*progress.Progress, error)
	BatchCreateProgress(ctx context.Context, progresses []*progress.Progress) ([]*progress.Progress, error)
	ListProgress(ctx context.Context, assignmentID, jobID string) ([]*progress.Progress, error)
	ListProgressByNamespace(ctx context.Context, assignmentID, jobID string, namespaces []string) ([]*progress.Progress, error)
}

// Service provides methods for agents to interact with jobs and progress updates.
type Service struct {
	store interface {
		jobstore
		progressstore
	}
	cpf            github.ClientFactoryInterface
	customAgentSvc *customagent.Service
	obsv           observability.Exporters
	ff             featureflags.Client
	ghtwirp        githubtwirp.ClientInterface
	eventEmitter   JobEventEmitter
}

// NewService creates a new Service instance with the provided GitHub client factory.
func NewService(
	store interface {
		jobstore
		progressstore
	},
	cpf github.ClientFactoryInterface,
	customAgentSvc *customagent.Service,
	obsv observability.Exporters,
	ff featureflags.Client,
	ghtwirp githubtwirp.ClientInterface,
	eventEmitter JobEventEmitter,
) *Service {
	return &Service{
		store:          store,
		cpf:            cpf,
		customAgentSvc: customAgentSvc,
		obsv:           obsv,
		ff:             ff,
		ghtwirp:        ghtwirp,
		eventEmitter:   eventEmitter,
	}
}

// GetJob retrieves a job by its ID.
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

// GetProgress retrieves progress updates for a job.
//
// If namespaces is empty, all progress updates are returned. Otherwise, only
// progress updates matching the provided namespaces are returned.
//
// If includeHistory is true, progress updates from the most recent previous
// job for the same assignment are also included.
func (s *Service) GetProgress(ctx context.Context, job *jobs.Job, namespaces []string, includeHistory bool) ([]*progress.Progress, error) {
	progressList, err := s.getProgress(ctx, job.AssignmentID, job.ID, namespaces)
	if err != nil {
		return nil, err
	}

	if !includeHistory {
		return progressList, nil
	}

	previousJobs := s.getPreviousJobs(ctx, job)
	if len(previousJobs) == 0 {
		return progressList, nil
	}

	previousJob := previousJobs[0]

	historicalProgressList, err := s.getProgress(ctx, previousJob.AssignmentID, previousJob.ID, namespaces)
	// If we can't get historical progress, just return current progress
	if err != nil {
		s.obsv.LogAndReportError(ctx, err, "failed to get historical progress for previous job")
		return progressList, nil
	}

	return append(historicalProgressList, progressList...), nil
}

// CreateProgress creates one or more progress updates for a job.
func (s *Service) CreateProgress(ctx context.Context, job *jobs.Job, progressList []*progress.Progress) ([]*progress.Progress, error) {
	var createdProgressList []*progress.Progress
	var err error

	switch len(progressList) {
	case 0:
		return []*progress.Progress{}, nil
	case 1:
		createdProgress, err := s.store.CreateProgress(ctx, progressList[0])
		if err != nil {
			return nil, err
		}
		createdProgressList = []*progress.Progress{createdProgress}
	default:
		createdProgressList, err = s.store.BatchCreateProgress(ctx, progressList)
		if err != nil {
			return nil, err
		}
	}

	// Emit job progress events for async sessions.
	// Only emit events for the sessions-legacy namespace for now.
	if job.UseAsyncSessions && s.eventEmitter != nil {
		for _, p := range createdProgressList {
			if p.Namespace != jobevents.SessionsLegacyNamespace {
				continue
			}
			contentJSON, jsonErr := json.Marshal(p.Content)
			if jsonErr != nil {
				// Since the progress object was already created (which implies it was successfully Marshalled)
				// this error should never happen, but log it just in case.
				s.obsv.LogAndReportError(ctx, jsonErr, "failed to marshal progress content for event emission")
				continue
			}
			s.eventEmitter.EmitJobProgress(ctx, job, &jobevents.ProgressUpdate{
				Content:   contentJSON,
				Namespace: p.Namespace,
				Kind:      p.Kind,
				Version:   strconv.FormatInt(p.Version, 10),
				CreatedAt: time.Unix(p.CreatedAt, 0),
			}, s.obsv)
		}
	}

	return createdProgressList, nil
}

// ListAgentsByRepoID is a passthrough to customagent.Service.ListAgentsByRepoID for the given user and job's repository.
// However, in this use of the API we will always omit agents with parsing errors. Furthermore, we will
// only list agents that apply to "github-copilot". (So, anything with `target: vscode` would be excluded.)
func (s *Service) ListAgentsByRepoID(ctx context.Context, userInfo *requestctx.UserInfo, job *jobs.Job, skipAuthCheck bool) ([]sweagentd.CustomAgent, error) {
	return s.customAgentSvc.ListAgentsByRepoID(
		ctx,
		uint64(job.RepoID),
		customagent.ListAgentsOpts{
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
			IncludeSources:       []string{customagent.SourceTypeRepo, customagent.SourceTypeOrg, customagent.SourceTypeEnterprise},
			Target:               "github-copilot",
			UserID:               userInfo.ID,
			SkipAuthCheck:        skipAuthCheck,
		})
}

// GetAgent is mainly a passthrough to customagent.Service.GetAgent for the given user and job's repository.
func (s *Service) GetAgent(ctx context.Context, userInfo *requestctx.UserInfo, repoOwner, repoName, agentName, version string) (sweagentd.CustomAgent, error) {
	return s.customAgentSvc.GetAgent(ctx, repoOwner, repoName, agentName, version, customagent.GetAgentOpts{UserID: userInfo.ID})
}

// ResolveAgentForJob is mainly a passthrough to customagent.Service.ResolveByNameAndRepoID for the given user and job's repository.
func (s *Service) ResolveAgentForJob(ctx context.Context, userInfo *requestctx.UserInfo, job *jobs.Job, agentName, version string) (sweagentd.CustomAgent, error) {
	return s.customAgentSvc.ResolveByNameAndRepoID(ctx, uint64(job.RepoID), agentName, version, customagent.ResolveByNameOpts{UserID: userInfo.ID, ErrorOnInvalidConfig: true})
}

// GetAgentByRepoID is mainly a passthrough to customagent.Service.GetAgentByRepoID for the given user and job's repository.
func (s *Service) GetAgentByRepoID(ctx context.Context, userInfo *requestctx.UserInfo, repoID uint64, agentName, version string) (sweagentd.CustomAgent, error) {
	return s.customAgentSvc.GetAgentByRepoID(ctx, repoID, agentName, version, customagent.GetAgentOpts{UserID: userInfo.ID})
}

// GetAgentForJob is mainly a passthrough to customagent.Service.FromDB for the given user and job's repository.
func (s *Service) GetAgentForJob(ctx context.Context, job *jobs.Job) (sweagentd.CustomAgent, error) {
	return s.customAgentSvc.FromDB(ctx, job.CustomAgent)
}

// CustomAgentsEnabledForRepoByName is a passthrough to customagent.Service.IsEnabledForRepoByName which checks if custom agents are enabled for the given repository.
func (s *Service) CustomAgentsEnabledForRepoByName(ctx context.Context, userID int64, repoOwner, repoName string) (bool, error) {
	return s.customAgentSvc.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
}

// CustomAgentsEnabledForJob is a passthrough to customagent.Service.IsEnabledForRepo which checks if custom agents are enabled for the given repository.
func (s *Service) CustomAgentsEnabledForJob(ctx context.Context, userID int64, job *jobs.Job) bool {
	return s.customAgentSvc.IsEnabledForRepo(ctx, userID, job.OwnerID, job.RepoID)
}

// GetOrganizationCustomInstructions fetches organization custom instructions for a job.
// Returns empty string if the job has no organization (OwnerID == 0).
func (s *Service) GetOrganizationCustomInstructions(ctx context.Context, userID int64, job *jobs.Job) (string, error) {
	ownerID := job.OwnerID

	if ownerID == 0 {
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

// getProgress retrieves progress updates for an assignment and job ID.
//
// If namespaces is empty, all progress updates are returned. Otherwise, only
// progress updates matching the provided namespaces are returned.
func (s *Service) getProgress(ctx context.Context, assignmentID, jobID string, namespaces []string) ([]*progress.Progress, error) {
	if len(namespaces) == 0 {
		progressList, err := s.store.ListProgress(ctx, assignmentID, jobID)
		if err != nil {
			return nil, err
		}
		return progressList, nil
	}

	progressList, err := s.store.ListProgressByNamespace(ctx, assignmentID, jobID, namespaces)
	if err != nil {
		return nil, err
	}

	return progressList, nil
}

// getPreviousJobs retrieves previous job (summaries) for the same assignment
// as the provided job, excluding the current job and jobs created after it.
//
// The returned jobs are sorted by creation time, most recent first. So the
// first job in the returned slice is the most recent previous job.
func (s *Service) getPreviousJobs(ctx context.Context, job *jobs.Job) []*jobs.JobSummary {
	s.obsv.LoggerWithTelemetry(ctx).Info("querying for previous jobs")

	allAssignmentJobs, err := s.store.GetJobSummariesForAssignmentID(ctx, job.OwnerID, job.RepoID, job.AssignmentID)
	if err != nil {
		// If we can't get the job (summaries) for the assignment, don't error
		// just return empty list
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to get job (summaries) for assignment")
		return nil
	}

	if len(allAssignmentJobs) == 0 {
		s.obsv.LoggerWithTelemetry(ctx).Info("no jobs found for assignment")
		return nil
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("found additional jobs for assignment")

	// Remove current job and any jobs created after it
	previousJobs := slices.DeleteFunc(allAssignmentJobs, func(j *jobs.JobSummary) bool {
		return j.ID == job.ID || j.CreatedAt > job.CreatedAt
	})

	// Check if there are any other jobs after filtering
	if len(previousJobs) == 0 {
		s.obsv.LoggerWithTelemetry(ctx).Info("no previous jobs found for assignment after filtering")
		return previousJobs
	}

	// Sort jobs by creation time, most recent first
	slices.SortFunc(previousJobs, func(a, b *jobs.JobSummary) int {
		return cmp.Compare(b.CreatedAt, a.CreatedAt)
	})

	return previousJobs
}

var (
	// ErrInvalidJobIDFormat indicates that the job ID format is invalid.
	ErrInvalidJobIDFormat = errors.New("invalid job ID format")
	// ErrInvalidJobIDOwner indicates that the job ID owner is invalid.
	ErrInvalidJobIDOwner = errors.New("invalid owner in job ID")
	// ErrInvalidJobIDRepo indicates that the job ID repo is invalid.
	ErrInvalidJobIDRepo = errors.New("invalid repo in job ID")
	// ErrJobNotFound indicates that the job was not found.
	ErrJobNotFound = errors.New("job not found")
)
