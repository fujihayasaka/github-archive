package twirpserver

import (
	"context"
	"errors"
	"fmt"
	"strings"

	v1 "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/api/jobapi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/twitchtv/twirp"
)

type jobstore interface {
	GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error)
	GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error)
}

type Server struct {
	obsv       observability.Exporters
	ghf        github.ClientFactoryInterface
	ghTwirp    githubtwirp.ClientInterface
	jobStore   jobstore
	jobService *jobservice.Service
	ffClient   featureflags.Client
}

func NewServer(obsv observability.Exporters, ghf github.ClientFactoryInterface, ghTwirp githubtwirp.ClientInterface, jobStore jobstore, jobService *jobservice.Service, ffClient featureflags.Client) *Server {
	return &Server{
		obsv:       obsv,
		ghf:        ghf,
		ghTwirp:    ghTwirp,
		jobStore:   jobStore,
		jobService: jobService,
		ffClient:   ffClient,
	}
}

func (s *Server) ListJobsForPullRequest(ctx context.Context, req *jobs_pb.ListJobsForPullRequestRequest) (*jobs_pb.ListJobsForPullRequestResponse, error) {
	assignment, err := s.jobStore.GetAssignmentForPR(ctx, req.GetOwnerId(), req.GetRepoId(), &req.PullRequestId, nil)
	if err != nil {
		return nil, err
	}
	if assignment == nil {
		return nil, twirp.NotFoundError("no assignment found for pull request")
	}
	jobs, err := s.jobStore.GetJobsForAssignment(ctx, assignment)
	if err != nil {
		return nil, err
	}

	j := make([]*jobs_pb.Job, len(jobs))
	for i := range jobs {
		j[i] = jobToProto(jobs[i])
	}
	return &jobs_pb.ListJobsForPullRequestResponse{
		Jobs: j,
	}, nil
}

func (s *Server) CreateJob(ctx context.Context, req *jobs_pb.CreateJobRequest) (*jobs_pb.CreateJobResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateJob")
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

	// A bunch of internal code depends on `requestctx` - so we need to add its data into the ctx
	ctx = requestctx.NewContext(ctx)

	// Validate the the user/repo has CCA enabled
	isEnabled, err := githubtwirp.IsCopilotSweEnabled(ctx, s.ghTwirp, int64(req.ActorId), int64(req.RepoId))
	if err != nil {
		return nil, fmt.Errorf("failed to check repo enablement: %w", err)
	}
	if !isEnabled {
		return nil, twirp.Aborted.Error("user or repo does not have CCA enabled")
	}

	// Need to get the user's details
	cu, err := s.ghTwirp.UserDetailAPI().GetCopilotUser(ctx, &v1.GetCopilotUserRequest{
		Id: uint64(req.ActorId),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get user's Copilot details: %w", err)
	}

	gh, err := s.ghf.NewClientFromRepo(ctx, int64(req.RepoId), int64(req.OwnerId))
	if err != nil {
		return nil, fmt.Errorf("failed to create gh client: %w", err)
	}

	// TODO: All of these API requests to hydrate more information about the job are bad.
	actor, repo, owner, err := hydrateAssignmentRequirements(ctx, gh, req.ActorId, int64(req.RepoId), req.OwnerId)
	if err != nil {
		return nil, fmt.Errorf("failed to hydrate assignment requirements: %w", err)
	}

	// Add custom agent
	params := jobservice.GetCustomAgentParams{
		UserID:     int64(cu.UserDetails.Id),
		GHClient:   gh,
		GHRepo:     repo,
		Name:       req.CustomAgent,
		Attributes: customAgentAttributesFromProto(req.CustomAgentAttributes),
	}
	agent, err := s.jobService.GetCustomAgent(ctx, params)
	if err != nil {
		if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
			return nil, twirp.NotFoundError("specified custom agent not found")
		}

		return nil, fmt.Errorf("failed to get custom agent: %w", err)
	}

	var job *jobs.Job

	problemStatementContent := strings.TrimSpace(req.ProblemStatement)

	jobActor := jobs.JobActor{
		ID:         int64(cu.UserDetails.Id),
		Login:      actor.GetLogin(),
		TrackingID: cu.UserDetails.AnalyticsTrackingId,
	}

	baseCommit := getBaseCommitFromRequest(req.BaseBranchName, repo.GetDefaultBranch())
	jb := s.jobService.NewJobBuilder(jobs.AgentActionFix, baseCommit).
		WithNewAssignmentWithCustomAgent(
			*owner.ID,
			*repo.ID,
			owner.GetNodeID(),
			*repo.NodeID,
			owner.GetLogin(),
			*repo.Name,
			agent,
		).
		WithJobActor(jobActor).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypeApiCallReceived,
			URL:         req.EventUrl,
			Identifiers: req.EventIdentifiers,
			Content:     req.EventContent,
		}).
		WithProblemStatement(&jobs.ProblemStatement{
			Content: problemStatementContent,
		}).
		WithFeatures(jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				// TODO: Generate a better title
				TitlePlaceholder: "[WIP] Copilot Request",
				BodyPlaceholder:  fmt.Sprintf("%s\n> %s\n", jobapi.PRBodyPrefix, strings.ReplaceAll(problemStatementContent, "\n", "\n> ")),
			},
		}).
		WithNewSession().
		WithBranchRuleViolationHook(func(ctx context.Context, gh github.ClientInterface, actorLogin string, assignment *jobs.Assignment, result *jobservice.CheckRulesResult) error {
			// TODO: Include failing rules here
			errMsg := "job cannot be created due to the following rule violations"
			return twirp.Aborted.Error(errMsg)
		})

	_, job, err = jb.Build(ctx, gh)
	if err != nil {
		if twirpErr, ok := err.(twirp.Error); ok {
			return nil, twirpErr
		}
		return nil, fmt.Errorf("failed to build job: %w", err)
	}

	aj, err := s.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return nil, fmt.Errorf("failed to queue job: %w", err)
	}

	return &jobs_pb.CreateJobResponse{
		JobId:             job.ID,
		SessionId:         aj.SessionId,
		PullRequestId:     job.PullRequestID,
		PullRequestNumber: int64(job.PullRequestNumber),
	}, nil
}

