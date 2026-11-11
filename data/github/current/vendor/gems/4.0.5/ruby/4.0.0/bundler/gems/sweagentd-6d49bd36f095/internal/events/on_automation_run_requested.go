package events

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
	"strings"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/sweagentd"
)

// OnAutomationRunRequested handles an automation run request event from
// copilot-mission-control. It constructs the appropriate event struct and
// delegates to OnIssueCreated or OnWorkflowRunFailed, which fetch the
// automation config from CMC and handle auth, prompt building, and job creation.
func (h *Handler) OnAutomationRunRequested(ctx context.Context, event AutomationRunRequestedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.OnAutomationRunRequested")
	defer span.End()

	triggerTags := stats.Tags{"trigger_type": "automation_run_requested"}

	if event.AutomationID == "" {
		return goerrors.Errorf("automation run requested with empty automation ID")
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("processing automation run request event")
	h.obsv.Increment(ctx, "triggers.received", triggerTags)

	switch event.Event {
	case string(automations.EventIssues):
		return h.runRequestedIssue(ctx, event)
	case string(automations.EventWorkflowRun):
		return h.runRequestedWorkflowRun(ctx, event)
	case string(automations.EventInterval):
		return h.runRequestedInterval(ctx, event)
	case string(automations.EventPullRequest),
		string(automations.EventPullRequestOpened),
		string(automations.EventPullRequestSynchronize),
		string(automations.EventPullRequestMerged):
		return h.runRequestedPullRequest(ctx, event)
	case string(automations.EventManual):
		return h.runRequestedManual(ctx, event)
	default:
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "unsupported_event_type"}))
		return goerrors.Errorf("unsupported automation run request event type: %s", event.Event)
	}
}

// runRequestedIssue constructs an IssueCreatedEvent with the automation ID set
// and delegates to OnIssueCreated which handles the full flow including
// fetching the automation config from CMC.
func (h *Handler) runRequestedIssue(ctx context.Context, event AutomationRunRequestedEvent) error {
	issueNumber, err := parseIssueNumberFromURL(event.ResourceURL)
	if err != nil {
		return goerrors.Errorf("failed to parse issue number from resource URL: %w", err)
	}

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID for automation run request: %w", err)
	}

	issueEvent := IssueCreatedEvent{
		Actor: &Actor{
			ID:    event.UserID,
			Login: event.UserLogin,
		},
		Repo: &Repository{
			ID:      event.RepoID,
			OwnerID: event.OwnerID,
			Name:    event.RepoName,
		},
		Owner: &Actor{
			ID:    event.OwnerID,
			Login: event.OwnerLogin,
		},
		Issue: &Issue{
			Number: issueNumber,
		},
		AgentID:      app.AppID(),
		Timestamp:    event.Timestamp,
		AutomationID: event.AutomationID,
	}

	return h.OnIssueCreated(ctx, issueEvent)
}

// runRequestedWorkflowRun constructs a WorkflowRunCompletedEvent with the
// automation ID set and delegates to OnWorkflowRunFailed which handles
// the full flow including fetching the automation config from CMC.
func (h *Handler) runRequestedWorkflowRun(ctx context.Context, event AutomationRunRequestedEvent) error {
	runID, err := parseWorkflowRunIDFromURL(event.ResourceURL)
	if err != nil {
		return goerrors.Errorf("failed to parse workflow run ID from resource URL: %w", err)
	}

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID for automation run request: %w", err)
	}

	workflowRunEvent := WorkflowRunCompletedEvent{
		Repo: &WorkflowRepository{
			ID:      event.RepoID,
			OwnerID: event.OwnerID,
		},
		WorkflowRun: &WorkflowRun{
			ID:         runID,
			UserID:     event.UserID,
			Status:     event.Type,
			Conclusion: event.Conclusion,
		},
		Timestamp: event.Timestamp,
		AgentID:   app.AppID(),
		// TODO: Kind is hardcoded to WorkflowRunKindFailedTrigger even though the
		// conclusion is dynamic. When we support additional conclusions (e.g.
		// "success"), introduce a distinct Kind to avoid misleading metrics/routing.
		Kind:         WorkflowRunKindFailedTrigger,
		AutomationID: event.AutomationID,
	}

	return h.OnWorkflowRunFailed(ctx, workflowRunEvent)
}

