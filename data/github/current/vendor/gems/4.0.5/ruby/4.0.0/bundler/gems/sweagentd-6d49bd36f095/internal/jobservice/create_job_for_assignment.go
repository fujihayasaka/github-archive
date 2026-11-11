package jobservice

import (
	"context"
	"errors"
	"fmt"
	"strings"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"go.opentelemetry.io/otel/attribute"
)

// ErrAgentNotEnabled is returned when the user or repo does not have the coding agent enabled.
var ErrAgentNotEnabled = goerrors.New("user or repo does not have CCA enabled")

// ErrAgentNotFound is returned when the requested agent is not found
var ErrAgentNotFound = goerrors.New("requested agent not found")

// ErrJobAlreadyInProgress is returned when a job is already queued or running for the assignment.
var ErrJobAlreadyInProgress = goerrors.New("a job is already queued or running for this assignment")

// ErrBotActorNotAllowed is returned when the actor is a bot, which is not supported for job creation.
var ErrBotActorNotAllowed = goerrors.New("bot actors are not allowed to create jobs")

// ErrResumeNoProblemStatement is returned when a resume job is requested but no prior problem statement can be found to inherit.
var ErrResumeNoProblemStatement = goerrors.New("resume job has no problem statement to inherit")

// CreateJobForAssignmentParams holds the parameters for creating a job for an assignment.
// All fields use plain Go types rather than protobuf types.
type CreateJobForAssignmentParams struct {
	ActorID          int64
	OwnerID          int64
	RepoID           int64
	AssignmentID     string
	AgentID          int64
	Model            string
	ProblemStatement string
	Features         jobs.EnvironmentFeatures
	HasFeatures      bool // whether features were explicitly provided by the caller

	// Event fields
	EventType        string
	EventURL         string
	EventIdentifiers []string
	EventContent     string

	// Custom agent fields
	CustomAgentName       string
	CustomAgentVersion    string
	CustomAgentAttributes *GetCustomAgentParamsAttributes

	// PullRequest fields for linking an existing PR to the assignment.
	// When set, the builder will use WithAssignmentPullRequest to persist
	// the link during Build().
	PullRequestID     int64
	PullRequestNumber int

	// Repo can be pre-fetched to avoid redundant API calls
	Repo *gg.Repository

	// BranchRuleViolationHook is called when branch rules are violated during job creation.
	BranchRuleViolationHook BranchRuleViolationHookFunc

	// ResumeSessionID, when set, identifies a session this job should resume.
	// It is forwarded to the launched runtime container so the runtime can
	// load the matching events.jsonl snapshot and call client.resumeSession,
	// and is also threaded through the agent compute env so cross-job
	// progress lookups can scope to the right session. Empty for new jobs;
	// behavior in that case is unchanged.
	ResumeSessionID string
}

// CreateJobForAssignmentResult holds the result of creating a job for an assignment.
type CreateJobForAssignmentResult struct {
	Job       *jobs.Job
	SessionID string
}

// assignmentContext holds the resolved dependencies needed to build a job for an assignment.
type assignmentContext struct {
	appID       int64
	userDetails *copilotUsersTwirp.CopilotUserDetails
	gh          github.ClientInterface
	actor       *gg.User
	repo        *gg.Repository
}

