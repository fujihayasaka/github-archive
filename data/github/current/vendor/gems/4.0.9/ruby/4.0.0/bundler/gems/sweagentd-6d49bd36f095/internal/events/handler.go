package events

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

type EventsHandler interface {
	OnPullRequestCommentCreated(ctx context.Context, event PullRequestCommentCreatedEvent) error
	OnPullRequestReviewSubmit(ctx context.Context, event PullRequestReviewSubmitEvent) error
	OnPullRequestStateChanged(ctx context.Context, event PullRequestStateChangedEvent) error
	OnPullRequestOpened(ctx context.Context, event PullRequestOpenedEvent) error
	OnPullRequestSynchronize(ctx context.Context, event PullRequestSynchronizeEvent) error
	OnWorkflowRunCompleted(ctx context.Context, event WorkflowRunCompletedEvent) error
	OnWorkflowRunFailed(ctx context.Context, event WorkflowRunCompletedEvent) error
	OnCodeScanningAlertsAssigned(ctx context.Context, event CodeScanningAlertsAssignmentEvent) error
	OnIssueCreated(ctx context.Context, event IssueCreatedEvent) error
	OnMergeConflict(ctx context.Context, event MergeConflictEvent) error
	OnAutomationRunRequested(ctx context.Context, event AutomationRunRequestedEvent) error
	Process(ctx context.Context, event sweagentd.Event) error
	HasAssignmentForPR(ctx context.Context, ownerID, repoID int64, pr *PullRequest) (bool, error)
}

var (
	_ EventsHandler = &Handler{}
	_ EventsHandler = &NoopHandler{}
)

// jobService defines the methods from the jobservice package that are used by
// the handler.
//
// This interface is currently a placeholder. As we continue to migrate to the
// jobservice package, this interface will shrink to only one or two methods
// specifically required by the handler.
//
// Most methods in this interface today are temporary to facilitate the migration
type jobService interface {
	QueueJobForExecution(ctx context.Context, job *jobs.Job) (*aqueductJobs.AgentJob, error)
	GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error)
	FinalizeJob(ctx context.Context, job *jobs.Job, jobStatus jobs.JobStatus, jobError *jobs.JobError, completedAt int64) error
	NewJobBuilder(action jobs.AgentAction, repo *gg.Repository, baseCommit string) *jobservice.JobBuilder
	JobBuilderForJob(assignment *jobs.Assignment, job *jobs.Job, repo *gg.Repository) *jobservice.JobBuilderWithAssignmentAndActor
	GetSessionClient(ctx context.Context, agentID int64, ids sweagentd.RepositoryWithActor) (capi.SessionClient, error)
	GetSessionForJob(ctx context.Context, job *jobs.Job) (*capi.Session, error)
	UpdateSession(ctx context.Context, job *jobs.Job, update capi.SessionUpdate) error
	CheckRules(ctx context.Context, gh jobservice.BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string, checkAgentPrefixExists bool) *jobservice.CheckRulesResult
}

type jobstore interface {
	GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error)
	GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error)
	GetLatestAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error)
	GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error)
	DetachAssignmentResource(ctx context.Context, assignment *jobs.Assignment, resource jobs.AssignmentResource) error
	DetachAssignmentResources(ctx context.Context, assignment *jobs.Assignment) error

	GetJobForComputeID(ctx context.Context, owner, repo int64, computeID string) (*jobs.Job, error)
	UpsertJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error)
	CountJobsForBranchAndEventType(ctx context.Context, owner, repo int64, branch string, eventType jobs.EventType) (int, error)

	CreateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) // used in tests only
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)                 // used in tests only
	CreateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error)                             // used in tests only
}

type Handler struct {
	obsv             observability.Exporters
	ffClient         featureflags.Client
	jobService       jobService
	jobsStore        jobstore
	jobExecutor      jobexecutor.JobExecutor
	ghTwirp          githubtwirp.ClientInterface
	capiClient       capi.Client
	ghFactory        github.ClientFactoryInterface
	appProvider      *agenticapp.Provider
	customAgents     *customagent.Service
	automationLookup automations.Lookup
}

func NewHandler(
	obsv observability.Exporters,
	capiClient capi.Client,
	ffClient featureflags.Client,
	jobService jobService,
	jobExecutor jobexecutor.JobExecutor,
	jobsStore jobstore,
	ghTwirp githubtwirp.ClientInterface,
	ghFactory github.ClientFactoryInterface,
	appProvider *agenticapp.Provider,
	customAgents *customagent.Service,
	automationLookup automations.Lookup,
) *Handler {
	return &Handler{
		obsv:             obsv,
		ffClient:         ffClient,
		jobsStore:        jobsStore,
		jobService:       jobService,
		jobExecutor:      jobExecutor,
		ghTwirp:          ghTwirp,
		capiClient:       capiClient,
		ghFactory:        ghFactory,
		appProvider:      appProvider,
		customAgents:     customAgents,
		automationLookup: automationLookup,
	}
}

