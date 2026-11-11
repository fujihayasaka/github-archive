package events

import (
	"context"
	"fmt"
	"slices"
	"strconv"
	"strings"

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

// IssuesTypeOpened represents the "opened" issue event type.
//
// TODO (colbylwilliams): move this to the correct place later.
const IssuesTypeOpened = "opened"

// OnIssueCreated is called to handle an IssueCreatedEvent event associated with
// a custom agent trigger.
func (h *Handler) OnIssueCreated(ctx context.Context, event IssueCreatedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.OnIssueCreated")
	defer span.End()

	h.obsv.LoggerWithTelemetry(ctx).Info("Processing OnIssueCreated event")
	h.obsv.Statter.Counter("events.on_issue_created.received", nil, 1)

	// Double check that the feature flag is enabled before proceeding.
	if !h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentTriggers, &event) {
		h.obsv.LoggerWithTelemetry(ctx).Info("Feature flag for custom agent triggers is disabled, skipping OnIssueCreated event")
		h.obsv.Statter.Counter("events.on_issue_created.skipped_feature_flag_disabled", nil, 1)
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("Feature flag for custom agent triggers is enabled, handling OnIssueCreated event")

	// This should always succeed because we hard-code copilot's agent ID into
	// the IssueCreatedEvent when we parse it from Hydro.
	app, err := h.appProvider.FindByID(event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID from issue created event: %w", err)
	}

	userID := uint64(event.Actor.ID)

	// List all custom agents for the repository.
	agents, err := h.customAgents.ListAgentsByRepoID(ctx, uint64(event.Repo.ID), customagent.ListAgentsOpts{
		UserID:               userID,
		Target:               customagent.TargetGitHubCopilot,
		ExcludeInvalidConfig: true,
		DedupeNames:          true,
		IncludeSources:       []string{customagent.SourceTypeRepo},
	})
	if err != nil {
		return goerrors.Errorf("failed to list custom agents for repo: %w", err)
	}

	// Filter agents to only those that have an issue create trigger.
	agents = slices.DeleteFunc(agents, func(a sweagentd.CustomAgent) bool {
		return !hasIssueCreateTrigger(a)
	})
	agents = slices.Clip(agents)

	if len(agents) == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("No custom agents with issue opened triggers found for repository, skipping OnIssueCreated event")
		h.obsv.Statter.Counter("events.on_issue_created.skipped_no_triggers", nil, 1)
		return nil
	}

	gh, err := h.ghFactory.NewClientForRepo(ctx, app, &event)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	// For each agent, build and queue a job. Generally, unexpected errors while
	// building or queuing for one agent should not block processing for other agents.
	for _, agent := range agents {
		h.obsv.LoggerWithTelemetry(ctx).Info("Building and queuing job for custom agent trigger for OnIssueCreated event")

		err := h.buildJobForIssueCreated(ctx, gh, app, agent, event)
		if err == nil {
			h.obsv.LoggerWithTelemetry(ctx).Info("successfully built and queued job for OnIssueCreated event")
			h.obsv.Statter.Counter("events.on_issue_created.job_built_and_queued", nil, 1)
			continue
		}

		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to build or queue job for OnIssueCreated event")
		h.obsv.Statter.Counter("events.on_issue_created.build_or_queue_job_error", nil, 1)

		switch {
		case jobservice.IsBuilderFinalizedJobError(err):
			// If it's a builder finalized error, we can just keep going.
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).Info("job builder finalized error encountered, continuing to next agent")

			continue
		case limiter.IsAnyLimiterError(err):
			// If it's a ratelimit error, we should return it and stop processing.
			//
			// TODO (colbylwilliams):
			// Once we return this error, the aqueduct job will be re-enqueued
			// and we'll receive it again later to retry. If there are multiple
			// agents with this trigger, the current code will retry building
			// the jobs for ALL agents again - even those that were successful
			// on prior attempts. This will lead to duplicate jobs being created
			// for those agents.
			//
			// To prevent creating duplicate jobs in this scenario, we should
			// probably query the database for existing jobs associated with
			// this event, and only attempt to build jobs for agents that don't
			// already have a successfully built job.
			//
			// For now, we'll just return the error and accept the potential risk of
			// duplication of jobs for successfully built ones.
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).Info("rate limit error encountered, stopping processing of OnIssueCreated event to retry later")

			return err
		default:
			// For all other errors, we just log and continue.
			h.obsv.LogAndReportError(ctx, err, "unexpected error building or queuing job for OnIssueCreated event")

			continue
		}
	}

	h.obsv.Statter.Counter("events.on_issue_created.handled", nil, 1)
	return nil
}

