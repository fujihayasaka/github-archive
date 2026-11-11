// Package twirpserver implements the Twirp server for job-related operations.
package twirpserver

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	store "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sandbox"
	"github.com/github/sweagentd/internal/sandbox/stopguard"
	"github.com/github/sweagentd/internal/sweagentd"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/twitchtv/twirp"
)

// maxAdditionalRepositories is the maximum number of additional repositories allowed in a CreateJob request.
const maxAdditionalRepositories = 10

// repositoryAdapter adapts ownership IDs to the sweagentd.Repository interface.
type repositoryAdapter struct {
	ownerID int64
	repoID  int64
}

func (r *repositoryAdapter) GetRepositoryID() int64 {
	return r.repoID
}

func (r *repositoryAdapter) GetOwnerID() int64 {
	return r.ownerID
}

// sandboxOps captures the subset of sandbox.Service methods used by the
// Twirp server. Defined here at the consumer to allow tests to substitute a
// fake implementation.
type sandboxOps interface {
	CreateSandbox(ctx context.Context, params *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error)
	StopSandbox(ctx context.Context, sandboxID string, actorID uint64) error
	ResumeSandbox(ctx context.Context, sandboxID string, actorID uint64) error
	DeleteSandbox(ctx context.Context, sandboxID string, actorID uint64) error
	GetSandboxState(ctx context.Context, sandboxID string, actorID uint64) (string, error)
	GetSandboxInfo(ctx context.Context, sandboxID string, actorID uint64) (*sandbox.Info, error)
	ResumeCopilotCLI(ctx context.Context, sandboxID string, actorID uint64, repoNWO string, freshEnv map[string]string) error
}

type jobstore interface {
	GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error)
	GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error)
	GetLatestAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error)
	GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error)
	GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error)
	ListJobsForPullRequestNumber(ctx context.Context, owner, repo int64, prNumber int) ([]*jobs.Job, error)
	CreateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error)
	PatchAssignment(ctx context.Context, assignment *jobs.Assignment, patch store.AssignmentPatch, opts ...store.PatchAssignmentOption) error
}

// Server implements the Twirp RPC handlers for job operations.
type Server struct {
	obsv           observability.Exporters
	ghf            github.ClientFactoryInterface
	ghTwirp        githubtwirp.ClientInterface
	jobStore       jobstore
	jobService     *jobservice.Service
	ffClient       featureflags.Client
	appProvider    *agenticapp.Provider
	jobExecutor    jobexecutor.JobExecutor
	sandboxService sandboxOps
	aqueductClient sweagentd.AqueductClient
	stopGuard      *stopguard.Guard
	memoryService  memoryService
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
	jobExecutor jobexecutor.JobExecutor,
	sandboxService *sandbox.Service,
	aqueductClient sweagentd.AqueductClient,
	stopGuard *stopguard.Guard,
) *Server {
	return &Server{
		obsv:           obsv,
		ghf:            ghf,
		ghTwirp:        ghTwirp,
		jobStore:       jobStore,
		jobService:     jobService,
		ffClient:       ffClient,
		appProvider:    appProvider,
		jobExecutor:    jobExecutor,
		sandboxService: sandboxService,
		aqueductClient: aqueductClient,
		stopGuard:      stopGuard,
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

				headers, ok := twirp.HTTPRequestHeaders(ctx)
				if ok {
					// Store integration client from User-Agent so TelemetryTags
					// includes it even without the *http.Request.
					_ = requestctx.AddIntegrationClient(ctx, headers.Get("User-Agent"))

					if s.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentTwirpProximaHookHeadersOnly) {
						err := addTenantContextFromHeaders(ctx, headers)
						if err != nil {
							return ctx, err
						}
					}
				}

				return ctx, nil
			},
		},
		hooks,
	)
}

func addTenantContextFromHeaders(ctx context.Context, headers http.Header) error {
	if slug := headers.Get(requestctx.GitHubTenantHeader); slug != "" {
		err := requestctx.AddTenantSlug(ctx, slug)
		if err != nil {
			return goerrors.Errorf("failed to add tenant slug to context: %w", err)
		}
	}

	if id := headers.Get(requestctx.GitHubTenantIDHeader); id != "" {
		err := requestctx.AddTenantID(ctx, id)
		if err != nil {
			return goerrors.Errorf("failed to add tenant id to context: %w", err)
		}
	}

	return nil
}

