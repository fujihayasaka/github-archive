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

// firePullRequestMergedTriggers dispatches matching pull_request.merged automations.
func (h *Handler) firePullRequestMergedTriggers(ctx context.Context, event PullRequestStateChangedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.firePullRequestMergedTriggers")
	defer span.End()

	triggerTags := stats.Tags{"trigger_type": "pull_request_merged"}

	h.obsv.LoggerWithTelemetry(ctx).Info("Processing pull_request.merged trigger event")
	h.obsv.Increment(ctx, "triggers.received", triggerTags)

	if event.PullRequest == nil {
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_pull_request"}))
		return nil
	}
	if event.PullRequest.State != PullRequestStateMerged {
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "not_merged"}))
		return nil
	}

	app := h.appProvider.CopilotApp()
	if app == nil {
		h.obsv.LoggerWithTelemetry(ctx).Error("Copilot app not configured, skipping pull_request.merged trigger")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_copilot_app"}))
		return nil
	}

	repo := event.Repo
	pr := event.PullRequest

	gh, err := h.ghFactory.NewClientForRepo(ctx, app, &event)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	ghRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}
	ownerLogin := ghRepo.GetOwner().GetLogin()

	runtimeConfigs, err := h.automationLookup.ListForEvent(ctx, automations.ListForEventRequest{
		Event: automations.EventMatchRequest{
			OwnerID:      repo.OwnerID,
			RepoID:       repo.ID,
			EventName:    automations.EventPullRequest,
			ActivityType: automations.ActivityPullRequestMerged,
		},
		Repo: automations.RepoInfo{
			OwnerLogin: ownerLogin,
			RepoName:   repo.Name,
		},
		AutomationID: event.AutomationID,
	})
	if err != nil {
		return goerrors.Errorf("failed to get automations with matching pull_request.merged triggers: %w", err)
	}

	if len(runtimeConfigs) == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("No custom agents with matching triggers found for pull_request.merged event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_matching_agents"}))
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Int("triggers.matching_agents", len(runtimeConfigs))).
		Info("Found custom agents with matching triggers for pull_request.merged event")

	actorLogin := ""
	if event.Actor != nil {
		actorLogin = event.Actor.Login
	}

	actorCtx, err := h.resolveActorPermissionContext(ctx, gh, repo, actorLogin, runtimeConfigs)
	if err != nil {
		return goerrors.Errorf("failed to check pull_request.merged actor permissions: %w", err)
	}

	runtimeConfigs = h.filterConfigsByActorPermissions(ctx, triggerTags, actorCtx, runtimeConfigs)
	if len(runtimeConfigs) == 0 {
		return nil
	}

	// Hydrate PR details only after actor filtering trims configs, to avoid the API call on permission-rejected events.
	ghPR, err := gh.GetPullRequest(ctx, repo.ID, pr.Number)
	if err != nil {
		return goerrors.Errorf("failed to get pull request details: %w", err)
	}

	err = h.dispatchTriggerJobs(ctx, "OnPullRequestMerged", triggerTags, runtimeConfigs, func(runtimeConfig automations.RuntimeConfig) (bool, error) {
		return h.buildJobForPullRequestMerged(ctx, gh, app, runtimeConfig, triggerTags, event, ghRepo, ghPR)
	})
	if err != nil {
		return err
	}

	h.obsv.Increment(ctx, "triggers.handled", triggerTags)
	return nil
}

func (h *Handler) buildJobForPullRequestMerged(
	ctx context.Context,
	gh github.ClientInterface,
	app sweagentd.AgenticApp,
	runtimeConfig automations.RuntimeConfig,
	triggerTags stats.Tags,
	event PullRequestStateChangedEvent,
	ghRepo *gg.Repository,
	ghPR *gg.PullRequest,
) (bool, error) {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.buildJobForPullRequestMerged")
	defer span.End()

	repo := event.Repo
	pr := event.PullRequest
	agent := runtimeConfig.CustomAgent

	if prTrigger := agent.Triggers().PullRequestMerged; prTrigger != nil {
		skip, filterErr := h.applyPullRequestMergedFilters(ctx, gh, prTrigger, event, ghPR, triggerTags)
		if filterErr != nil {
			return false, filterErr
		}
		if skip {
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

	ownerLogin := ghRepo.GetOwner().GetLogin()
	ownerNodeID := ghRepo.GetOwner().GetNodeID()
	repoNodeID := ghRepo.GetNodeID()
	baseRef := ghRepo.GetDefaultBranch()

	// Use a distinct assignment resource so the Service cancellation sweep cannot match worker-built merged jobs.
	builder := h.jobService.NewJobBuilder(jobs.AgentActionTask, ghRepo, baseRef).
		WithNewAssignment(repo.OwnerID, repo.ID, ownerNodeID, repoNodeID, ownerLogin, repo.Name, useAsyncSessions, mergedPullRequestResource(pr.ID)).
		WithJobActor(*jobActor).
		WithTrigger().
		WithAutomationID(runtimeConfig.AutomationID).
		WithRequestStartedAt(event.Timestamp).
		WithCustomAgent(agent).
		WithAgentID(app.AppID()).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return pullRequestMergedProblemStatement(ghRepo, ghPR)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestMerged,
			URL:         ghPR.GetHTMLURL(),
			Identifiers: eventIdentifiers(pr.ID),
			Content:     ghPR.GetBody(),
		}).
		WithFeatures(jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{BaseRef: baseRef},
		}).
		WithNewSession().
		WithAINameGen()

	_, job, err := builder.Build(ctx, gh)
	if err != nil {
		return false, goerrors.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("successfully built job for pull_request.merged event")
	h.obsv.LoggerWithTelemetry(ctx).Info("queuing job for execution")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return false, goerrors.Errorf("failed to queue job: %w", err)
	}

	return true, nil
}

