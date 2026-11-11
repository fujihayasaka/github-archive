package events

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

const mergeConflictAgentName = "merge-conflict-resolver"

// OnMergeConflict is called to handle a MergeConflictEvent associated with
// a merge conflict detected on a pull request.
func (h *Handler) OnMergeConflict(ctx context.Context, event MergeConflictEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.OnMergeConflict")
	defer span.End()

	metricTags := stats.Tags{}

	h.obsv.LoggerWithTelemetry(ctx).Info("Processing OnMergeConflict event")
	h.obsv.Increment(ctx, "merge_conflict.received", metricTags)

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID from merge conflict event: %w", err)
	}

	gh, err := h.ghFactory.NewClientFromRepo(ctx, app, event.Repo.ID, event.Repo.OwnerID)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	ggRepo, err := gh.GetRepositoryByID(ctx, event.Repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	// The MergeConflict proto only provides repository_id, not the owner ID.
	// Resolve the owner ID from the GitHub API response for downstream use.
	repoOwnerID := ggRepo.GetOwner().GetID()
	if repoOwnerID == 0 {
		return goerrors.Errorf("repository %d has no owner ID, cannot proceed", event.Repo.ID)
	}

	ownerLogin := ggRepo.GetOwner().GetLogin()
	repoName := ggRepo.GetName()

	agent := mergeConflictAgent(event.Repo.ID, repoOwnerID, ownerLogin, repoName)

	h.obsv.LoggerWithTelemetry(ctx).Info("Building and queuing job for merge conflict event")

	err = h.buildJobForMergeConflict(ctx, gh, app, agent, event, ggRepo, repoOwnerID)
	if err == nil {
		h.obsv.LoggerWithTelemetry(ctx).Info("successfully built and queued job for OnMergeConflict event")
		h.obsv.Increment(ctx, "merge_conflict.job_queued", metricTags)
		h.obsv.Increment(ctx, "merge_conflict.handled", metricTags)
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to build or queue job for OnMergeConflict event")
	h.obsv.Increment(ctx, "merge_conflict.job_error", metricTags)

	switch {
	case jobservice.IsBuilderFinalizedJobError(err):
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Info("job builder finalized error encountered")
		return nil
	case limiter.IsAnyLimiterError(err):
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Info("rate limit error encountered, stopping processing of OnMergeConflict event to retry later")
		return err
	default:
		h.obsv.LogAndReportError(ctx, err, "unexpected error building or queuing job for OnMergeConflict event")
		return nil
	}
}

func (h *Handler) buildJobForMergeConflict(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, agent sweagentd.CustomAgent, event MergeConflictEvent, ggRepo *gg.Repository, repoOwnerID int64) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.buildJobForMergeConflict")
	defer span.End()

	ownerLogin := ggRepo.GetOwner().GetLogin()
	repoName := ggRepo.GetName()

	// Find the pull request associated with the head commit SHA.
	// The MergeConflict event provides the PR database ID but not the number,
	// so we look up PRs by the head commit and match by ID.
	pr, err := h.findPullRequestForMergeConflict(ctx, gh, ownerLogin, repoName, event)
	if err != nil {
		return goerrors.Errorf("failed to find pull request for merge conflict: %w", err)
	}

	prAuthor := pr.GetUser()
	jobActor, err := h.getJobActorFromGitHubUser(ctx, prAuthor)
	if err != nil {
		return goerrors.Errorf("failed to get job actor: %w", err)
	}

	headBranch := pr.GetHead().GetRef()
	if headBranch == "" {
		return goerrors.New("pull request has no head branch, cannot determine target branch for conflict resolution")
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, event.Repo.ID)

	ownerNodeID := ggRepo.GetOwner().GetNodeID()
	repoNodeID := ggRepo.GetNodeID()

	builder := h.jobService.NewJobBuilder(jobs.AgentActionTask, ggRepo, headBranch).
		WithNewAssignment(repoOwnerID, event.Repo.ID, ownerNodeID, repoNodeID, ownerLogin, repoName, useAsyncSessions, mergeConflictResource(event.PullRequestID)).
		WithJobActor(*jobActor).
		WithTrigger().
		WithCustomAgent(agent).
		WithAgentID(app.AppID()).
		WithRequestStartedAt(event.Timestamp).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return mergeConflictProblemStatement(pr, event)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypeMergeConflict,
			Identifiers: eventIdentifiers(event.PullRequestID),
		}).
		WithNewSession().
		WithAINameGen()

	_, job, err := builder.Build(ctx, gh)
	if err != nil {
		return goerrors.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("queuing successfully built job for merge conflict event")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return goerrors.Errorf("failed to queue job: %w", err)
	}

	return nil
}