// setupAssignmentContext validates enablement and gathers the external
// dependencies (app, user, GH client, actor, repo) required to build a job.
func (s *Service) setupAssignmentContext(ctx context.Context, params *CreateJobForAssignmentParams) (*assignmentContext, error) {
	agenticApp, err := s.appProvider.FindByID(ctx, params.AgentID)
	if err != nil {
		return nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
	}

	// Validate the user/repo has CCA enabled.
	// First-party external agents that manage their own enablement checks
	// (e.g., CCRA) are exempt from the monolith's disallow-flag gate.
	isEnabled, result, err := s.twirp.IsAgentEnabled(ctx, agenticApp.AppID(), params.ActorID, params.RepoID)
	if err != nil {
		return nil, goerrors.Errorf("failed to check repo enablement: %w", err)
	}
	if !isEnabled {
		if agenticApp.IsThirdPartyApp() {
			return nil, ErrAgentNotEnabled
		}
		if exempt, ok := agenticApp.(sweagentd.AgenticAppEnablementExempt); !ok || !exempt.SkipEnablementCheck() {
			return nil, ErrAgentNotEnabled
		}
	}
	if result != nil && !s.ffs.IsEnabled(ctx, featureflags.CopilotSWEAgentTwirpProximaHookHeadersOnly) {
		tenantErr := addTenantContext(ctx, result.TenantSlug, result.TenantId)
		if tenantErr != nil {
			return nil, tenantErr
		}
	}

	userDetails, err := s.twirp.GetCopilotUserDetails(ctx, params.ActorID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get user's Copilot details: %w", err)
	}

	gh, err := s.ghf.NewClientFromRepo(ctx, agenticApp, params.RepoID, params.OwnerID)
	if err != nil {
		return nil, goerrors.Errorf("failed to create gh client: %w", err)
	}

	actor, repo, _, err := hydrateRequirements(ctx, gh, uint64(params.ActorID), params.RepoID, uint64(params.OwnerID), params.Repo)
	if err != nil {
		// When transport-level token refresh is not enabled, fall back to
		// the original evict-and-retry logic for stale tokens (e.g. app reinstall).
		if !s.ffs.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentClientTokenRefreshOn401, params.RepoID) {
			var apiErr *github.GitHubAPIError
			if errors.As(err, &apiErr) && apiErr.StatusCode() == 401 {
				s.ghf.InvalidateTokenForRepo(agenticApp, params.RepoID, params.OwnerID)
				gh, err = s.ghf.NewClientFromRepo(ctx, agenticApp, params.RepoID, params.OwnerID)
				if err != nil {
					return nil, goerrors.Errorf("failed to create gh client after token refresh: %w", err)
				}
				actor, repo, _, err = hydrateRequirements(ctx, gh, uint64(params.ActorID), params.RepoID, uint64(params.OwnerID), params.Repo)
			}
		}
		if err != nil {
			return nil, goerrors.Errorf("failed to hydrate assignment requirements: %w", err)
		}
	}

	// Reject bot actors early — bots don't have Copilot seats or valid billing,
	// so allowing them through would cause failures in downstream calls.
	if s.ffs.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentRejectBotActors, params.RepoID) &&
		strings.EqualFold(actor.GetType(), "Bot") {
		return nil, ErrBotActorNotAllowed
	}

	return &assignmentContext{
		appID:       agenticApp.AppID(),
		userDetails: userDetails,
		gh:          gh,
		actor:       actor,
		repo:        repo,
	}, nil
}

// setupCustomAgent parses the custom agent name/version from the
// params and looks up the matching agent definition.
//
// For follow-up jobs in an existing assignment, when the request omits a
// custom agent (no name, no version, no inline attributes) the previous
// job's custom agent is inherited so the agent selected at task start
// persists across the entire thread (issue #12007). This mirrors the
// inheritance done for branch and model and avoids silently falling back
// to the default Copilot agent. Non-job-scoped agents are re-resolved via
// GetCustomAgent to preserve enablement, auth, and user-invocable checks.
func (s *Service) setupCustomAgent(ctx context.Context, params *CreateJobForAssignmentParams, userDetails *copilotUsersTwirp.CopilotUserDetails, gh github.ClientInterface, repo *gg.Repository, latestJob *jobs.Job) (sweagentd.CustomAgent, error) {
	resolveAgent := func(name, version string) (sweagentd.CustomAgent, error) {
		caParams := GetCustomAgentParams{
			UserID:     int64(userDetails.Id),
			GHClient:   gh,
			GHRepo:     repo,
			Name:       name,
			Version:    version,
			Attributes: params.CustomAgentAttributes,
		}
		agent, err := s.GetCustomAgent(ctx, caParams)
		if err != nil {
			if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
				return nil, goerrors.Errorf("%w: %w", ErrAgentNotFound, err)
			}
			return nil, goerrors.Errorf("failed to get custom agent: %w", err)
		}
		return agent, nil
	}

	if params.CustomAgentName == "" && params.CustomAgentVersion == "" && params.CustomAgentAttributes == nil &&
		latestJob != nil && !latestJob.CustomAgent.IsCopilot() {
		s.obsv.LoggerWithTelemetry(ctx).Info("Inheriting custom agent from latest job",
			kvp.String("inherited_custom_agent_name", latestJob.CustomAgent.Name),
			kvp.String("inherited_custom_agent_version", latestJob.CustomAgent.Version),
			kvp.String("inherited_custom_agent_scope", latestJob.CustomAgent.Scope),
		)

		// Keep FromDB reconstruction only for job-scoped agents, because non-job-scoped
		// agents must be resolved through the authenticated lookup path.
		if latestJob.CustomAgent.Scope == agentconfig.ScopeJob {
			if !s.customAgentSvc.IsEnabledForRepo(ctx, int64(userDetails.Id), repo.Owner.GetID(), repo.GetID()) {
				return customagent.Copilot(repo.Owner.GetID(), repo.GetID(), repo.Owner.GetLogin(), repo.GetName()), nil
			}
			agent, err := s.customAgentSvc.FromDB(ctx, latestJob.CustomAgent)
			if err != nil {
				return nil, goerrors.Errorf("failed to inherit custom agent from latest job: %w", err)
			}
			return agent, nil
		}

		agent, err := resolveAgent(latestJob.CustomAgent.Name, latestJob.CustomAgent.Version)
		if err != nil {
			return nil, goerrors.Errorf("failed to inherit custom agent from latest job: %w", err)
		}
		return agent, nil
	}

	agentName, agentVersion := customagent.ParseCustomAgentName(params.CustomAgentName)
	if params.CustomAgentVersion != "" {
		agentVersion = params.CustomAgentVersion
	}
	return resolveAgent(agentName, agentVersion)
}

