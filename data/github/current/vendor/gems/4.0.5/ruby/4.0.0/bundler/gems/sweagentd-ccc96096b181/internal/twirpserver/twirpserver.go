// Package twirpserver implements the Twirp server for job-related operations.
package twirpserver

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/api/jobapi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/twitchtv/twirp"
)

type jobstore interface {
	GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error)
	GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error)
	GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error)
	GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error)
	CreateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error)
}

// Server implements the Twirp RPC handlers for job operations.
type Server struct {
	obsv        observability.Exporters
	ghf         github.ClientFactoryInterface
	ghTwirp     githubtwirp.ClientInterface
	jobStore    jobstore
	jobService  *jobservice.Service
	ffClient    featureflags.Client
	appProvider *agenticapp.Provider
}

// NewServer creates a new Twirp server instance with the provided dependencies.
func NewServer(
	obsv observability.Exporters,
	ghf github.ClientFactoryInterface,
	ghTwirp githubtwirp.ClientInterface,
	jobStore jobstore,
	jobService *jobservice.Service,
	ffClient featureflags.Client,
	appProvider *agenticapp.Provider,
) *Server {
	return &Server{
		obsv:        obsv,
		ghf:         ghf,
		ghTwirp:     ghTwirp,
		jobStore:    jobStore,
		jobService:  jobService,
		ffClient:    ffClient,
		appProvider: appProvider,
	}
}

// ServerHooks returns Twirp server hooks that wrap the provided hooks with
// common request context initialization. This ensures all endpoints have
// access to requestctx without needing to call requestctx.NewContext manually.
func (s *Server) ServerHooks(hooks *twirp.ServerHooks) *twirp.ServerHooks {
	return twirp.ChainHooks(
		&twirp.ServerHooks{
			RequestReceived: func(ctx context.Context) (context.Context, error) {
				ctx = requestctx.NewContext(ctx)
				_ = requestctx.AddRequestStartedAt(ctx, time.Now())
				return ctx, nil
			},
		},
		hooks,
	)
}

// ListJobsForPullRequest retrieves all jobs associated with a specific pull request.
func (s *Server) ListJobsForPullRequest(ctx context.Context, req *jobs_pb.ListJobsForPullRequestRequest) (*jobs_pb.ListJobsForPullRequestResponse, error) {
	var assignment *jobs.Assignment
	var err error

	if s.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentWorkOnCurrentBranch, req.GetRepoId()) {
		resource := jobs.AssignmentResource{
			Type: "pull_request",
			ID:   strconv.FormatInt(req.PullRequestId, 10),
		}
		assignment, err = s.jobStore.GetAssignmentForResource(ctx, req.GetOwnerId(), req.GetRepoId(), resource)
	} else {
		assignment, err = s.jobStore.GetAssignmentForPR(ctx, req.GetOwnerId(), req.GetRepoId(), &req.PullRequestId, nil)
	}

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