// runRequestedInterval handles a run request for an interval/schedule automation.
// Unlike issues and workflow_run, there is no existing On* handler for intervals
// in the events package — the scheduler executor handles them. This method
// mirrors the executeCMC path: fetches the automation config via ListForEvent,
// then builds and queues the job.
//
// TODO: Consolidate with scheduler/executor.executeCMC to share interval
// job-building logic and avoid drift between the two paths.
func (h *Handler) runRequestedInterval(ctx context.Context, event AutomationRunRequestedEvent) error {
	return h.runRequestedGeneric(ctx, event, genericRunParams{
		triggerType:         "interval",
		eventName:           automations.EventInterval,
		jobEventType:        jobs.EventTypeIntervalTriggered,
		problemStatementFmt: "Requested run of scheduled automation %q in %s/%s",
	})
}

// runRequestedManual handles a manual automation run with no event context.
// It fetches the automation config from CMC by ID, builds a problem statement
// from the agent name and repository, and queues a job against the repo's
// default branch.
func (h *Handler) runRequestedManual(ctx context.Context, event AutomationRunRequestedEvent) error {
	return h.runRequestedGeneric(ctx, event, genericRunParams{
		triggerType:         "manual",
		eventName:           automations.EventManual,
		jobEventType:        jobs.EventTypeManualTriggered,
		problemStatementFmt: "Manual run of automation %q in %s/%s",
	})
}

// genericRunParams holds the parameters that differ between interval and manual
// run request handling.
type genericRunParams struct {
	triggerType         string
	eventName           automations.EventName
	jobEventType        jobs.EventType
	problemStatementFmt string // format string expecting (agentName, ownerLogin, repoName)
}

// runRequestedGeneric is the shared implementation for interval and manual run
// requests. Both follow the same flow: fetch automation config by ID, resolve
// the job actor, build a job against the repo's default branch, and queue it.
func (h *Handler) runRequestedGeneric(ctx context.Context, event AutomationRunRequestedEvent, params genericRunParams) error {
	triggerTags := stats.Tags{"trigger_type": params.triggerType}

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID for %s automation run request: %w", params.triggerType, err)
	}

	// Fetch the automation config from CMC using the automation ID filter.
	// Trigger matching is skipped when AutomationID is set.
	runtimeConfigs, err := h.automationLookup.ListForEvent(ctx, automations.ListForEventRequest{
		Event: automations.EventMatchRequest{
			OwnerID:   event.OwnerID,
			RepoID:    event.RepoID,
			EventName: params.eventName,
		},
		Repo: automations.RepoInfo{
			OwnerLogin: event.OwnerLogin,
			RepoName:   event.RepoName,
		},
		AutomationID: event.AutomationID,
	})
	if err != nil {
		return goerrors.Errorf("failed to get automation config for %s run request: %w", params.triggerType, err)
	}
	if len(runtimeConfigs) == 0 {
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_matching_agents"}))
		return goerrors.Errorf("automation %s not found or not active", event.AutomationID)
	}

	gh, err := h.ghFactory.NewClientFromRepo(ctx, app, event.RepoID, event.OwnerID)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client for %s run request: %w", params.triggerType, err)
	}

	dispatchLabel := fmt.Sprintf("OnAutomationRunRequested/%s", params.triggerType)
	err = h.dispatchTriggerJobs(ctx, dispatchLabel, triggerTags, runtimeConfigs, func(runtimeConfig automations.RuntimeConfig) (bool, error) {
		return h.buildJobForGenericRun(ctx, gh, app, runtimeConfig, triggerTags, event, params)
	})
	if err != nil {
		return err
	}

	h.obsv.Increment(ctx, "triggers.handled", triggerTags)
	return nil
}