// ListJobsForPullRequest retrieves all jobs associated with a specific pull request.
func (s *Server) ListJobsForPullRequest(ctx context.Context, req *jobs_pb.ListJobsForPullRequestRequest) (*jobs_pb.ListJobsForPullRequestResponse, error) {
	var assignment *jobs.Assignment
	var err error

	repo := &repositoryAdapter{ownerID: req.GetOwnerId(), repoID: req.GetRepoId()}

	assignment, err = s.getAssignmentForPR(ctx, repo, &req.PullRequestId, nil)

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

// ListJobsForPullRequestByNumber returns all jobs for a pull request number across every
// assignment, so callers can determine whether any automation job has ever touched the PR.
func (s *Server) ListJobsForPullRequestByNumber(ctx context.Context, req *jobs_pb.ListJobsForPullRequestByNumberRequest) (*jobs_pb.ListJobsForPullRequestByNumberResponse, error) {
	jobsForPR, err := s.jobStore.ListJobsForPullRequestNumber(ctx, req.GetOwnerId(), req.GetRepoId(), int(req.GetPullRequestNumber()))
	if err != nil {
		return nil, err
	}

	j := make([]*jobs_pb.Job, len(jobsForPR))
	for i := range jobsForPR {
		j[i] = jobToProto(jobsForPR[i])
	}
	return &jobs_pb.ListJobsForPullRequestByNumberResponse{
		Jobs: j,
	}, nil
}

// CreateJob creates a new job for an assignment with a custom problem statement.
// Depending on features and flags, the job may be a task or a fix (for example, for a pull request).
func (s *Server) CreateJob(ctx context.Context, req *jobs_pb.CreateJobRequest) (*jobs_pb.CreateJobResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateJob")
	defer span.End()

	// Validate fields not covered by CreateAssignment/CreateJobForAssignment
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

	// Check quota once for the entire CreateJob flow, so that the internal
	// createAssignment and createJobForAssignment calls don't repeat this check.
	// Apps/integrations with the check exemption flag enabled are exempt.
	if !s.appProvider.IsAgentCheckExempt(ctx, s.ffClient, req.AgentId, int64(req.RepoId)) {
		err := CheckQuota(ctx, s.ghTwirp, s.ffClient, s.obsv, int64(req.OwnerId), int64(req.RepoId), int64(req.ActorId), "job")
		if err != nil {
			return nil, err
		}
	}

	// Fetch the repo once so both createAssignment and createJobForAssignment can reuse it.
	gh, err := s.ghf.NewClientFromRepo(ctx, s.appProvider.CopilotApp(), int64(req.RepoId), int64(req.OwnerId))
	if err != nil {
		return nil, goerrors.Errorf("failed to create gh client: %w", err)
	}
	repo, err := gh.GetRepositoryByID(ctx, int64(req.RepoId))
	if err != nil {
		return nil, goerrors.Errorf("failed to get repo by ID: %w", err)
	}

	additionalRepositories, err := s.fetchAdditionalRepositories(ctx, req.GetAdditionalRepositories(), int64(req.GetActorId()), int64(req.GetRepoId()))
	if err != nil {
		return nil, goerrors.Errorf("failed to fetch additional repositories: %w", err)
	}

	// Step 1: Create a new assignment
	assignmentResp, err := s.createAssignment(ctx, int64(req.OwnerId), int64(req.RepoId), repo, additionalRepositories)
	if err != nil {
		return nil, goerrors.Errorf("failed to create assignment: %w", err)
	}

	// If HeadRef is provided and the feature flag is enabled, look up an existing
	// PR for that branch and link the assignment to it. This allows the builder
	// to skip PR creation and work on the existing PR's branch.
	features := reqFeaturesToJobFeatures(req.Features)
	baseRef := repo.GetDefaultBranch()
	if features.PullRequest != nil && features.PullRequest.BaseRef != "" {
		baseRef = features.PullRequest.BaseRef
	} else if features.Branch != nil && features.Branch.BaseRef != "" {
		baseRef = features.Branch.BaseRef
	}
	skipDefaultBranchCheck := s.shouldSkipDefaultBranchHeadRefCheck(ctx, int64(req.ActorId), int64(req.RepoId), req.AgentId)

	existingPR, err := s.lookupExistingPRForHeadRef(ctx, gh, repo, &features, assignmentResp.Id, baseRef, skipDefaultBranchCheck)
	if err != nil {
		return nil, err
	}

	// Step 2: Create a job for the assignment
	params := createJobForAssignmentParamsFromRequest(&jobs_pb.CreateJobForAssignmentRequest{
		ActorId:                req.ActorId,
		RepoId:                 req.RepoId,
		OwnerId:                req.OwnerId,
		ProblemStatement:       req.ProblemStatement,
		AgentId:                uint64(req.AgentId),
		EventUrl:               req.EventUrl,
		EventIdentifiers:       req.EventIdentifiers,
		EventContent:           req.EventContent,
		AssignmentId:           assignmentResp.Id,
		CustomAgent:            req.CustomAgent,
		CustomAgentAttributes:  req.CustomAgentAttributes,
		Features:               req.Features,
		Model:                  req.Model,
		EventType:              req.EventType,
		AdditionalRepositories: req.AdditionalRepositories,
	}, repo)
	// Use the local features which may have HeadRef cleared on PR lookup failure,
	// rather than re-converting from the original proto.
	params.Features = features
	if existingPR != nil {
		params.PullRequestID = existingPR.GetID()
		params.PullRequestNumber = existingPR.GetNumber()
	}
	jobResult, err := s.jobService.CreateJobForAssignment(ctx, params)
	if err != nil {
		return nil, mapJobServiceError(err)
	}

	return &jobs_pb.CreateJobResponse{
		JobId:             jobResult.Job.ID,
		SessionId:         jobResult.SessionID,
		PullRequestId:     jobResult.Job.PullRequestID,
		PullRequestNumber: int64(jobResult.Job.PullRequestNumber),
	}, nil
}

func customAgentAttributesFromProto(in *jobs_pb.CustomAgentAttributes) *jobservice.GetCustomAgentParamsAttributes {
	if in == nil {
		return nil
	}

	return &jobservice.GetCustomAgentParamsAttributes{
		DisplayName:       in.GetDisplayName(),
		Description:       in.GetDescription(),
		Prompt:            in.GetPrompt(),
		Tools:             in.GetTools(),
		Permissions:       in.GetPermissions(),
		GitHubMCPToolsets: in.GetGithubMcpToolsets(),
		MCPServers:        mcpServersFromProto(in.GetMcpServers(), in.GetTools()),
		Skills:            in.GetSkills(),
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

func (s *Server) fetchAdditionalRepositories(ctx context.Context, inputRepositories []*jobs_pb.CreateJobRepositoryRef, actorID, repoID int64) ([]*gg.Repository, error) {
	if len(inputRepositories) == 0 || !s.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentMultiRepoRead, actorID, repoID) {
		return nil, nil
	}

	if len(inputRepositories) > maxAdditionalRepositories {
		return nil, twirp.InvalidArgumentError("additional_repositories", fmt.Sprintf("more than maximum of %d additional repositories provided", maxAdditionalRepositories))
	}

	additionalRepositories := make([]*gg.Repository, len(inputRepositories))
	for i, additionalRepository := range inputRepositories {
		// TODO (houndie):  We should probably create one client that's scoped
		// to all of these repositories, instead of creating a new one each time.
		additionalGH, err := s.ghf.NewClientFromRepo(ctx, s.appProvider.CopilotApp(), int64(additionalRepository.GetRepoId()), int64(additionalRepository.GetOwnerId()))
		if err != nil {
			return nil, goerrors.Errorf("failed to create additional repo gh client: %w", err)
		}

		additionalRepo, err := additionalGH.GetRepositoryByID(ctx, int64(additionalRepository.GetRepoId()))
		if err != nil {
			return nil, goerrors.Errorf("failed to get additional repo by ID: %w", err)
		}

		additionalRepositories[i] = additionalRepo
	}

	return additionalRepositories, nil
}

// getAssignmentForPR returns the assignment for the given PR, using GetLatestAssignmentForPR
// when the CopilotSWEAgentGetLatestAssignment feature flag is enabled.
func (s *Server) getAssignmentForPR(ctx context.Context, repo *repositoryAdapter, id *int64, number *int) (*jobs.Assignment, error) {
	if s.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentGetLatestAssignment, repo) {
		return s.jobStore.GetLatestAssignmentForPR(ctx, repo.GetOwnerID(), repo.GetRepositoryID(), id, number)
	}
	return s.jobStore.GetAssignmentForPR(ctx, repo.GetOwnerID(), repo.GetRepositoryID(), id, number)
}

// shouldSkipDefaultBranchHeadRefCheck returns true when the default-branch
// rejection in lookupExistingPRForHeadRef should be bypassed:
//   - the CopilotSWEAgentSkipDefaultBranchHeadRefCheck feature flag is enabled
//     for the actor or repo, OR
//   - the agent implements sweagentd.AgenticAppBranchlessMode and returns
//     SkipBranchAndPRCreation() == true (e.g., Copilot Code Review never pushes
//     commits to head_ref).
func (s *Server) shouldSkipDefaultBranchHeadRefCheck(ctx context.Context, actorID, repoID, agentID int64) bool {
	if s.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentSkipDefaultBranchHeadRefCheck, actorID, repoID) {
		return true
	}
	agent, lookupErr := s.appProvider.FindByID(ctx, agentID)
	if lookupErr != nil {
		return false
	}
	bl, ok := agent.(sweagentd.AgenticAppBranchlessMode)
	return ok && bl.SkipBranchAndPRCreation()
}