func (s *Server) CreateJobForIssue(ctx context.Context, req *jobs_pb.CreateJobForIssueRequest) (*jobs_pb.CreateJobForIssueResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateJobForIssue")
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
	if req.IssueId == 0 {
		return nil, twirp.RequiredArgumentError("issue_id")
	}
	if len(req.AdditionalInstructions) > problemstatement.MaxProblemStatementLength {
		return nil, twirp.InvalidArgumentError("additional_instructions", fmt.Sprintf("additional_instructions exceeds maximum length of %d characters", problemstatement.MaxProblemStatementLength))
	}

	// AdditionalInstructions is optional - if not provided, only the issue description will be used

	// A bunch of internal code depends on `requestctx` - so we need to add its data into the ctx
	ctx = requestctx.NewContext(ctx)

	// Validate the the user/repo has CCA enabled
	isEnabled, err := githubtwirp.IsCopilotSweEnabled(ctx, s.ghTwirp, int64(req.ActorId), int64(req.RepoId))
	if err != nil {
		return nil, fmt.Errorf("failed to check repo enablement: %w", err)
	}
	if !isEnabled {
		return nil, twirp.Aborted.Error("user or repo does not have CCA enabled")
	}

	// Need to get the user's details
	cu, err := s.ghTwirp.UserDetailAPI().GetCopilotUser(ctx, &v1.GetCopilotUserRequest{
		Id: uint64(req.ActorId),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get user's Copilot details: %w", err)
	}

	gh, err := s.ghf.NewClientFromRepo(ctx, int64(req.RepoId), int64(req.OwnerId))
	if err != nil {
		return nil, fmt.Errorf("failed to create gh client: %w", err)
	}

	issueRes, err := s.ghTwirp.SweagentdAPI().GetIssueById(ctx, &sweagentdv1.GetIssueByIdRequest{
		IssueId: uint64(req.IssueId),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get issue by ID: %w", err)
	}
	issue := issueRes.GetIssue()

	// TODO: All of these API requests to hydrate more information about the job are bad.
	actor, repo, owner, err := hydrateAssignmentRequirements(ctx, gh, req.ActorId, int64(req.RepoId), req.OwnerId)
	if err != nil {
		return nil, fmt.Errorf("failed to hydrate assignment requirements: %w", err)
	}

	// Add custom agent
	params := jobservice.GetCustomAgentParams{
		UserID:     int64(cu.UserDetails.Id),
		GHClient:   gh,
		GHRepo:     repo,
		Name:       req.CustomAgent,
		Attributes: customAgentAttributesFromProto(req.CustomAgentAttributes),
	}
	agent, err := s.jobService.GetCustomAgent(ctx, params)
	if err != nil {
		if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
			return nil, twirp.NotFoundError("specified custom agent not found")
		}

		return nil, fmt.Errorf("failed to get custom agent: %w", err)
	}

	var job *jobs.Job

	jobActor := jobs.JobActor{
		ID:         int64(cu.UserDetails.Id),
		Login:      actor.GetLogin(),
		TrackingID: cu.UserDetails.AnalyticsTrackingId,
	}

	actx, err := gh.GetIssueContext(ctx, *repo.NodeID, int(issue.Number))
	if err != nil {
		return nil, fmt.Errorf("failed to get issue context: %w", err)
	}

	baseCommit := getBaseCommitFromRequest(req.BaseBranchName, repo.GetDefaultBranch())
	jb := s.jobService.NewJobBuilder(jobs.AgentActionFix, baseCommit).
		WithNewAssignmentWithCustomAgent(
			*owner.ID,
			*repo.ID,
			owner.GetNodeID(),
			*repo.NodeID,
			owner.GetLogin(),
			*repo.Name,
			agent,
		).
		WithJobActor(jobActor).
		WithJobInitHook(func(j *jobs.Job) {
			j.IssueNumber = int(issue.GetNumber())
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypeApiCallReceived,
			URL:         issue.HtmlUrl,
			Identifiers: []string{fmt.Sprintf("%d", issue.Id)},
			Content:     req.EventContent,
		}).
		WithLabelsFrom(github.LabelsToLabelable(issue.Labels)).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return problemstatement.NewIssueBuilder(
				s.obsv,
				gh,
				actx,
				githubtwirp.NewAuthorResolver(s.obsv, s.ghTwirp, s.ffClient),
				problemstatement.WithAdditionalInstructions(req.GetAdditionalInstructions()),
			).Build(c)
		}).
		WithFeatures(jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				BodyPlaceholder: fmt.Sprintf("Thanks for assigning this issue to me. I'm starting to work on it and will keep this PR's description up to date as I form a plan and make progress.\n\nOriginal issue description:\n\n> %s\n\n\nFixes #%d.", strings.ReplaceAll(issue.Body, "\n", "\n> "), issue.Number),
				BaseRef:         baseCommit,
			},
			Branch: &jobs.BranchFeature{
				BaseRef: baseCommit,
			},
		}).
		WithBranchRuleViolationHook(func(ctx context.Context, gh github.ClientInterface, actorLogin string, assignment *jobs.Assignment, result *jobservice.CheckRulesResult) error {
			// TODO: Include failing rules here
			errMsg := "job cannot be created due to the following rule violations"
			return twirp.Aborted.Error(errMsg)
		})

	_, job, err = jb.Build(ctx, gh)
	if err != nil {
		if twirpErr, ok := err.(twirp.Error); ok {
			return nil, twirpErr
		}
		return nil, fmt.Errorf("failed to build job: %w", err)
	}

	// Queue the job to be processed
	aj, err := s.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return nil, fmt.Errorf("failed to queue job: %w", err)
	}

	return &jobs_pb.CreateJobForIssueResponse{
		JobId:             job.ID,
		SessionId:         aj.SessionId,
		PullRequestId:     job.PullRequestID,
		PullRequestNumber: int64(job.PullRequestNumber),
	}, nil
}