func (h *Handler) buildJobForGenericRun(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, runtimeConfig automations.RuntimeConfig, triggerTags stats.Tags, event AutomationRunRequestedEvent, params genericRunParams) (bool, error) {
	agent := runtimeConfig.CustomAgent
	eventRepo := &Repository{ID: event.RepoID, OwnerID: event.OwnerID}

	jobActor, ok, err := h.jobActorForRuntimeConfig(ctx, gh, eventRepo, runtimeConfig, triggerTags)
	if err != nil {
		return false, goerrors.Errorf("failed to get job actor: %w", err)
	}
	if !ok {
		return false, nil
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, event.RepoID)

	repo, err := gh.GetRepositoryByID(ctx, event.RepoID)
	if err != nil {
		return false, goerrors.Errorf("failed to get repository: %w", err)
	}

	repoOwnerLogin := repo.GetOwner().GetLogin()
	repoName := repo.GetName()

	ps := jobs.ProblemStatement{
		Content:           fmt.Sprintf(params.problemStatementFmt, agent.Name(), repoOwnerLogin, repoName),
		ContentFilterMode: jobs.ProblemStatementContentFilterModeNone,
	}

	resource := jobs.AssignmentResource{
		Type: "automation_run_requested",
		ID:   event.AutomationID,
	}

	_, job, err := h.jobService.NewJobBuilder(jobs.AgentActionTask, repo, repo.GetDefaultBranch()).
		WithNewAssignmentWithCustomAgent(
			event.OwnerID, event.RepoID,
			repo.GetOwner().GetNodeID(), repo.GetNodeID(),
			repoOwnerLogin, repoName,
			useAsyncSessions, agent,
			resource,
		).
		WithJobActor(*jobActor).
		WithTrigger().
		WithAutomationID(runtimeConfig.AutomationID).
		WithCustomAgent(agent).
		WithAgentID(app.AppID()).
		WithEvent(jobservice.Event{
			Type: params.jobEventType,
			URL:  fmt.Sprintf("https://github.com/%s/%s", repoOwnerLogin, repoName),
		}).
		WithProblemStatement(&ps).
		WithRequestStartedAt(event.Timestamp).
		WithFeatures(jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				BaseRef: repo.GetDefaultBranch(),
			},
		}).
		WithNewSession().
		WithAINameGen().
		Build(ctx, gh)
	if err != nil {
		return false, goerrors.Errorf("failed to build job for %s run request: %w", params.triggerType, err)
	}

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return false, goerrors.Errorf("failed to queue job for %s run request: %w", params.triggerType, err)
	}

	return true, nil
}