// CreateJobForAssignment creates a new job for the given assignment.
// It handles agent enablement checks, branch resolution, custom agent resolution,
// job building, and queuing. Callers are responsible for request validation and quota checks.
func (s *Service) CreateJobForAssignment(ctx context.Context, params *CreateJobForAssignmentParams) (*CreateJobForAssignmentResult, error) { //nolint:maintidx // pre-existing complexity
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CreateJobForAssignment")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("assignment_id", params.AssignmentID))

	logger.Info("Creating job for assignment",
		kvp.Int64("agent_id", params.AgentID),
		kvp.String("model", params.Model),
	)

	assignment, err := s.store.GetAssignment(ctx, params.OwnerID, params.RepoID, params.AssignmentID)
	if err != nil {
		if errors.Is(err, db.ErrAssignmentNotFound) {
			return nil, goerrors.Errorf("failed to get assignment: %w", ErrAssignmentNotFound)
		}
		return nil, goerrors.Errorf("failed to get assignment: %w", err)
	}

	assignmentJobs, err := s.store.GetJobsForAssignment(ctx, assignment)
	if err != nil {
		return nil, goerrors.Errorf("failed to get jobs for assignment: %w", err)
	}

	logger.Info(fmt.Sprintf("Found %d previous jobs for assignment", len(assignmentJobs)))

	if s.hasActiveJobs(ctx, assignmentJobs, params.ActorID, params.RepoID) {
		return nil, ErrJobAlreadyInProgress
	}

	latestJob := GetMostRecentJob(assignmentJobs)

	ac, err := s.setupAssignmentContext(ctx, params)
	if err != nil {
		return nil, err
	}

	// CCR (Copilot Code Review) jobs never need a branch.
	branchConfig := ResolveBranchConfig(ac.repo, latestJob, params.Features, s.appProvider.IsCopilotCodeReviewApp(params.AgentID))
	isFollowUp := branchConfig.InheritedBranch != ""
	span.SetAttributes(
		attribute.Bool("job.is_follow_up", isFollowUp),
		attribute.Bool("job.branch_config.needs_new_branch", branchConfig.NeedsNewBranch),
	)

	customAgent, err := s.setupCustomAgent(ctx, params, ac.userDetails, ac.gh, ac.repo, latestJob)
	if err != nil {
		return nil, err
	}

	problemStatementContent := strings.TrimSpace(params.ProblemStatement)

	// For resume jobs, the caller is allowed to omit problem_statement.
	// Inherit the latest job's problem statement so the resumed runtime
	// has the same task context as the run that timed out.
	if problemStatementContent == "" && params.ResumeSessionID != "" && latestJob != nil {
		problemStatementContent = strings.TrimSpace(latestJob.ProblemStatement.Content)
		logger.Info("Inheriting problem statement from latest job for resume",
			kvp.String("resume_session_id", params.ResumeSessionID),
			kvp.Int("inherited_problem_statement_length", len(problemStatementContent)))
	}

	// Reject resume jobs that have no problem statement after inheritance attempt.
	if params.ResumeSessionID != "" && problemStatementContent == "" {
		return nil, ErrResumeNoProblemStatement
	}

	// Set default PR placeholders when creating a new pull request
	if branchConfig.Features.PullRequest != nil && branchConfig.Features.PullRequest.TitlePlaceholder == "" {
		branchConfig.Features.PullRequest.TitlePlaceholder = "[WIP] Copilot Request"
		branchConfig.Features.PullRequest.BodyPlaceholder = fmt.Sprintf("%s\n> %s\n", PRBodyPrefix, strings.ReplaceAll(problemStatementContent, "\n", "\n> "))
	}

	jobActor := jobs.JobActor{
		ID:         int64(ac.userDetails.Id),
		Login:      ac.actor.GetLogin(),
		TrackingID: ac.userDetails.AnalyticsTrackingId,
	}

	var headRef string
	if branchConfig.Features.PullRequest != nil {
		headRef = branchConfig.Features.PullRequest.HeadRef
	}
	action := jobs.ResolveAction(branchConfig.Features.PullRequest != nil, headRef)
	logger.Info("Resolved agent action",
		kvp.String("action", string(action)),
		kvp.Int64("actor_id", params.ActorID),
		kvp.Bool("has_pull_request_feature", branchConfig.Features.PullRequest != nil))

	// Default to api_call_received if not provided. On resume, inherit the
	// originating job's event type so trigger-specific runtime behavior (e.g.
	// using the automation prompt as the problem statement) is re-applied for
	// the resumed run, which omits the event type.
	eventType := jobs.EventType(params.EventType)
	if eventType == "" {
		if params.ResumeSessionID != "" && latestJob != nil && latestJob.EventType != "" {
			eventType = latestJob.EventType
		} else {
			eventType = jobs.EventTypeAPICallReceived
		}
	}

	jb := s.NewJobBuilder(action, ac.repo, branchConfig.BaseRef).
		ForAssignment(assignment).
		WithJobActor(jobActor).
		WithRequestStartedAt(requestctx.RequestStartedAtOrNow(ctx)).
		WithJobInitHook(func(j *jobs.Job) {
			// Inherit model from previous job if not specified in request
			if latestJob != nil && params.Model == "" {
				logger.Info("Inheriting model from latest job", kvp.String("inherited_model", latestJob.Model))
				j.Model = latestJob.Model
				j.IsAutoMode = false
			}
			// Inherit branch name for follow-up sessions
			if branchConfig.InheritedBranch != "" {
				j.BranchName = branchConfig.InheritedBranch
			}
			// Resume target, if any, propagates from the request through
			// the job to the launcher (which sets COPILOT_AGENT_RESUME_SESSION_ID
			// on the runtime container).
			if params.ResumeSessionID != "" {
				j.ResumeSessionID = params.ResumeSessionID
			}
		}).
		WithCustomAgent(customAgent).
		WithModel(params.Model).
		WithAgentID(ac.appID).
		WithEvent(Event{
			Type:        eventType,
			URL:         params.EventURL,
			Identifiers: params.EventIdentifiers,
			Content:     params.EventContent,
		}).
		WithProblemStatement(&jobs.ProblemStatement{
			Content: problemStatementContent,
		}).
		WithNewSession().
		WithAINameGen().
		WithExperiments().
		WithWorkflowsAccess(jobs.InheritedWorkflowsAccess(assignmentJobs, ac.appID))

	if params.PullRequestID != 0 && params.PullRequestNumber != 0 {
		jb.WithAssignmentPullRequest(params.PullRequestID, params.PullRequestNumber)
		jb.WithRespectAssignmentModified()
	}

	if params.BranchRuleViolationHook != nil {
		jb = jb.WithBranchRuleViolationHook(params.BranchRuleViolationHook)
	}

	// Apply features if needed (either from request or to trigger branch creation)
	if branchConfig.NeedsNewBranch || params.HasFeatures {
		jb = jb.WithFeatures(branchConfig.Features)
	}

	_, job, err := jb.Build(ctx, ac.gh)
	if err != nil {
		return nil, goerrors.Errorf("failed to build job: %w", err)
	}

	aj, err := s.QueueJobForExecution(ctx, job)
	if err != nil {
		return nil, goerrors.Errorf("failed to queue job: %w", err)
	}

	return &CreateJobForAssignmentResult{
		Job:       job,
		SessionID: aj.SessionId,
	}, nil
}

