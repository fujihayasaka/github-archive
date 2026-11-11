package events

import (
	"context"
	"fmt"
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
	"github.com/moby/patternmatcher"
)

// OnPullRequestOpened handles a PullRequestOpenedEvent and dispatches matching CCA automations.
func (h *Handler) OnPullRequestOpened(ctx context.Context, event PullRequestOpenedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.OnPullRequestOpened")
	defer span.End()

	triggerTags := stats.Tags{"trigger_type": "pull_request_opened"}

	h.obsv.LoggerWithTelemetry(ctx).Info("Processing OnPullRequestOpened event")
	h.obsv.Increment(ctx, "triggers.received", triggerTags)

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID from pull_request opened event: %w", err)
	}

	if h.automationLookup == nil {
		h.obsv.LoggerWithTelemetry(ctx).Info("Automation lookup not available, skipping OnPullRequestOpened event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_trigger_checker"}))
		return nil
	}

	repo := event.Repo
	owner := event.Owner

	runtimeConfigs, err := h.automationLookup.ListForEvent(ctx, automations.ListForEventRequest{
		Event: automations.EventMatchRequest{
			OwnerID:      owner.ID,
			RepoID:       repo.ID,
			EventName:    automations.EventPullRequest,
			ActivityType: automations.ActivityPullRequestOpened,
		},
		Repo: automations.RepoInfo{
			OwnerLogin: owner.Login,
			RepoName:   repo.Name,
		},
		AutomationID: event.AutomationID,
	})
	if err != nil {
		return goerrors.Errorf("failed to get automations with matching pull_request triggers: %w", err)
	}

	if len(runtimeConfigs) == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("No custom agents with matching triggers found for repository, skipping OnPullRequestOpened event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_matching_agents"}))
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Int("triggers.matching_agents", len(runtimeConfigs))).
		Info("Found custom agents with matching triggers for OnPullRequestOpened event")

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
		return goerrors.Errorf("failed to check pull_request actor permissions: %w", err)
	}

	runtimeConfigs = h.filterConfigsByActorPermissions(ctx, triggerTags, actorCtx, runtimeConfigs)
	if len(runtimeConfigs) == 0 {
		return nil
	}

	err = h.dispatchTriggerJobs(ctx, "OnPullRequestOpened", triggerTags, runtimeConfigs, func(runtimeConfig automations.RuntimeConfig) (bool, error) {
		return h.buildJobForPullRequestOpened(ctx, gh, app, runtimeConfig, triggerTags, event)
	})
	if err != nil {
		return err
	}

	h.obsv.Increment(ctx, "triggers.handled", triggerTags)
	return nil
}

func (h *Handler) buildJobForPullRequestOpened(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, runtimeConfig automations.RuntimeConfig, triggerTags stats.Tags, event PullRequestOpenedEvent) (bool, error) {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.buildJobForPullRequestOpened")
	defer span.End()

	repo := event.Repo
	owner := event.Owner
	pr := event.PullRequest
	agent := runtimeConfig.CustomAgent

	if prTrigger := agent.Triggers().PullRequestOpened; prTrigger != nil {
		skip, err := h.applyPullRequestFilters(ctx, gh, prTrigger, event, triggerTags)
		if err != nil {
			return false, err
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

	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return false, goerrors.Errorf("failed to get repository: %w", err)
	}

	// Treat default-branch head as a business-logic skip, not an error, to avoid Sentry alerts.
	headBranch := pr.HeadBranch
	if headBranch != "" && headBranch == ggRepo.GetDefaultBranch() {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("branch", headBranch),
		).Info("pull_request head branch equals default branch, skipping to prevent direct commits")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "head_is_default_branch"}))
		return false, nil
	}

	// Block jobs that branch protection would reject before queueing.
	rulesResult := h.jobService.CheckRules(ctx, gh, app, &jobs.Job{
		ActorID:    jobActor.ID,
		OwnerID:    owner.ID,
		RepoID:     repo.ID,
		RepoNodeID: repo.NodeID,
		AgentID:    app.AppID(),
		BranchName: headBranch,
	}, owner.Login, repo.Name, headBranch, false)
	if len(rulesResult.Rules) > 0 {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("branch", headBranch),
			kvp.Int("rules.count", len(rulesResult.Rules)),
		).Info("repository rules prevent agent from working on PR head branch, skipping")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "rules_violation"}))
		return false, nil
	}

	ownerNodeID := ggRepo.GetOwner().GetNodeID()
	repoNodeID := ggRepo.GetNodeID()

	builder := h.jobService.NewJobBuilder(jobs.AgentActionTask, ggRepo, headBranch).
		WithNewAssignment(owner.ID, repo.ID, ownerNodeID, repoNodeID, owner.Login, repo.Name, useAsyncSessions, pullRequestResource(pr.ID)).
		WithAssignmentPullRequest(pr.ID, pr.Number).
		WithJobActor(*jobActor).
		WithTrigger().
		WithAutomationID(runtimeConfig.AutomationID).
		WithRequestStartedAt(event.Timestamp).
		WithJobInitHook(func(j *jobs.Job) {
			j.BranchName = headBranch
		}).
		WithCustomAgent(agent).
		WithAgentID(app.AppID()).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return pullRequestOpenedProblemStatement(event, ggRepo)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestOpened,
			URL:         pullRequestHTMLURL(ggRepo, pr.Number),
			Identifiers: eventIdentifiers(pr.ID),
			Content:     event.Body,
		}).
		WithFeatures(jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				HeadRef: headBranch,
			},
		}).
		WithNewSession().
		WithAINameGen()

	_, job, err := builder.Build(ctx, gh)
	if err != nil {
		return false, goerrors.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("successfully built job for pull_request opened event")
	h.obsv.LoggerWithTelemetry(ctx).Info("queuing job for execution")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return false, goerrors.Errorf("failed to queue job: %w", err)
	}

	return true, nil
}