// mergeConflictResource creates an assignment resource for a merge conflict pull request.
func mergeConflictResource(prID int64) jobs.AssignmentResource {
	return jobs.AssignmentResource{
		Type: "merge_conflict",
		ID:   strconv.FormatInt(prID, 10),
	}
}

func mergeConflictAgent(repoID, repoOwnerID int64, ownerLogin, repoName string) sweagentd.CustomAgent {
	metadata := customagent.Metadata{
		Name:        mergeConflictAgentName,
		RepoID:      repoID,
		RepoOwnerID: repoOwnerID,
		RepoOwner:   ownerLogin,
		RepoName:    repoName,
		Scope:       agentconfig.ScopeRepository,
	}

	attrs := customagent.ConfigAttributes{
		DisplayName: "Merge Conflict Resolver",
		Description: "Resolves merge conflicts on pull requests",
		Tools:       []string{"*"},
	}

	return customagent.NewWithConfig(metadata, customagent.NewConfigWithAttributes(attrs))
}

func mergeConflictProblemStatement(pr *gg.PullRequest, event MergeConflictEvent) (jobs.ProblemStatement, error) {
	var sb strings.Builder
	fmt.Fprintf(&sb, "A merge conflict has been detected on pull request #%d in the %s repository.\n\n", pr.GetNumber(), pr.GetBase().GetRepo().GetFullName())
	fmt.Fprintf(&sb, "Pull Request: %s\n", pr.GetHTMLURL())
	fmt.Fprintf(&sb, "Base branch: %s\n", pr.GetBase().GetRef())
	fmt.Fprintf(&sb, "Head branch: %s\n\n", pr.GetHead().GetRef())

	if len(event.ConflictPaths) > 0 {
		fmt.Fprintf(&sb, "Conflicting files:\n")
		for _, path := range event.ConflictPaths {
			fmt.Fprintf(&sb, "- %s\n", path)
		}
		sb.WriteString("\n")
	}

	fmt.Fprintf(&sb, "Please resolve the merge conflicts in the head branch so that the pull request can be merged cleanly into the base branch. You can use the GitHub MCP server to access more details about the pull request.\n")

	return jobs.ProblemStatement{
		Content: sb.String(),
	}, nil
}

// findPullRequestForMergeConflict locates the pull request associated with a
// merge conflict event. It queries PRs by the head commit SHA and matches by
// database ID.
func (h *Handler) findPullRequestForMergeConflict(ctx context.Context, gh github.ClientInterface, owner, repo string, event MergeConflictEvent) (*gg.PullRequest, error) {
	prs, err := gh.ListPullRequestsWithCommit(ctx, owner, repo, event.HeadCommitOID)
	if err != nil {
		return nil, goerrors.Errorf("failed to list pull requests with commit %s: %w", event.HeadCommitOID, err)
	}

	for _, pr := range prs {
		if pr.GetID() == event.PullRequestID {
			return pr, nil
		}
	}

	return nil, goerrors.Errorf("pull request with ID %d not found for commit %s", event.PullRequestID, event.HeadCommitOID)
}