// addTenantContext adds tenant slug and ID to the request context if present.
func addTenantContext(ctx context.Context, tenantSlug, tenantID string) error {
	if tenantSlug != "" {
		err := requestctx.AddTenantSlug(ctx, tenantSlug)
		if err != nil {
			return goerrors.Errorf("failed to add tenant slug to context: %w", err)
		}
	}
	if tenantID != "" {
		err := requestctx.AddTenantID(ctx, tenantID)
		if err != nil {
			return goerrors.Errorf("failed to add tenant id to context: %w", err)
		}
	}
	return nil
}

// hydrateRequirements fetches and returns the actor, repository, and owner details needed to create a job.
// If repo is non-nil, it is used directly instead of being re-fetched.
func hydrateRequirements(ctx context.Context, gh github.ClientInterface, actorID uint64, repoID int64, ownerID uint64, repo *gg.Repository) (*gg.User, *gg.Repository, *gg.User, error) {
	user, err := gh.GetUserByID(ctx, actorID)
	if err != nil {
		return nil, nil, nil, goerrors.Errorf("failed to get user by ID: %w", err)
	}

	if repo == nil {
		repo, err = gh.GetRepositoryByID(ctx, repoID)
		if err != nil {
			return nil, nil, nil, goerrors.Errorf("failed to get repo by ID: %w", err)
		}
	}

	if ownerID == actorID {
		return user, repo, user, nil
	}

	owner, err := gh.GetUserByID(ctx, ownerID)
	if err != nil {
		return nil, nil, nil, goerrors.Errorf("failed to get owner by ID: %w", err)
	}

	return user, repo, owner, nil
}