// lookupExistingPRForHeadRef finds an open PR whose head matches HeadRef from
// the request features. When found, it links the assignment to the PR so the
// builder skips PR creation and works on the existing branch.
func (s *Server) lookupExistingPRForHeadRef(
	ctx context.Context,
	gh github.ClientInterface,
	repo *gg.Repository,
	features *jobs.EnvironmentFeatures,
	assignmentID string,
	baseRef string,
	skipDefaultBranchCheck bool,
) (*gg.PullRequest, error) {
	if features.PullRequest == nil || features.PullRequest.HeadRef == "" {
		return nil, nil
	}

	headRef := strings.TrimPrefix(features.PullRequest.HeadRef, "refs/heads/")
	features.PullRequest.HeadRef = headRef

	// Extract just the branch name for the default branch check.
	// HeadRef may be "owner:branch" for fork PRs.
	branchOnly := github.BranchNameFromHeadRef(headRef)

	// Prevent the agent from committing directly to the default branch,
	// unless the caller has opted out (e.g., branchless agents that operate
	// on an existing PR and never push commits).
	if !skipDefaultBranchCheck && branchOnly == repo.GetDefaultBranch() {
		return nil, twirp.InvalidArgumentError("features.pull_request.head_ref", fmt.Sprintf("branch %q (from head_ref %q) matches the repository default branch; the agent cannot push directly to the default branch", branchOnly, headRef))
	}
	pr, multipleFound, prErr := github.LookupExistingPRForHeadRef(ctx, gh, repo.GetOwner().GetLogin(), repo.GetName(), headRef, baseRef)
	if prErr != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(prErr).WithFields(
			kvp.String("head_ref", headRef),
		).Warn("failed to look up existing PRs for HeadRef, clearing HeadRef to allow fallback PR creation")
		s.obsv.Increment(ctx, "pr_lookup.failure", stats.Tags{"entry_point": "twirp"})
		features.PullRequest.HeadRef = ""
		return nil, nil
	}
	if multipleFound {
		s.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("head_ref", headRef),
		).Warn("multiple open PRs found for HeadRef, linking PR that matches base ref")
	}
	if pr == nil {
		features.PullRequest.HeadRef = ""
		return nil, nil
	}

	// For fork PRs, the fork branch doesn't exist on the base repo, so
	// clear HeadRef to fall back to the default branch as the workflow Ref.
	// The workflow checks out the PR's head SHA regardless of the Ref used
	// to dispatch it.
	if branchOnly != headRef {
		features.PullRequest.HeadRef = ""
	}

	s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Int("pr_number", pr.GetNumber()),
		kvp.Int64("pr_id", pr.GetID()),
		kvp.String("assignment_id", assignmentID),
		kvp.String("head_ref", headRef),
	).Info("found existing PR for HeadRef, linking assignment to PR")

	return pr, nil
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

	if reqFeatures.CopilotSetupSteps != nil {
		f.CopilotSetupSteps = &jobs.CopilotSetupStepsFeature{
			Skip:    reqFeatures.CopilotSetupSteps.GetSkip(),
			Exclude: reqFeatures.CopilotSetupSteps.GetExclude(),
			Only:    reqFeatures.CopilotSetupSteps.GetOnly(),
		}
	}

	return f
}