func hasIssueCreateTrigger(agent sweagentd.CustomAgent) bool {
	triggers := agent.Triggers()
	if triggers.Issues == nil {
		return false
	}

	issueTypes := triggers.Issues.Types
	if len(issueTypes) == 0 {
		return false
	}

	return slices.Contains(issueTypes, IssuesTypeOpened)
}

func (h *Handler) buildJobForIssueCreated(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, agent sweagentd.CustomAgent, event IssueCreatedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.buildJobForIssueCreated")
	defer span.End()

	repo := event.Repo
	owner := event.Owner
	issue := event.Issue

	// get the issue resource
	details, err := gh.GetIssue(ctx, owner.Login, repo.Name, issue.Number)
	if err != nil {
		return goerrors.Errorf("failed to get issue details from GitHub: %w", err)
	}

	jobActor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return goerrors.Errorf("failed to get job actor: %w", err)
	}

	var pullRequestFeature *jobs.PullRequestFeature
	// Only create a pull request if the feature flag is enabled.
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentTriggersCreatePR, &event) {
		agentName := agent.DisplayName()
		if agentName == "" {
			agentName = agent.Name()
		}
		pullRequestFeature = &jobs.PullRequestFeature{
			TitlePlaceholder: fmt.Sprintf("%s: Issue #%d %s", agentName, issue.Number, IssuesTypeOpened),
			BodyPlaceholder:  fmt.Sprintf("Starting work to handle opening issue #%d: %s", issue.Number, details.GetTitle()),
		}
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, repo.ID)

	// Fetch repository from GitHub API
	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	builder := h.jobService.NewJobBuilder(jobs.AgentActionTask, ggRepo, repo.DefaultBranch).
		WithNewAssignment(owner.ID, repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, useAsyncSessions, issueResource(event.Issue.ID)).
		WithJobActor(*jobActor).
		WithJobInitHook(func(j *jobs.Job) {
			j.IssueNumber = issue.Number
		}).
		WithCustomAgent(agent).
		WithAgentID(app.AppID()).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return issueCreatedTriggerProblemStatement(details)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypeIssueCreated,
			Identifiers: eventIdentifiers(issue.ID),
			Content:     details.GetBody(),
		}).
		WithFeatures(jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				BaseRef: repo.DefaultBranch,
				Name:    fmt.Sprintf("issue-%d-%s", issue.Number, IssuesTypeOpened),
			},
			PullRequest: pullRequestFeature,
		}).
		WithNewSession().
		WithAINameGen()

	_, job, err := builder.Build(ctx, gh)
	if err != nil {
		return goerrors.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("successfully built job for issue created event")

	h.obsv.LoggerWithTelemetry(ctx).Info("queuing job for execution")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return goerrors.Errorf("failed to queue job: %w", err)
	}

	return nil
}

// issueResource creates an assignment resource for an issue
func issueResource(id int64) jobs.AssignmentResource {
	return jobs.AssignmentResource{
		Type: "issue",
		ID:   strconv.FormatInt(id, 10),
	}
}

func issueCreatedTriggerProblemStatement(issue *gg.Issue) (jobs.ProblemStatement, error) {
	var sb strings.Builder
	_, _ = sb.WriteString(fmt.Sprintf("You have been triggered by a new issue being %s in the %s repository.\n\n", IssuesTypeOpened, issue.GetRepository().GetFullName()))
	_, _ = sb.WriteString(fmt.Sprintf("Issue number: %d\n", issue.GetNumber()))
	_, _ = sb.WriteString(fmt.Sprintf("URL: %s\n\n", issue.GetHTMLURL()))
	_, _ = sb.WriteString(fmt.Sprintf("<issue_title>%s</issue_title>\n", issue.GetTitle()))
	_, _ = sb.WriteString(fmt.Sprintf("<issue_description>%s</issue_description>\n\n", issue.GetBody()))
	_, _ = sb.WriteString("You can use the GitHub MCP server to access more details about this issue.\n")

	return jobs.ProblemStatement{
		Content: sb.String(),
	}, nil
}
