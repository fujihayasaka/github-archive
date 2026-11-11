package events

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// maxTriggeredJobsPerBranch is the maximum number of workflow_run failed
// triggered jobs allowed per branch. After this many attempts, the agent
// stops retrying and the branch requires manual intervention.
const maxTriggeredJobsPerBranch = 3

// OnWorkflowRunFailed is called to handle a WorkflowRunCompletedEvent for
// non-agent workflow runs that have failed, associated with custom agent
// workflow_run triggers.
func (h *Handler) OnWorkflowRunFailed(ctx context.Context, event WorkflowRunCompletedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.OnWorkflowRunFailed")
	defer span.End()

	triggerTags := stats.Tags{"trigger_type": "workflow_run_failed"}

	h.obsv.LoggerWithTelemetry(ctx).Info("Processing OnWorkflowRunFailed event")
	h.obsv.Increment(ctx, "triggers.received", triggerTags)

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID from workflow run failed event: %w", err)
	}

	if h.automationLookup == nil {
		h.obsv.LoggerWithTelemetry(ctx).Info("Automation lookup not available, skipping OnWorkflowRunFailed event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_trigger_checker"}))
		return nil
	}

	gh, err := h.ghFactory.NewClientFromRepo(ctx, app, event.Repo.ID, event.Repo.OwnerID)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	ggRepo, err := gh.GetRepositoryByID(ctx, event.Repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}
	if ggRepo.GetVisibility() == "public" && featureflags.ShouldSkipPublicRepoAutomations(ctx, h.ffClient, event.Repo) {
		h.obsv.LoggerWithTelemetry(ctx).Info("skipping workflow_run_failed trigger for public repository")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "public_repository"}))
		return nil
	}

	ownerLogin := ggRepo.GetOwner().GetLogin()
	repoName := ggRepo.GetName()

	// Get the workflow run from the GitHub API to obtain the display name
	// (the `name:` field from the workflow YAML), which is what users
	// configure in their agent's `workflows` list — consistent with
	// GitHub Actions workflow_run trigger semantics.
	run, err := gh.GetWorkflowRunByID(ctx, ownerLogin, repoName, event.WorkflowRun.ID)
	if err != nil {
		return goerrors.Errorf("failed to get workflow run from GitHub: %w", err)
	}

	workflowName := run.GetName()

	runtimeConfigs, err := h.automationLookup.ListForEvent(ctx, automations.ListForEventRequest{
		Event: automations.EventMatchRequest{
			OwnerID:            event.Repo.OwnerID,
			RepoID:             event.Repo.ID,
			EventName:          automations.EventWorkflowRun,
			ActivityType:       automations.ActivityWorkflowRunFailed,
			WorkflowName:       workflowName,
			WorkflowConclusion: automations.WorkflowConclusion(run.GetConclusion()),
		},
		Repo: automations.RepoInfo{
			OwnerLogin: ownerLogin,
			RepoName:   repoName,
		},
		AutomationID: event.AutomationID,
	})
	if err != nil {
		return goerrors.Errorf("failed to get automations with matching triggers: %w", err)
	}

	if len(runtimeConfigs) == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("No custom agents with matching workflow run triggers found for repository, skipping OnWorkflowRunFailed event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_matching_agents"}))
		return nil
	}

	actorLogin := run.GetTriggeringActor().GetLogin()

	actorCtx, err := h.resolveActorPermissionContext(ctx, gh, event.Repo, actorLogin, runtimeConfigs)
	if err != nil {
		return goerrors.Errorf("failed to check workflow triggering actor permissions: %w", err)
	}

	runtimeConfigs = h.filterConfigsByActorPermissions(ctx, triggerTags, actorCtx, runtimeConfigs)
	if len(runtimeConfigs) == 0 {
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Int("triggers.matching_agents", len(runtimeConfigs))).
		Info("Found custom agents with matching triggers for OnWorkflowRunFailed event")

	err = h.dispatchTriggerJobs(ctx, "OnWorkflowRunFailed", triggerTags, runtimeConfigs, func(runtimeConfig automations.RuntimeConfig) (bool, error) {
		return h.buildJobForWorkflowRunFailed(ctx, gh, app, runtimeConfig, triggerTags, event, ggRepo, run)
	})
	if err != nil {
		return err
	}

	h.obsv.Increment(ctx, "triggers.handled", triggerTags)
	return nil
}