func customAgentAttributesFromProto(in *jobs_pb.CustomAgentAttributes) *jobservice.GetCustomAgentParamsAttributes {
	if in == nil {
		return nil
	}
	return &jobservice.GetCustomAgentParamsAttributes{
		DisplayName: in.GetDisplayName(),
		Description: in.GetDescription(),
		Prompt:      in.GetPrompt(),
		Tools:       in.GetTools(),
	}
}

func (s *Server) GetJobBySessionID(ctx context.Context, req *jobs_pb.GetJobBySessionIDRequest) (*jobs_pb.GetJobBySessionIDResponse, error) {
	if req.SessionId == "" {
		return nil, twirp.RequiredArgumentError("session_id")
	}
	if req.OwnerId == 0 {
		return nil, twirp.RequiredArgumentError("owner_id")
	}
	if req.RepoId == 0 {
		return nil, twirp.RequiredArgumentError("repo_id")
	}

	job, err := s.jobService.GetJobBySessionID(ctx, req.OwnerId, req.RepoId, req.SessionId)
	if err != nil {
		if jobservice.IsJobNotFound(err) {
			return nil, twirp.NotFoundError("no job found for session ID")
		}
		return nil, fmt.Errorf("failed to get job by session ID: %w", err)
	}
	if job == nil {
		return nil, twirp.NotFoundError("no job found for session ID")
	}

	return &jobs_pb.GetJobBySessionIDResponse{
		Job: jobToProto(job),
	}, nil
}