// CreateJob creates a new job for a pull request with a custom problem statement.
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

	app, err := s.appProvider.FindByID(req.AgentId)
	if err != nil {
		return nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
	}

	// Validate the user/repo has CCA enabled
	isEnabled, _, err := s.ghTwirp.IsAgentEnabled(ctx, app.AppID(), int64(req.ActorId), int64(req.RepoId))
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

	targetGH, err := s.ghf.NewClientFromRepo(ctx, app, int64(req.RepoId), int64(req.OwnerId))
	if err != nil {
		return nil, goerrors.Errorf("failed to create gh client: %w", err)
	}

	// TODO: All of these API requests to hydrate more information about the job are bad.
	actor, repo, owner, err := hydrateAssignmentRequirements(ctx, targetGH, req.ActorId, int64(req.RepoId), req.OwnerId)
	if err != nil {
		return nil, goerrors.Errorf("failed to hydrate assignment requirements: %w", err)
	}

	// Parse custom agent name and version from the request - may be in the form name@version
	agentName, agentVersion := customagent.ParseCustomAgentName(req.CustomAgent)

	// Add custom agent
	params := jobservice.GetCustomAgentParams{
		UserID:     int64(cu.Id),
		GHClient:   targetGH,
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

	agenticApp, err := s.appProvider.FindByID(req.AgentId)
	if err != nil {
		return nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
	}

	var job *jobs.Job

	problemStatementContent := strings.TrimSpace(req.ProblemStatement)

	jobActor := jobs.JobActor{
		ID:         int64(cu.Id),
		Login:      actor.GetLogin(),
		TrackingID: cu.AnalyticsTrackingId,
	}

	useAsyncSessions := s.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, *repo.ID)

	baseCommit := getBaseCommitFromFeatures(req.Features, repo.GetDefaultBranch())

	// Convert request features to internal format, preserving PR placeholders
	builderFeatures := reqFeaturesToJobFeatures(req.Features)
	if builderFeatures.PullRequest != nil {
		builderFeatures.PullRequest.TitlePlaceholder = "[WIP] Copilot Request"
		builderFeatures.PullRequest.BodyPlaceholder = fmt.Sprintf("%s\n> %s\n", jobservice.PRBodyPrefix, strings.ReplaceAll(problemStatementContent, "\n", "\n> "))
	}

	jb := s.jobService.NewJobBuilder(jobs.AgentActionFix, repo, baseCommit).
		WithNewAssignmentWithCustomAgent(
			*owner.ID,
			*repo.ID,
			owner.GetNodeID(),
			*repo.NodeID,
			owner.GetLogin(),
			*repo.Name,
			useAsyncSessions,
			customAgent,
		).
		WithJobActor(jobActor).
		WithRequestStartedAt(requestctx.RequestStartedAtOrNow(ctx)).
		WithAgentID(agenticApp.AppID()).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypeAPICallReceived,
			URL:         req.EventUrl,
			Identifiers: req.EventIdentifiers,
			Content:     req.EventContent,
		}).
		WithProblemStatement(&jobs.ProblemStatement{
			Content: problemStatementContent,
		}).
		WithFeatures(builderFeatures).
		WithModel(req.Model).
		WithNewSession().
		WithAINameGen().
		WithBranchRuleViolationHook(func(ctx context.Context, gh github.ClientInterface, actorLogin string, assignment *jobs.Assignment, result *jobservice.CheckRulesResult) error {
			// TODO: Include failing rules here
			errMsg := "job cannot be created due to the following rule violations"
			return twirp.FailedPrecondition.Error(errMsg)
		})

	_, job, err = jb.Build(ctx, targetGH)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) {
			return nil, twirpErr
		}
		return nil, goerrors.Errorf("failed to build job: %w", err)
	}

	aj, err := s.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return nil, goerrors.Errorf("failed to queue job: %w", err)
	}

	return &jobs_pb.CreateJobResponse{
		JobId:             job.ID,
		SessionId:         aj.SessionId,
		PullRequestId:     job.PullRequestID,
		PullRequestNumber: int64(job.PullRequestNumber),
	}, nil
}