func (h *Handler) Process(ctx context.Context, event sweagentd.Event) error {
	start := time.Now()
	eventType := eventTypeName(event)

	err := processEvent(ctx, h, event)

	outcome := "success"
	if err != nil {
		if github.IsNodeNotFound(err) {
			outcome = "skipped"
		} else if jobutils.IsExpectedError(err) {
			outcome = "expected"
		} else {
			outcome = "error"
		}
	}
	tags := stats.Tags{"event_type": eventType, "outcome": outcome}
	if outcome == "error" {
		tags["error_class"] = classifyError(err)
	}
	h.obsv.DistributionMs(ctx, "events.handler_duration_ms", tags, time.Since(start))

	if err != nil {
		// If the error is due to an unresolvable node ID (e.g., the repository
		// or pull request was deleted or transferred), skip processing and log
		// a warning. These are expected conditions that should not be counted
		// as handler failures.
		if github.IsNodeNotFound(err) {
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("skipping event: node ID could not be resolved, resource may have been deleted or transferred")
			h.obsv.Increment(ctx, "events.node_not_found_skipped", stats.Tags{"event_type": eventType})
			return nil
		}

		// Get the agent from the event
		agentID := event.GetAgentID()
		agent, findErr := h.appProvider.FindByID(ctx, agentID)
		if findErr != nil {
			return fmt.Errorf("failed to find agentic app by ID: %w", findErr)
		}
		return jobutils.HandleErrorByType(ctx, h.obsv, h.ghFactory, agent, err)
	}
	return nil
}

// validateRules verifies that repository rules (rulesets and classic branch protection)
// won't block the agent from pushing to the PR's head branch. Returns an error suitable for
// posting a user-visible PR comment if rules are violated, or nil if the check passes or is
// disabled by feature flag.
func (h *Handler) validateRules(
	ctx context.Context,
	gh github.ClientInterface,
	app sweagentd.AgenticApp,
	assignment *jobs.Assignment,
	actor *Actor,
	repo github.GQLRepository,
	pr *github.GQLPullRequest,
) error {
	if !h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentPRCommentRulesCheck, actor.ID, repo.ID) {
		return nil
	}

	owner := repo.Owner

	// On first trigger, no assignment exists yet so we construct a minimal one
	// for posting the error comment to the PR.
	if assignment == nil {
		assignment = &jobs.Assignment{
			RepoID:            repo.ID,
			OwnerID:           owner.GetID(),
			PullRequestNumber: pr.Number,
		}
	}

	// Block the agent from pushing directly to the default branch.
	if h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentBlockDefaultBranch, actor.ID, repo.ID) {
		if defaultBranch := repo.GetDefaultBranch(); defaultBranch != "" && pr.HeadRef.Name == defaultBranch {
			h.obsv.Statter.Counter("hydro.default_branch_push", h.obsv.TelemetryTags(ctx), 1)
			h.obsv.LoggerWithTelemetry(ctx).Warn("agent cannot push to the default branch",
				kvp.Int64("repo_id", repo.ID),
				kvp.Int64("owner_id", owner.GetID()),
			)

			defaultBranchErr := fmt.Errorf("head branch %q is the default branch", pr.HeadRef.Name)
			return jobutils.NewDefaultBranchErrorWithPRComment(ctx, defaultBranchErr, assignment, actor.Login)
		}
	}

	rulesResult := h.jobService.CheckRules(ctx, gh, app, &jobs.Job{
		ActorID:    actor.ID,
		OwnerID:    owner.GetID(),
		RepoID:     repo.ID,
		RepoNodeID: repo.NodeID,
		AgentID:    app.AppID(),
		BranchName: pr.HeadRef.Name,
	}, owner.Login, repo.Name, pr.HeadRef.Name, false)

	if len(rulesResult.Rules) == 0 {
		return nil
	}

	rulesErr := &jobservice.RulesViolationError{CheckRulesResult: rulesResult}
	h.obsv.Statter.Counter("hydro.rules_violation", h.obsv.TelemetryTags(ctx), 1)
	h.obsv.LoggerWithTelemetry(ctx).WithError(rulesErr).Warn("repository rules prevent agent from working on current branch",
		kvp.Int64("repo_id", repo.ID),
		kvp.Int64("owner_id", owner.GetID()),
	)

	return jobutils.NewRulesViolationErrorWithPRComment(ctx, rulesErr, assignment, actor.Login, rulesResult)
}