// pullRequestHTMLURL is constructed from owner/repo+number since the hydro event lacks html_url.
func pullRequestHTMLURL(repo *gg.Repository, number int) string {
	if repo == nil {
		return ""
	}
	return fmt.Sprintf("%s/pull/%d", repo.GetHTMLURL(), number)
}

func pullRequestOpenedProblemStatement(event PullRequestOpenedEvent, repo *gg.Repository) (jobs.ProblemStatement, error) {
	pr := event.PullRequest
	var sb strings.Builder
	fmt.Fprintf(&sb, "You have been triggered by a pull request being opened in the %s repository.\n\n", repo.GetFullName())
	fmt.Fprintf(&sb, "Pull request number: %d\n", pr.Number)
	fmt.Fprintf(&sb, "URL: %s\n", pullRequestHTMLURL(repo, pr.Number))
	if pr.HeadBranch != "" {
		fmt.Fprintf(&sb, "Head branch: %s\n", pr.HeadBranch)
	}
	if pr.BaseBranch != "" {
		fmt.Fprintf(&sb, "Base branch: %s\n", pr.BaseBranch)
	}
	sb.WriteString("\n")
	fmt.Fprintf(&sb, "<pull_request_title>%s</pull_request_title>\n", event.Title)
	fmt.Fprintf(&sb, "<pull_request_description>%s</pull_request_description>\n\n", event.Body)
	sb.WriteString("You can use the GitHub MCP server to access more details about this pull request, including its diff and review state.\n")

	return jobs.ProblemStatement{
		Content: sb.String(),
	}, nil
}

// matchesAnyChangedPath returns (false, err) on parse error so callers fail-CLOSED. CMC pre-validates.
func matchesAnyChangedPath(patterns []string, files []*gg.CommitFile) (bool, error) {
	pm, err := patternmatcher.New(patterns)
	if err != nil {
		return false, err
	}
	for _, f := range files {
		matched, mErr := pm.MatchesOrParentMatches(f.GetFilename())
		if mErr != nil {
			return false, mErr
		}
		if matched {
			return true, nil
		}
	}
	return false, nil
}

// applyPullRequestFilters evaluates the agent's query and paths filters. Query fails-OPEN; paths fail-CLOSED.
func (h *Handler) applyPullRequestFilters(ctx context.Context, gh github.ClientInterface, prTrigger *sweagentd.CustomAgentPullRequestTrigger, event PullRequestOpenedEvent, triggerTags stats.Tags) (skip bool, err error) {
	if strings.TrimSpace(prTrigger.Query) != "" {
		ghPR, gerr := gh.GetPullRequest(ctx, event.Repo.ID, event.PullRequest.Number)
		if gerr != nil {
			return false, goerrors.Errorf("failed to get pull request details from GitHub: %w", gerr)
		}
		res := issuefilter.EvaluatePR(prTrigger.Query, ghPR)
		if res.Error != "" {
			h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("filter_error", res.Error)).
				Warn("Pull request filter query evaluation error (fail-open)")
		}
		if !res.Matched {
			h.obsv.LoggerWithTelemetry(ctx).Info("Pull request did not match trigger query filter, skipping")
			h.obsv.Increment(ctx, "triggers.filtered", triggerTags.Merge(stats.Tags{"filter": "query"}))
			return true, nil
		}
	}
	if len(prTrigger.Paths) == 0 {
		return false, nil
	}
	files, ferr := gh.ListPullRequestFiles(ctx, event.Owner.Login, event.Repo.Name, event.PullRequest.Number)
	if ferr != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("error", ferr.Error())).
			Warn("Failed to list pull request files for paths filter, skipping (fail-closed)")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "paths_api_error"}))
		return true, nil
	}
	matched, perr := matchesAnyChangedPath(prTrigger.Paths, files)
	if perr != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("filter_error", perr.Error())).
			Warn("Pull request paths filter evaluation error, skipping (fail-closed)")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "paths_parse_error"}))
		return true, nil
	}
	if !matched {
		h.obsv.LoggerWithTelemetry(ctx).Info("Pull request did not match trigger paths filter, skipping")
		h.obsv.Increment(ctx, "triggers.filtered", triggerTags.Merge(stats.Tags{"filter": "paths"}))
		return true, nil
	}
	return false, nil
}