// CreateJobForIssue creates a new job to address a GitHub issue.
//
//nolint:maintidx // complexity is acceptable here for the sake of clarity - handles multiple validation and setup steps
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

	// Get the agent from the request
	agenticApp, err := s.appProvider.FindByID(req.AgentId)
	if err != nil {
		return nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
	}

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

	targetGH, err := s.ghf.NewClientFromRepo(ctx, agenticApp, int64(req.RepoId), int64(req.OwnerId))
	if err != nil {
		return nil, goerrors.Errorf("failed to create gh client: %w", err)
	}

	issueRes, err := s.ghTwirp.SweagentdAPI().GetIssueById(ctx, &sweagentdv1.GetIssueByIdRequest{
		IssueId: uint64(req.IssueId),
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to get issue by ID: %w", err)
	}
	issue := issueRes.GetIssue()

	// TODO: All of these API requests to hydrate more information about the job are bad.
	actor, repo, owner, err := hydrateAssignmentRequirements(ctx, targetGH, req.ActorId, int64(req.RepoId), req.OwnerId)
	if err != nil {
		return nil, goerrors.Errorf("failed to hydrate assignment requirements: %w", err)
	}

	// Custom agent name may be in the form "name@version", so separate the fields if so
	agentName, agentVersion := customagent.ParseCustomAgentName(req.CustomAgent)

	// Add custom agent
	params := jobservice.GetCustomAgentParams{
		UserID:     int64(cu.Id),
		GHClient:   targetGH,
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

	jobActor := jobs.JobActor{
		ID:         int64(cu.Id),
		Login:      actor.GetLogin(),
		TrackingID: cu.AnalyticsTrackingId,
	}

	issueRepoID := int64(issue.GetRepositoryId())
	if issueRepoID == 0 {
		return nil, goerrors.New("issue missing repository ID")
	}

	issueGH := targetGH
	useCrossRepoClient := issue.GetRepositoryId() != req.GetRepoId()
	if useCrossRepoClient {
		// TODO: The `GetIssueById` call does not return the repo owner's ID - so we need to create a gh client
		// using the NWO instead. We should add the repo owner ID to the response, to avoid this brittle step.
		repoNWO := strings.TrimSpace(issue.GetRepositoryNwo())
		if repoNWO == "" {
			return nil, goerrors.Errorf("issue repository name with owner missing for repository %d", issueRepoID)
		}
		ownerName, repoName, ok := strings.Cut(repoNWO, "/")
		ownerName = strings.TrimSpace(ownerName)
		repoName = strings.TrimSpace(repoName)
		if !ok || ownerName == "" || repoName == "" {
			return nil, goerrors.Errorf("invalid issue repository name with owner: %s", repoNWO)
		}
		issueGH, err = s.ghf.NewClientFromRepoName(ctx, agenticApp, repoName, ownerName, req.ActorId)
		if err != nil {
			return nil, goerrors.Errorf("failed to create GitHub client for issue repository: %w", err)
		}
	}

	issueRepo, err := issueGH.GetRepositoryByID(ctx, issueRepoID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get issue repository by ID: %w", err)
	}
	if issueRepo.GetNodeID() == "" {
		return nil, goerrors.New("issue repository missing node ID")
	}

	actx, err := issueGH.GetIssueContext(ctx, issueRepo.GetNodeID(), int(issue.Number), s.appProvider.IsAgenticActor)
	if err != nil {
		return nil, goerrors.Errorf("failed to get issue context: %w", err)
	}

	baseCommit := getBaseCommitFromRequest(req.BaseBranchName, repo.GetDefaultBranch())

	// Build issue reference - use full NWO format for cross-repo issues to ensure proper linking
	issueRef := fmt.Sprintf("#%d", issue.Number)
	if useCrossRepoClient {
		issueRef = fmt.Sprintf("%s#%d", issue.GetRepositoryNwo(), issue.Number)
	}

	// Generate the PR body suffix to include custom agent info and issue reference
	customAgentQuote := jobapi.GenerateCustomAgentQuote(customAgent)
	// Include additional instructions in the problem statement quote if provided
	problemStatementQuote := jobapi.GenerateProblemStatementQuote(req.GetAdditionalInstructions())
	// The user-provided suffix contains the issue fix reference
	userProvidedSuffix := fmt.Sprintf("* Fixes %s.", issueRef)
	bodySuffix := jobapi.ConstructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix)

	useAsyncSessions := s.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, *repo.ID)

	jb := s.jobService.NewJobBuilder(jobs.AgentActionFix, repo, baseCommit).
		WithNewAssignmentWithCustomAgent(
			*owner.ID,
			*repo.ID,
			owner.GetNodeID(),
			*repo.NodeID,
			owner.GetLogin(),
			*repo.Name,
			useAsyncSessions,
			customAgent,
		).
		WithJobActor(jobActor).
		WithRequestStartedAt(requestctx.RequestStartedAtOrNow(ctx)).
		WithJobInitHook(func(j *jobs.Job) {
			j.IssueNumber = int(issue.GetNumber())
		}).
		WithAgentID(agenticApp.AppID()).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypeAPICallReceived,
			URL:         issue.HtmlUrl,
			Identifiers: []string{fmt.Sprintf("%d", issue.Id)},
			Content:     req.EventContent,
		}).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return problemstatement.NewIssueBuilder(
				s.obsv,
				targetGH,
				actx,
				job.AgentID,
				githubtwirp.NewAuthorResolver(s.obsv, s.ghTwirp, s.ffClient),
				s.appProvider,
				problemstatement.WithAdditionalInstructions(req.GetAdditionalInstructions()),
			).Build(c)
		}).
		WithFeatures(jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				BodyPlaceholder: fmt.Sprintf("Thanks for assigning this issue to me. I'm starting to work on it and will keep this PR's description up to date as I form a plan and make progress.\n\nOriginal issue description:\n\n> %s", strings.ReplaceAll(issue.Body, "\n", "\n> ")),
				BodySuffix:      bodySuffix,
				BaseRef:         baseCommit,
			},
			Branch: &jobs.BranchFeature{
				BaseRef: baseCommit,
			},
		}).
		WithBranchRuleViolationHook(func(ctx context.Context, gh github.ClientInterface, actorLogin string, assignment *jobs.Assignment, result *jobservice.CheckRulesResult) error {
			// TODO: Include failing rules here
			errMsg := "job cannot be created due to the following rule violations"
			return twirp.FailedPrecondition.Error(errMsg)
		})

	_, job, err = jb.Build(ctx, targetGH)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) {
			return nil, twirpErr
		}
		return nil, goerrors.Errorf("failed to build job: %w", err)
	}

	// Queue the job to be processed
	aj, err := s.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return nil, goerrors.Errorf("failed to queue job: %w", err)
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
		Permissions: in.GetPermissions(),
		MCPServers:  mcpServersFromProto(in.GetMcpServers(), in.GetTools()),
	}
}