// hasActiveJobs returns true when the assignment already has a non-terminal
// (queued/running) job
func (s *Service) hasActiveJobs(ctx context.Context, assignmentJobs []*jobs.Job, actorID, repoID int64) bool {
	if !s.ffs.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentDedupJobCreation, actorID, repoID) {
		return false
	}
	hasActive, activeJobID := jobs.HasQueuedOrRunningJobs(assignmentJobs)
	if hasActive {
		s.obsv.LoggerWithTelemetry(ctx).Info("Active job already exists",
			kvp.String("active_job_id", activeJobID))
	}
	return hasActive
}

// BranchConfig holds the resolved branch configuration for a job.
type BranchConfig struct {
	// BaseRef is the branch to use as the base for the job (passed to NewJobBuilder)
	BaseRef string
	// InheritedBranch is set when reusing an existing branch from a previous job
	InheritedBranch string
	// NeedsNewBranch indicates whether a new branch needs to be created
	NeedsNewBranch bool
	// Features contains the environment features to apply
	Features jobs.EnvironmentFeatures
}

// ResolveBranchConfig determines the branch configuration for a new job based on:
// 1. Explicit features from the request (highest priority)
// 2. Branch inherited from the most recent job in the assignment
// 3. Creating a new branch from the repo's default branch (fallback)
//
// When branchlessEnabled is true and no branch/PR features are provided,
// the job runs on the default branch without creating a new one.
//
// Branch.BaseRef and PullRequest.BaseRef take priority over Branch.Name when
// determining the base ref, preventing cases where the head branch is
// incorrectly used as the PR base.
func ResolveBranchConfig(repo *gg.Repository, latestJob *jobs.Job, features jobs.EnvironmentFeatures, branchlessEnabled bool) BranchConfig {
	// Case 1: Explicit features provided — derive base ref from BaseRef fields (or default branch)
	if features.Branch != nil || features.PullRequest != nil {
		// Prioritize explicit base refs; Branch.Name is the head branch to create,
		// so it must not be used as the base ref.
		var baseRef string
		switch {
		case features.Branch != nil && features.Branch.BaseRef != "":
			baseRef = features.Branch.BaseRef
		case features.PullRequest != nil && features.PullRequest.BaseRef != "":
			baseRef = features.PullRequest.BaseRef
		default:
			baseRef = repo.GetDefaultBranch()
		}
		return BranchConfig{
			BaseRef:        baseRef,
			NeedsNewBranch: features.Branch != nil || features.PullRequest != nil,
			Features:       features,
		}
	}

	// Case 2: No features - try to inherit branch from previous job.
	if latestJob != nil && latestJob.BranchName != "" {
		// Use the previous job's BaseCommit (the original base, e.g. "main") so PRs
		// target the correct branch, and inherit BranchName so the job continues
		// working on the existing feature branch.
		baseRef := latestJob.BaseCommit
		if baseRef == "" {
			baseRef = repo.GetDefaultBranch()
		}
		return BranchConfig{
			BaseRef:         baseRef,
			InheritedBranch: latestJob.BranchName,
			NeedsNewBranch:  false,
			Features:        features,
		}
	}

	// Case 3: No features and no branch to inherit — branchless if enabled
	if branchlessEnabled {
		return BranchConfig{
			BaseRef:        repo.GetDefaultBranch(),
			NeedsNewBranch: false,
			Features:       features,
		}
	}

	// Default: create a new branch
	features.Branch = &jobs.BranchFeature{
		BaseRef: repo.GetDefaultBranch(),
	}
	return BranchConfig{
		BaseRef:        repo.GetDefaultBranch(),
		NeedsNewBranch: true,
		Features:       features,
	}
}

// GetMostRecentJob returns the most recent job from a list of jobs based on CreatedAt.
// Returns nil if the job list is empty.
func GetMostRecentJob(allJobs []*jobs.Job) *jobs.Job {
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