func (h *Handler) buildJobForWorkflowRunFailed(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, runtimeConfig automations.RuntimeConfig, triggerTags stats.Tags, event WorkflowRunCompletedEvent, ggRepo *gg.Repository, run *gg.WorkflowRun) (bool, error) {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.buildJobForWorkflowRunFailed")
	defer span.End()

	ownerLogin := ggRepo.GetOwner().GetLogin()
	repoName := ggRepo.GetName()
	agent := runtimeConfig.CustomAgent

	jobActor, ok, err := h.jobActorForRuntimeConfig(ctx, gh, event.Repo, runtimeConfig, triggerTags)
	if err != nil {
		return false, goerrors.Errorf("failed to check automation owner permissions: %w", err)
	}
	if !ok {
		return false, nil
	}

	// The agent pushes fixes directly to the branch where the workflow failed,
	// rather than creating a new branch and PR.
	headBranch := run.GetHeadBranch()
	if headBranch == "" {
		return false, goerrors.New("workflow run has no head branch, cannot determine target branch for fix")
	}

	// Normalize qualified refs and block the default branch to prevent the
	// agent from committing directly to it.
	headBranch = strings.TrimPrefix(headBranch, "refs/heads/")
	if headBranch == ggRepo.GetDefaultBranch() {
		return false, goerrors.Errorf("workflow run head branch %q is the default branch, skipping to prevent direct commits", headBranch)
	}

	// Cap retries to prevent infinite loops: agent pushes fix → CI fails → trigger
	// fires again. If we've already created maxTriggeredJobsPerBranch jobs for this
	// branch, skip creating another.
	var maxRetriesEnabled bool
	var existingJobCount int
	if h.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentMaxTriggerRetries, event.Repo) {
		maxRetriesEnabled = true
		count, err := h.jobsStore.CountJobsForBranchAndEventType(ctx, event.Repo.OwnerID, event.Repo.ID, headBranch, jobs.EventTypeWorkflowRunFailed)
		if err != nil {
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to count existing triggered jobs for branch, proceeding with job creation")
		} else {
			existingJobCount = count
		}
	}

	if maxRetriesEnabled && existingJobCount >= maxTriggeredJobsPerBranch {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.Int("triggers.existing_job_count", existingJobCount),
			kvp.Int("triggers.max_retries", maxTriggeredJobsPerBranch),
			kvp.String("triggers.branch", headBranch),
		).Info("max triggered job retries reached for branch, skipping job creation")
		h.obsv.Increment(ctx, "triggers.skipped", stats.Tags{"trigger_type": "workflow_run_failed", "reason": "max_retries_reached"})
		return false, nil
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, event.Repo.ID)

	ownerNodeID := ggRepo.GetOwner().GetNodeID()
	repoNodeID := ggRepo.GetNodeID()

	// Check for an existing PR associated with this workflow run so we can
	// link the assignment to it instead of treating this as a standalone branch job.
	// Match on Head.Ref to avoid linking the wrong PR when the run is associated
	// with multiple PRs (e.g. the same commit appears in more than one open PR).
	var associatedPR *gg.PullRequest
	for _, pr := range run.PullRequests {
		if pr.GetHead().GetRef() == headBranch {
			associatedPR = pr
			break
		}
	}
	if associatedPR != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.Int("pr_number", associatedPR.GetNumber()),
			kvp.Int64("pr_id", associatedPR.GetID()),
		).Info("found associated PR for workflow run, linking assignment to existing PR")
	}

	resources := []jobs.AssignmentResource{workflowRunResource(event.WorkflowRun.ID)}
	if associatedPR != nil {
		resources = append(resources, pullRequestResource(associatedPR.GetID()))
	}

	action := jobs.AgentActionTask
	if associatedPR != nil {
		// Existing PR-linked runs use the fix-pr-comment action. Downstream PR update
		// skip logic keys off job.Action
		action = jobs.AgentActionFixPRComment
	}
	assignmentBuilder := h.jobService.NewJobBuilder(action, ggRepo, headBranch).
		WithNewAssignment(event.Repo.OwnerID, event.Repo.ID, ownerNodeID, repoNodeID, ownerLogin, repoName, useAsyncSessions, resources...)

	if associatedPR != nil {
		assignmentBuilder = assignmentBuilder.WithAssignmentPullRequest(associatedPR.GetID(), associatedPR.GetNumber())
	}

	builder := assignmentBuilder.
		WithJobActor(*jobActor).
		WithTrigger().
		WithAutomationID(runtimeConfig.AutomationID).
		WithCustomAgent(agent).
		WithAgentID(app.AppID()).
		WithJobInitHook(func(j *jobs.Job) {
			j.BranchName = headBranch
		}).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return workflowRunFailedProblemStatement(run)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypeWorkflowRunFailed,
			Identifiers: eventIdentifiers(event.WorkflowRun.ID),
		}).
		WithNewSession().
		WithAINameGen()

	// When linked to a pre-existing PR, populate Features.PullRequest.HeadRef
	// so downstream code can identify the branch associated with the PR.
	if associatedPR != nil {
		builder = builder.WithFeatures(jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				HeadRef: headBranch,
			},
		})
	}

	_, job, err := builder.Build(ctx, gh)
	if err != nil {
		return false, goerrors.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("successfully built job for workflow run failed event")

	h.obsv.LoggerWithTelemetry(ctx).Info("queuing job for execution")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return false, goerrors.Errorf("failed to queue job: %w", err)
	}

	return true, nil
}

// getJobActorFromGitHubUser creates a JobActor from a GitHub API user object.
func (h *Handler) getJobActorFromGitHubUser(ctx context.Context, user *gg.User) (*jobs.JobActor, error) {
	if user == nil {
		return nil, goerrors.New("triggering actor is nil")
	}

	jobActor := &jobs.JobActor{
		ID:    user.GetID(),
		Login: user.GetLogin(),
	}

	return h.fillJobActorDetails(ctx, jobActor)
}

// workflowRunResource creates an assignment resource for a workflow run.
func workflowRunResource(id int64) jobs.AssignmentResource {
	return jobs.AssignmentResource{
		Type: "workflow_run",
		ID:   strconv.FormatInt(id, 10),
	}
}

func workflowRunFailedProblemStatement(run *gg.WorkflowRun) (jobs.ProblemStatement, error) {
	var sb strings.Builder
	fmt.Fprintf(&sb, "A workflow run has failed in the %s repository.\n\n", run.GetRepository().GetFullName())
	fmt.Fprintf(&sb, "Workflow: %s\n", run.GetName())
	fmt.Fprintf(&sb, "Run URL: %s\n", run.GetHTMLURL())
	fmt.Fprintf(&sb, "Run number: %d\n", run.GetRunNumber())
	fmt.Fprintf(&sb, "Conclusion: %s\n\n", run.GetConclusion())
	fmt.Fprintf(&sb, "Please analyze the failure and suggest fixes. You can use the GitHub MCP server to access the workflow run logs and other details.\n")

	return jobs.ProblemStatement{
		Content: sb.String(),
	}, nil
}