// mcpServersFromProto converts MCP servers proto map to mcpconfig.JSON.
// It uses the type field to determine which fields are relevant for each server.
// Servers with unknown types or missing required fields are skipped.
// If a server is referenced in agent tools but missing a tools field, it defaults to ["*"].
// TODO (chuxel): This function is a combination of content from internal/mcp/mcpconfig/json.go
// and internal/customagent/config.go, so we should move common logic to public functions instead.
func mcpServersFromProto(in map[string]*jobs_pb.MCPServer, tools []string) mcpconfig.JSON {
	if len(in) == 0 {
		return mcpconfig.JSON{}
	}

	// Build a set of servers referenced in agent tools (format: "server-name/tool-name")
	referencedServers := make(map[string]bool)
	for _, tool := range tools {
		parts := strings.Split(tool, "/")
		if len(parts) >= 2 {
			referencedServers[parts[0]] = true
		}
	}

	servers := make(map[string]mcpconfig.Server, len(in))
	for name, server := range in {
		// If server's tools field is missing but server is referenced in agent tools, default to ["*"]
		serverTools := server.GetTools()
		if len(serverTools) == 0 {
			if !referencedServers[name] {
				continue // tools field is required
			}
			serverTools = []string{"*"}
		}

		s := mcpconfig.Server{
			Tools: serverTools,
			Type:  server.GetType(),
		}

		switch {
		case mcpconfig.IsLocal(server.GetType()):
			// command is required for local servers
			if server.GetCommand() == "" {
				continue
			}
			s.Local = &mcpconfig.Local{
				Command: server.GetCommand(),
				Args:    server.GetArgs(),
				Env:     server.GetEnv(),
			}

		case mcpconfig.IsRemote(server.GetType()):
			// url is required for remote servers
			if server.GetUrl() == "" {
				continue
			}
			s.Remote = &mcpconfig.Remote{
				Type:    server.GetType(),
				URL:     server.GetUrl(),
				Headers: server.GetHeaders(),
			}

		default:
			continue // Skip servers with unknown types
		}

		servers[name] = s
	}

	return mcpconfig.JSON{Servers: servers}
}

// GetJobBySessionID retrieves a job using its session ID.
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
		return nil, goerrors.Errorf("failed to get job by session ID: %w", err)
	}
	if job == nil {
		return nil, twirp.NotFoundError("no job found for session ID")
	}

	return &jobs_pb.GetJobBySessionIDResponse{
		Job: jobToProto(job),
	}, nil
}

// hydrateAssignmentRequirements fetches and returns the actor, repository, and owner details needed to create an assignment.
// TODO: This function makes multiple API calls and should be parallelized, or otherwise optimized (ex: using GraphQL to make one call).
func hydrateAssignmentRequirements(ctx context.Context, gh github.ClientInterface, actorID uint64, repoID int64, ownerID uint64) (*gg.User, *gg.Repository, *gg.User, error) {
	// Get the user by ID to get their login
	user, err := gh.GetUserByID(ctx, actorID)
	if err != nil {
		return nil, nil, nil, goerrors.Errorf("failed to get user by ID: %w", err)
	}

	// Get the repo by ID
	repo, err := gh.GetRepositoryByID(ctx, repoID)
	if err != nil {
		return nil, nil, nil, goerrors.Errorf("failed to get repo by ID: %w", err)
	}

	// If the actor is the owner, we can skip an API call
	if ownerID == actorID {
		return user, repo, user, nil
	}

	// Get the owner by ID to get their login
	owner, err := gh.GetUserByID(ctx, ownerID)
	if err != nil {
		return nil, nil, nil, goerrors.Errorf("failed to get owner by ID: %w", err)
	}

	return user, repo, owner, nil
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

// reqFeaturesToJobFeatures converts the Features from the request proto to the internal jobs.EnvironmentFeatures type.
func reqFeaturesToJobFeatures(reqFeatures *jobs_pb.Features) jobs.EnvironmentFeatures {
	f := jobs.EnvironmentFeatures{}

	if reqFeatures == nil {
		return f
	}

	if reqFeatures.Branch != nil {
		f.Branch = &jobs.BranchFeature{
			Name:    reqFeatures.Branch.Name,
			BaseRef: reqFeatures.Branch.BaseRef,
		}
	}

	if reqFeatures.PullRequest != nil {
		f.PullRequest = &jobs.PullRequestFeature{
			BaseRef: reqFeatures.PullRequest.BaseRef,
			HeadRef: reqFeatures.PullRequest.HeadRef,
		}
	}

	return f
}

// getBaseCommitFromFeatures returns the base branch name from the features if provided,
// otherwise falls back to the default branch.
func getBaseCommitFromFeatures(features *jobs_pb.Features, defaultBranch string) string {
	if features == nil {
		return defaultBranch
	}

	if features.Branch != nil && features.Branch.BaseRef != "" {
		return features.Branch.BaseRef
	}

	if features.PullRequest != nil && features.PullRequest.BaseRef != "" {
		return features.PullRequest.BaseRef
	}

	return defaultBranch
}