// runRequestedPullRequest fetches the target PR and dispatches to the handler
// matching event.Event so each PR activity (opened/synchronize/merged) applies
// its own trigger query/paths. AutomationID restricts the lookup to the
// requested automation.
func (h *Handler) runRequestedPullRequest(ctx context.Context, event AutomationRunRequestedEvent) error {
	prNumber, err := parsePullRequestNumberFromURL(event.ResourceURL)
	if err != nil {
		return goerrors.Errorf("failed to parse pull request number from resource URL: %w", err)
	}

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID for automation run request: %w", err)
	}

	// Fetch PR details from GitHub to populate head/base branch info required
	// by the downstream job builder. The organic Hydro event carries these
	// fields, but the ad-hoc path only has the URL.
	repo := &Repository{
		ID:      event.RepoID,
		OwnerID: event.OwnerID,
		Name:    event.RepoName,
	}
	owner := &Actor{
		ID:    event.OwnerID,
		Login: event.OwnerLogin,
	}
	actor := &Actor{
		ID:    event.UserID,
		Login: event.UserLogin,
	}

	gh, err := h.ghFactory.NewClientForRepo(ctx, app, &PullRequestOpenedEvent{Repo: repo, Owner: owner})
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client for pull request fetch: %w", err)
	}

	pr, err := gh.GetPullRequest(ctx, event.RepoID, prNumber)
	if err != nil {
		return goerrors.Errorf("failed to fetch pull request #%d: %w", prNumber, err)
	}

	prInfo := &PullRequest{
		ID:         pr.GetID(),
		Number:     prNumber,
		HeadBranch: pr.GetHead().GetRef(),
		BaseBranch: pr.GetBase().GetRef(),
		IsOpen:     pr.GetState() == "open",
		State:      pr.GetState(),
	}

	switch event.Event {
	case string(automations.EventPullRequestSynchronize):
		return h.OnPullRequestSynchronize(ctx, PullRequestSynchronizeEvent{
			Actor:        actor,
			Repo:         repo,
			PullRequest:  prInfo,
			AgentID:      app.AppID(),
			Timestamp:    event.Timestamp,
			AutomationID: event.AutomationID,
		})
	case string(automations.EventPullRequestMerged):
		mergedPR := *prInfo
		if pr.GetMerged() {
			mergedPR.State = PullRequestStateMerged
		}
		return h.OnPullRequestStateChanged(ctx, PullRequestStateChangedEvent{
			Actor:        actor,
			Repo:         repo,
			PullRequest:  &mergedPR,
			AgentID:      app.AppID(),
			Timestamp:    event.Timestamp,
			AutomationID: event.AutomationID,
		})
	default:
		return h.OnPullRequestOpened(ctx, PullRequestOpenedEvent{
			Actor:        actor,
			Repo:         repo,
			Owner:        owner,
			PullRequest:  prInfo,
			HeadRepoID:   event.RepoID,
			Title:        pr.GetTitle(),
			Body:         pr.GetBody(),
			AgentID:      app.AppID(),
			Timestamp:    event.Timestamp,
			AutomationID: event.AutomationID,
		})
	}
}

// parseIssueNumberFromURL extracts the issue number from a GitHub issue URL.
// Expected format: https://github.com/{owner}/{repo}/issues/{number}
func parseIssueNumberFromURL(rawURL string) (int, error) {
	parts := splitURLPath(rawURL)
	for i, part := range parts {
		if part == "issues" && i+1 < len(parts) {
			num, err := strconv.Atoi(parts[i+1])
			if err != nil {
				return 0, goerrors.Errorf("invalid issue number in URL %q: %w", rawURL, err)
			}
			return num, nil
		}
	}
	return 0, goerrors.Errorf("could not find issue number in URL %q", rawURL)
}

// parsePullRequestNumberFromURL extracts the pull request number from a GitHub PR URL.
// Expected format: https://github.com/{owner}/{repo}/pull/{number}
func parsePullRequestNumberFromURL(rawURL string) (int, error) {
	parts := splitURLPath(rawURL)
	for i, part := range parts {
		if part == "pull" && i+1 < len(parts) {
			num, err := strconv.Atoi(parts[i+1])
			if err != nil {
				return 0, goerrors.Errorf("invalid pull request number in URL %q: %w", rawURL, err)
			}
			return num, nil
		}
	}
	return 0, goerrors.Errorf("could not find pull request number in URL %q", rawURL)
}

// parseWorkflowRunIDFromURL extracts the workflow run ID from a GitHub actions URL.
// Expected format: https://github.com/{owner}/{repo}/actions/runs/{id}
func parseWorkflowRunIDFromURL(rawURL string) (int64, error) {
	parts := splitURLPath(rawURL)
	for i, part := range parts {
		if part == "runs" && i+1 < len(parts) {
			id, err := strconv.ParseInt(parts[i+1], 10, 64)
			if err != nil {
				return 0, goerrors.Errorf("invalid workflow run ID in URL %q: %w", rawURL, err)
			}
			return id, nil
		}
	}
	return 0, goerrors.Errorf("could not find workflow run ID in URL %q", rawURL)
}

// splitURLPath extracts and splits the path segments from a URL, stripping
// any query string or fragment. Uses net/url for robust parsing.
func splitURLPath(rawURL string) []string {
	u, err := url.Parse(rawURL)
	if err != nil {
		// Fallback: treat the whole input as a path.
		return strings.Split(strings.Trim(rawURL, "/"), "/")
	}
	return strings.Split(strings.Trim(u.Path, "/"), "/")
}