func hydrateAssignmentRequirements(ctx context.Context, gh github.ClientInterface, actorID uint64, repoID int64, ownerID uint64) (*gg.User, *gg.Repository, *gg.User, error) {
	// Get the user by ID to get their login
	user, err := gh.GetUserById(ctx, actorID)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to get user by ID: %w", err)
	}

	// Get the repo by ID
	repo, err := gh.GetRepositoryById(ctx, repoID)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to get repo by ID: %w", err)
	}

	// Get the owner by ID to get their login
	owner, err := gh.GetUserById(ctx, ownerID)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to get user by ID: %w", err)
	}

	return user, repo, owner, nil
}

func (s *Server) CreateCommand(ctx context.Context, req *jobs_pb.CreateCommandRequest) (*jobs_pb.CreateCommandResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateCommand")
	defer span.End()

	// Validate the request fields
	if req.JobId == "" {
		return nil, twirp.RequiredArgumentError("job_id")
	}
	if req.OwnerId == 0 {
		return nil, twirp.RequiredArgumentError("owner_id")
	}
	if req.RepoId == 0 {
		return nil, twirp.RequiredArgumentError("repo_id")
	}
	if req.ActorId == 0 {
		return nil, twirp.RequiredArgumentError("actor_id")
	}
	if req.ExternalId == "" {
		return nil, twirp.RequiredArgumentError("external_id")
	}
	if strings.TrimSpace(req.Content) == "" {
		return nil, twirp.RequiredArgumentError("content")
	}
	if req.Timestamp == 0 {
		return nil, twirp.RequiredArgumentError("timestamp")
	}
	if !s.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSweAgentCommands, int64(req.ActorId)) {
		return nil, twirp.FailedPrecondition.Error("command jobs are disabled")
	}

	// Validate the the user/repo has CCA enabled
	isEnabled, err := githubtwirp.IsCopilotSweEnabled(ctx, s.ghTwirp, int64(req.ActorId), int64(req.RepoId))
	if err != nil {
		return nil, fmt.Errorf("failed to check repo enablement: %w", err)
	}
	if !isEnabled {
		return nil, twirp.Aborted.Error("user or repo does not have CCA enabled")
	}

	// Need to get the user's details
	cu, err := s.ghTwirp.UserDetailAPI().GetCopilotUser(ctx, &v1.GetCopilotUserRequest{
		Id: uint64(req.ActorId),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get user's Copilot details: %w", err)
	}

	job, err := s.jobService.GetJobByID(ctx, req.OwnerId, req.RepoId, req.JobId)
	if err != nil {
		return nil, twirp.NotFoundError("no job found for ID")
	}

	// For now commands can only be created by the job's actor
	if job.ActorID != int64(cu.UserDetails.Id) {
		return nil, twirp.NotFoundError("no job found for ID")
	}

	if s.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentZeroQuotaTest, int64(req.ActorId)) {
		return nil, twirp.ResourceExhausted.Error("insufficient premium quota to create command")
	}

	// Check if user has sufficient quota before accepting the command
	hasSufficientQuota, _, err := githubtwirp.CheckPremiumQuota(ctx, s.ghTwirp, s.ffClient, s.obsv, req.OwnerId, req.RepoId, int64(cu.UserDetails.Id))
	if err != nil {
		if errors.Is(err, githubtwirp.ErrCustomerSelectionRequired) {
			return nil, twirp.FailedPrecondition.Error("customer selection required")
		}
		return nil, fmt.Errorf("failed to check quota: %w", err)
	}
	if !hasSufficientQuota {
		return nil, twirp.ResourceExhausted.Error("insufficient premium quota to create command")
	}

	createdCommand, err := s.jobService.CreateCommandForJob(ctx, job, req.ExternalId, int64(cu.UserDetails.Id), req.Content, req.Timestamp)
	if err != nil {
		if errors.Is(err, command.ErrJobIsTerminal) {
			return nil, twirp.FailedPrecondition.Error("cannot create command for job in terminal state")
		}
		return nil, fmt.Errorf("failed to add command to job: %w", err)
	}

	return &jobs_pb.CreateCommandResponse{
		Id:         createdCommand.ID,
		ExternalId: createdCommand.ExternalID,
		JobId:      createdCommand.JobID,
	}, nil
}

// getBaseCommitFromRequest returns the base branch name if provided in the request,
// otherwise falls back to the default branch.
func getBaseCommitFromRequest(baseBranchName, defaultBranch string) string {
	trimmed := strings.TrimSpace(baseBranchName)
	if trimmed != "" {
		return trimmed
	}
	return defaultBranch
}
