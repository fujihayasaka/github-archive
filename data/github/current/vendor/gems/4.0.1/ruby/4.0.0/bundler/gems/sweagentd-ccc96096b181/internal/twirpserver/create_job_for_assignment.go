package twirpserver

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/twitchtv/twirp"
)

// CreateJobForAssignment handles the creation of a new job for a given assignment.
func (s *Server) CreateJobForAssignment(ctx context.Context, req *jobs_pb.CreateJobForAssignmentRequest) (*jobs_pb.CreateJobForAssignmentResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateJobForAssignment")
	defer span.End()

	// Validate the request fields
	if req.ActorId == 0 {
		return nil, twirp.RequiredArgumentError("actor_id")
	}
	if req.OwnerId == 0 {
		return nil, twirp.RequiredArgumentError("owner_id")
	}
	if req.RepoId == 0 {
		return nil, twirp.RequiredArgumentError("repo_id")
	}
	if strings.TrimSpace(req.ProblemStatement) == "" {
		return nil, twirp.RequiredArgumentError("problem_statement")
	}
	if len(req.ProblemStatement) > problemstatement.MaxProblemStatementLength {
		return nil, twirp.InvalidArgumentError("problem_statement", fmt.Sprintf("problem_statement exceeds maximum length of %d characters", problemstatement.MaxProblemStatementLength))
	}
	if strings.TrimSpace(req.AssignmentId) == "" {
		return nil, twirp.RequiredArgumentError("assignment_id")
	}

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("assignment_id", req.AssignmentId))

	logger.Info("Creating job for assignment",
		kvp.Any("features", req.Features),
		kvp.Uint64("agent_id", req.AgentId),
		kvp.String("model", req.Model),
	)

	agenticApp, err := s.appProvider.FindByID(int64(req.AgentId))
	if err != nil {
		return nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
	}

	// Validate the user/repo has CCA enabled
	isEnabled, _, err := s.ghTwirp.IsAgentEnabled(ctx, agenticApp.AppID(), int64(req.ActorId), int64(req.RepoId))
	if err != nil {
		return nil, goerrors.Errorf("failed to check repo enablement: %w", err)
	}
	if !isEnabled {
		return nil, twirp.Aborted.Error("user or repo does not have CCA enabled")
	}

	// Need to get the user's details
	cu, err := s.ghTwirp.GetCopilotUserDetails(ctx, int64(req.ActorId))
	if err != nil {
		return nil, goerrors.Errorf("failed to get user's Copilot details: %w", err)
	}

	gh, err := s.ghf.NewClientFromRepo(ctx, agenticApp, int64(req.RepoId), int64(req.OwnerId))
	if err != nil {
		return nil, goerrors.Errorf("failed to create gh client: %w", err)
	}

	actor, repo, _, err := hydrateAssignmentRequirements(ctx, gh, req.ActorId, int64(req.RepoId), req.OwnerId)
	if err != nil {
		return nil, goerrors.Errorf("failed to hydrate assignment requirements: %w", err)
	}

	assignment, err := s.jobStore.GetAssignment(ctx, int64(req.OwnerId), int64(req.RepoId), req.AssignmentId)
	if err != nil {
		return nil, goerrors.Errorf("failed to get assignment: %w", err)
	}

	assignmentJobs, err := s.jobStore.GetJobsForAssignment(ctx, assignment)
	if err != nil {
		return nil, goerrors.Errorf("failed to get jobs for assignment: %w", err)
	}

	logger.Info(fmt.Sprintf("Found %d previous jobs for assignment", len(assignmentJobs)))
	latestJob := getMostRecentJob(assignmentJobs)

	// Determine branch configuration based on request features and previous jobs
	branchConfig := s.resolveBranchConfig(repo, latestJob, req.Features)
	logger.Info(fmt.Sprintf("Resolved branch config: baseRef=%s, inheritedBranch=%s, needsNewBranch=%t",
		branchConfig.baseRef, branchConfig.inheritedBranch, branchConfig.needsNewBranch))

	// Custom agent name may be in the form "name@version", so separate the fields if so
	agentName, agentVersion := customagent.ParseCustomAgentName(req.CustomAgent)
	// Add custom agent
	params := jobservice.GetCustomAgentParams{
		UserID:     int64(cu.Id),
		GHClient:   gh,
		GHRepo:     repo,
		Name:       agentName,
		Version:    agentVersion,
		Attributes: customAgentAttributesFromProto(req.CustomAgentAttributes),
	}
	customAgent, err := s.jobService.GetCustomAgent(ctx, params)
	if err != nil {
		if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
			return nil, twirp.NotFoundError("specified custom agent not found")
		}

		return nil, goerrors.Errorf("failed to get custom agent: %w", err)
	}

	var job *jobs.Job

	problemStatementContent := strings.TrimSpace(req.ProblemStatement)

	jobActor := jobs.JobActor{
		ID:         int64(cu.Id),
		Login:      actor.GetLogin(),
		TrackingID: cu.AnalyticsTrackingId,
	}

	action := jobs.AgentActionFix
	if branchConfig.features.PullRequest == nil && s.ffClient.IsEnabledForUser(ctx, featureflags.CodingAgentProposeTasks, int64(req.ActorId)) {
		action = jobs.AgentActionTask
	}

	// Default to api_call_received if not provided
	eventType := jobs.EventType(req.EventType)
	if eventType == "" {
		eventType = jobs.EventTypeAPICallReceived
	}

	jb := s.jobService.NewJobBuilder(action, repo, branchConfig.baseRef).
		ForAssignment(assignment).
		WithJobActor(jobActor).
		WithRequestStartedAt(requestctx.RequestStartedAtOrNow(ctx)).
		WithJobInitHook(func(j *jobs.Job) {
			// Inherit model from previous job if not specified in request
			if latestJob != nil && req.Model == "" {
				logger.Info("Inheriting model from latest job", kvp.String("inherited_model", latestJob.Model))
				j.Model = latestJob.Model
			}
			// Inherit branch name for follow-up sessions
			if branchConfig.inheritedBranch != "" {
				j.BranchName = branchConfig.inheritedBranch
			}
		}).
		WithCustomAgent(customAgent).
		WithModel(req.Model).
		WithAgentID(agenticApp.AppID()).
		WithEvent(jobservice.Event{
			Type:        eventType,
			URL:         req.EventUrl,
			Identifiers: req.EventIdentifiers,
			Content:     req.EventContent,
		}).
		WithProblemStatement(&jobs.ProblemStatement{
			Content: problemStatementContent,
		}).
		WithNewSession().
		WithAINameGen()

	// Apply features if needed (either from request or to trigger branch creation)
	if branchConfig.needsNewBranch || req.Features != nil {
		jb = jb.WithFeatures(branchConfig.features)
	}

	_, job, err = jb.Build(ctx, gh)
	if err != nil {
		return nil, goerrors.Errorf("failed to build job: %w", err)
	}

	aj, err := s.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return nil, goerrors.Errorf("failed to queue job: %w", err)
	}

	return &jobs_pb.CreateJobForAssignmentResponse{
		JobId:     job.ID,
		SessionId: aj.SessionId,
	}, nil
}

