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
	"github.com/github/sweagentd/internal/issuefilter"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// OnIssueCreated is called to handle an IssueCreatedEvent event associated with
// a custom agent trigger.
func (h *Handler) OnIssueCreated(ctx context.Context, event IssueCreatedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.OnIssueCreated")
	defer span.End()

	triggerTags := stats.Tags{"trigger_type": "issue_created"}

	h.obsv.LoggerWithTelemetry(ctx).Info("Processing OnIssueCreated event")
	h.obsv.Increment(ctx, "triggers.received", triggerTags)

	// This should always succeed because we hard-code copilot's agent ID into
	// the IssueCreatedEvent when we parse it from Hydro.
	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID from issue created event: %w", err)
	}

	if h.automationLookup == nil {
		h.obsv.LoggerWithTelemetry(ctx).Info("Automation lookup not available, skipping OnIssueCreated event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_trigger_checker"}))
		return nil
	}

	// Get runtime configs with matching triggers from the automation lookup.
	repo := event.Repo
	owner := event.Owner

	runtimeConfigs, err := h.automationLookup.ListForEvent(ctx, automations.ListForEventRequest{
		Event: automations.EventMatchRequest{
			OwnerID:      owner.ID,
			RepoID:       repo.ID,
			EventName:    automations.EventIssues,
			ActivityType: automations.ActivityIssueOpened,
		},
		Repo: automations.RepoInfo{
			OwnerLogin: owner.Login,
			RepoName:   repo.Name,
		},
		AutomationID: event.AutomationID,
	})
	if err != nil {
		return goerrors.Errorf("failed to get automations with matching triggers: %w", err)
	}

	if len(runtimeConfigs) == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("No custom agents with matching triggers found for repository, skipping OnIssueCreated event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_matching_agents"}))
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Int("triggers.matching_agents", len(runtimeConfigs))).
		Info("Found custom agents with matching triggers for OnIssueCreated event")

	gh, err := h.ghFactory.NewClientForRepo(ctx, app, &event)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	actorLogin := ""
	if event.Actor != nil {
		actorLogin = event.Actor.Login
	}

	actorCtx, err := h.resolveActorPermissionContext(ctx, gh, repo, actorLogin, runtimeConfigs)
	if err != nil {
		return goerrors.Errorf("failed to check issue actor permissions: %w", err)
	}

	runtimeConfigs = h.filterConfigsByActorPermissions(ctx, triggerTags, actorCtx, runtimeConfigs)
	if len(runtimeConfigs) == 0 {
		return nil
	}

	err = h.dispatchTriggerJobs(ctx, "OnIssueCreated", triggerTags, runtimeConfigs, func(runtimeConfig automations.RuntimeConfig) (bool, error) {
		return h.buildJobForIssueCreated(ctx, gh, app, runtimeConfig, triggerTags, event)
	})
	if err != nil {
		return err
	}

	h.obsv.Increment(ctx, "triggers.handled", triggerTags)
	return nil
}

func (h *Handler) buildJobForIssueCreated(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, runtimeConfig automations.RuntimeConfig, triggerTags stats.Tags, event IssueCreatedEvent) (bool, error) {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.buildJobForIssueCreated")
	defer span.End()

	repo := event.Repo
	owner := event.Owner
	issue := event.Issue
	agent := runtimeConfig.CustomAgent

	// get the issue resource
	details, err := gh.GetIssue(ctx, owner.Login, repo.Name, issue.Number)
	if err != nil {
		return false, goerrors.Errorf("failed to get issue details from GitHub: %w", err)
	}

	// Evaluate optional query filter from the agent's trigger config.
	// Uses fail-open: if the query is blank or invalid, the issue is still processed.
	if q := agent.Triggers().Issues; q != nil && q.Query != "" {
		filterResult := issuefilter.Evaluate(q.Query, details)
		if filterResult.Error != "" {
			h.obsv.LoggerWithTelemetry(ctx).WithFields(
				kvp.String("filter_error", filterResult.Error),
			).Warn("Issue filter query evaluation error (fail-open)")
		}
		if !filterResult.Matched {
			h.obsv.LoggerWithTelemetry(ctx).Info("Issue did not match trigger query filter, skipping")
			h.obsv.Increment(ctx, "triggers.filtered", stats.Tags{"trigger_type": "issue_created"})
			return false, nil
		}
	}

	jobActor, ok, err := h.jobActorForRuntimeConfig(ctx, gh, repo, runtimeConfig, triggerTags)
	if err != nil {
		return false, goerrors.Errorf("failed to check automation owner permissions: %w", err)
	}
	if !ok {
		return false, nil
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, repo.ID)

	// Fetch repository from GitHub API
	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return false, goerrors.Errorf("failed to get repository: %w", err)
	}

	defaultBranch := repo.DefaultBranch
	if defaultBranch == "" {
		defaultBranch = ggRepo.GetDefaultBranch()
	}

	ownerNodeID := owner.NodeID
	if ownerNodeID == "" {
		ownerNodeID = ggRepo.GetOwner().GetNodeID()
	}

	repoNodeID := repo.NodeID
	if repoNodeID == "" {
		repoNodeID = ggRepo.GetNodeID()
	}

	builder := h.jobService.NewJobBuilder(jobs.AgentActionTask, ggRepo, defaultBranch).
		WithNewAssignment(owner.ID, repo.ID, ownerNodeID, repoNodeID, owner.Login, repo.Name, useAsyncSessions, issueResource(details.GetID())).
		WithJobActor(*jobActor).
		WithTrigger().
		WithAutomationID(runtimeConfig.AutomationID).
		WithRequestStartedAt(event.Timestamp).
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
			URL:         details.GetHTMLURL(),
			Identifiers: eventIdentifiers(details.GetID()),
			Content:     details.GetBody(),
		}).
		WithNewSession().
		WithAINameGen().
		WithFeatures(jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				BaseRef: defaultBranch,
			},
		})

	_, job, err := builder.Build(ctx, gh)
	if err != nil {
		return false, goerrors.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("successfully built job for issue created event")

	h.obsv.LoggerWithTelemetry(ctx).Info("queuing job for execution")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return false, goerrors.Errorf("failed to queue job: %w", err)
	}

	return true, nil
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
	_, _ = sb.WriteString(fmt.Sprintf("You have been triggered by a new issue being %s in the %s repository.\n\n", automations.ActivityIssueOpened, issue.GetRepository().GetFullName()))
	_, _ = sb.WriteString(fmt.Sprintf("Issue number: %d\n", issue.GetNumber()))
	_, _ = sb.WriteString(fmt.Sprintf("URL: %s\n\n", issue.GetHTMLURL()))
	_, _ = sb.WriteString(fmt.Sprintf("<issue_title>%s</issue_title>\n", issue.GetTitle()))
	_, _ = sb.WriteString(fmt.Sprintf("<issue_description>%s</issue_description>\n\n", issue.GetBody()))
	_, _ = sb.WriteString("You can use the GitHub MCP server to access more details about this issue.\n")

	return jobs.ProblemStatement{
		Content: sb.String(),
	}, nil
}