// eventTypeName returns a snake_case name for the event type for use in metrics.
func eventTypeName(event any) string {
	switch e := event.(type) {
	case *PullRequestCommentCreatedEvent:
		return "pull_request_comment_created"
	case *PullRequestReviewSubmitEvent:
		return "pull_request_review_submit"
	case *PullRequestStateChangedEvent:
		return "pull_request_state_changed"
	case *WorkflowRunCompletedEvent:
		if !e.IsAgentCompletion() {
			return "workflow_run_failed_trigger"
		}
		return "workflow_run_completed"
	case *CodeScanningAlertsAssignmentEvent:
		return "code_scanning_alerts_assignment"
	case *IssueCreatedEvent:
		return "issue_created"
	case *PullRequestOpenedEvent:
		return "pull_request_opened"
	case *MergeConflictEvent:
		return "merge_conflict"
	case *AutomationRunRequestedEvent:
		return "automation_run_requested"
	default:
		return "unknown"
	}
}

func processEvent(ctx context.Context, h EventsHandler, event any) error {
	switch v := event.(type) {
	case *PullRequestCommentCreatedEvent:
		return h.OnPullRequestCommentCreated(ctx, *v)

	case *PullRequestReviewSubmitEvent:
		return h.OnPullRequestReviewSubmit(ctx, *v)

	case *PullRequestStateChangedEvent:
		return h.OnPullRequestStateChanged(ctx, *v)

	case *WorkflowRunCompletedEvent:
		if v.IsAgentCompletion() {
			return h.OnWorkflowRunCompleted(ctx, *v)
		}
		return h.OnWorkflowRunFailed(ctx, *v)

	case *CodeScanningAlertsAssignmentEvent:
		return h.OnCodeScanningAlertsAssigned(ctx, *v)

	case *IssueCreatedEvent:
		return h.OnIssueCreated(ctx, *v)

	case *PullRequestOpenedEvent:
		return h.OnPullRequestOpened(ctx, *v)

	case *PullRequestSynchronizeEvent:
		return h.OnPullRequestSynchronize(ctx, *v)

	case *MergeConflictEvent:
		return h.OnMergeConflict(ctx, *v)

	case *AutomationRunRequestedEvent:
		return h.OnAutomationRunRequested(ctx, *v)

	default:
		return fmt.Errorf("unknown event type %T", v)
	}
}

func (h *Handler) assignmentForPR(ctx context.Context, repo sweagentd.Repository, prID *int64, prNumber *int) (*jobs.Assignment, error) {
	if prID != nil {
		assignment, err := h.getAssignmentForPRDirect(ctx, repo, prID, prNumber)
		if err != nil {
			return nil, fmt.Errorf("failed to get assignment for pull request: %w", err)
		}
		return assignment, nil
	}

	// Legacy lookup by PR ID/number fields
	// This handles assignments created before the Resources field was populated
	if h.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentGetLatestAssignment, repo) {
		assignment, err := h.jobsStore.GetLatestAssignmentForPR(ctx, repo.GetOwnerID(), repo.GetRepositoryID(), prID, prNumber)
		if err != nil {
			return nil, fmt.Errorf("failed to get latest assignment: %w", err)
		}
		return assignment, nil
	}

	assignment, err := h.jobsStore.GetAssignmentForPR(ctx, repo.GetOwnerID(), repo.GetRepositoryID(), prID, prNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to get assignment: %w", err)
	}

	return assignment, nil
}

// getAssignmentForPRDirect looks up an assignment by PR ID/number, using GetLatestAssignmentForPR
// when the CopilotSWEAgentGetLatestAssignment feature flag is enabled.
func (h *Handler) getAssignmentForPRDirect(ctx context.Context, repo sweagentd.Repository, prID *int64, prNumber *int) (*jobs.Assignment, error) {
	if h.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentGetLatestAssignment, repo) {
		return h.jobsStore.GetLatestAssignmentForPR(ctx, repo.GetOwnerID(), repo.GetRepositoryID(), prID, prNumber)
	}
	return h.jobsStore.GetAssignmentForPR(ctx, repo.GetOwnerID(), repo.GetRepositoryID(), prID, prNumber)
}

// HasAssignmentForPR checks if a pull request has an existing agent assignment.
func (h *Handler) HasAssignmentForPR(ctx context.Context, ownerID, repoID int64, pr *PullRequest) (bool, error) {
	if pr == nil {
		return false, nil
	}
	repo := &sweagentd.RepositoryAdapter{RepoID: repoID, OwnerID: ownerID}
	assignment, err := h.getAssignmentForPRDirect(ctx, repo, &pr.ID, &pr.Number)
	if err != nil {
		return false, err
	}
	return assignment != nil, nil
}

// getMostRecentJobWithAgent returns the most recent job with the specified agent ID from a
// list of jobs based on CreatedAt. Returns nil if no job matches the agent ID.
func getMostRecentJobWithAgent(allJobs []*jobs.Job, agentID int64) *jobs.Job {
	var mostRecent *jobs.Job

	for _, job := range allJobs {
		if job.AgentID != agentID {
			continue
		}

		if mostRecent == nil || job.CreatedAt > mostRecent.CreatedAt {
			mostRecent = job
		}
	}

	return mostRecent
}