// mergedPullRequestResource is the assignment resource for a merged-trigger job, kept distinct from pullRequestResource so the Service cancellation sweep cannot match it.
func mergedPullRequestResource(id int64) jobs.AssignmentResource {
	return jobs.AssignmentResource{
		Type: "pull_request_merged",
		ID:   strconv.FormatInt(id, 10),
	}
}

func pullRequestMergedProblemStatement(repo *gg.Repository, pr *gg.PullRequest) (jobs.ProblemStatement, error) {
	var sb strings.Builder
	fmt.Fprintf(&sb, "You have been triggered by a pull request being merged in the %s repository.\n\n", repo.GetFullName())
	fmt.Fprintf(&sb, "Pull request number: %d\n", pr.GetNumber())
	fmt.Fprintf(&sb, "URL: %s\n", pr.GetHTMLURL())
	if base := pr.GetBase().GetRef(); base != "" {
		fmt.Fprintf(&sb, "Base branch: %s\n", base)
	}
	if head := pr.GetHead().GetRef(); head != "" {
		fmt.Fprintf(&sb, "Merged head branch: %s\n", head)
	}
	sb.WriteString("\n")
	fmt.Fprintf(&sb, "<pull_request_title>%s</pull_request_title>\n", pr.GetTitle())
	fmt.Fprintf(&sb, "<pull_request_description>%s</pull_request_description>\n\n", pr.GetBody())
	sb.WriteString("You can use the GitHub MCP server to access more details about this pull request, including its diff.\n")

	return jobs.ProblemStatement{Content: sb.String()}, nil
}

// applyPullRequestMergedFilters runs query (fail-open) and paths (fail-closed) filters against the PR.
func (h *Handler) applyPullRequestMergedFilters(
	ctx context.Context,
	gh github.ClientInterface,
	prTrigger *sweagentd.CustomAgentPullRequestTrigger,
	event PullRequestStateChangedEvent,
	ghPR *gg.PullRequest,
	triggerTags stats.Tags,
) (bool, error) {
	if strings.TrimSpace(prTrigger.Query) != "" {
		res := issuefilter.EvaluatePR(prTrigger.Query, ghPR)
		if res.Error != "" {
			h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("filter_error", res.Error)).
				Warn("Pull request filter query evaluation error (fail-open)")
		}
		if !res.Matched {
			h.obsv.LoggerWithTelemetry(ctx).Info("Merged pull request did not match trigger query filter, skipping")
			h.obsv.Increment(ctx, "triggers.filtered", triggerTags.Merge(stats.Tags{"filter": "query"}))
			return true, nil
		}
	}
	if len(prTrigger.Paths) == 0 {
		return false, nil
	}
	files, err := gh.ListPullRequestFiles(ctx, ghPR.GetBase().GetRepo().GetOwner().GetLogin(), event.Repo.Name, event.PullRequest.Number)
	if err != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("error", err.Error())).
			Warn("Failed to list pull request files for paths filter, skipping (fail-closed)")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "paths_api_error"}))
		return true, nil
	}
	matched, mErr := matchesAnyChangedPath(prTrigger.Paths, files)
	if mErr != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("filter_error", mErr.Error())).
			Warn("Pull request paths filter evaluation error, skipping (fail-closed)")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "paths_parse_error"}))
		return true, nil
	}
	if !matched {
		h.obsv.LoggerWithTelemetry(ctx).Info("Merged pull request did not match trigger paths filter, skipping")
		h.obsv.Increment(ctx, "triggers.filtered", triggerTags.Merge(stats.Tags{"filter": "paths"}))
		return true, nil
	}
	return false, nil
}