// getMostRecentJob returns the most recent job from a list of jobs based on CreatedAt.
// Returns nil if the job list is empty.
func getMostRecentJob(allJobs []*jobs.Job) *jobs.Job {
	if len(allJobs) == 0 {
		return nil
	}

	mostRecent := allJobs[0]
	for _, job := range allJobs[1:] {
		if job.CreatedAt > mostRecent.CreatedAt {
			mostRecent = job
		}
	}

	return mostRecent
}

// branchConfig holds the resolved branch configuration for a job.
type branchConfig struct {
	// baseRef is the branch to use as the base for the job (passed to NewJobBuilder)
	baseRef string
	// inheritedBranch is set when reusing an existing branch from a previous job
	inheritedBranch string
	// needsNewBranch indicates whether a new branch needs to be created
	needsNewBranch bool
	// features contains the environment features to apply
	features jobs.EnvironmentFeatures
}

// resolveBranchConfig determines the branch configuration for a new job based on:
// 1. Explicit features from the request (highest priority)
// 2. Branch inherited from the most recent job in the assignment
// 3. Creating a new branch from the repo's default branch (fallback)
func (s *Server) resolveBranchConfig(repo *gg.Repository, latestJob *jobs.Job, reqFeatures *jobs_pb.Features) branchConfig {
	features := reqFeaturesToJobFeatures(reqFeatures)

	// Case 1: Explicit features provided - use them as-is
	if reqFeatures != nil {
		baseRef := repo.GetDefaultBranch()
		if features.Branch != nil && features.Branch.Name != "" {
			baseRef = features.Branch.Name
		} else if features.PullRequest != nil && features.PullRequest.BaseRef != "" {
			baseRef = features.PullRequest.BaseRef
		}
		return branchConfig{
			baseRef:        baseRef,
			needsNewBranch: features.Branch != nil || features.PullRequest != nil,
			features:       features,
		}
	}

	// Case 2: No features - try to inherit branch from previous job
	if latestJob != nil && latestJob.BranchName != "" {
		return branchConfig{
			baseRef:         latestJob.BranchName,
			inheritedBranch: latestJob.BranchName,
			needsNewBranch:  false,
			features:        features,
		}
	}

	// Case 3: No features and no branch to inherit - create new branch
	features.Branch = &jobs.BranchFeature{
		BaseRef: repo.GetDefaultBranch(),
	}
	return branchConfig{
		baseRef:        repo.GetDefaultBranch(),
		needsNewBranch: true,
		features:       features,
	}
}
