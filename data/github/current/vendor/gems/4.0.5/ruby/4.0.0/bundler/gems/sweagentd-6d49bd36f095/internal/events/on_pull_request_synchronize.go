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
)

const maxSynchronizeJobsPerBranch = 3

// pullRequestIsFromFork reports whether the PR head repo differs from the base repo, failing closed (true) when the head repo is unknown.
func pullRequestIsFromFork(ghPR *gg.PullRequest, baseRepoID int64) bool {
	head := ghPR.GetHead().GetRepo()
	if head == nil || head.GetID() == 0 {
		return true
	}
	if base := ghPR.GetBase().GetRepo(); base != nil && base.GetID() != 0 {
		return head.GetID() != base.GetID()
	}
	return head.GetID() != baseRepoID
}

// OnPullRequestSynchronize handles PullRequestSynchronizeEvent and dispatches matching pull_request.synchronize automations.
// Defense in depth: synchronize proto lacks request_context.auth, so we cap jobs per branch (CopilotSWEAgentMaxTriggerRetries) to break agent → push → synchronize → agent loops when integration-auth detection misses.
func (h *Handler) OnPullRequestSynchronize(ctx context.Context, event PullRequestSynchronizeEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.OnPullRequestSynchronize")
	defer span.End()

	triggerTags := stats.Tags{"trigger_type": "pull_request_synchronize"}

	h.obsv.LoggerWithTelemetry(ctx).Info("Processing OnPullRequestSynchronize event")
	h.obsv.Increment(ctx, "triggers.received", triggerTags)

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID from pull_request synchronize event: %w", err)
	}

	if h.automationLookup == nil {
		h.obsv.LoggerWithTelemetry(ctx).Info("Automation lookup not available, skipping OnPullRequestSynchronize event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_trigger_checker"}))
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
			ActivityType: automations.ActivityPullRequestSynchronize,
		},
		Repo: automations.RepoInfo{
			OwnerLogin: ownerLogin,
			RepoName:   repo.Name,
		},
		AutomationID: event.AutomationID,
	})
	if err != nil {
		return goerrors.Errorf("failed to get automations with matching pull_request.synchronize triggers: %w", err)
	}

	if len(runtimeConfigs) == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("No custom agents with matching triggers found for pull_request.synchronize event")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "no_matching_agents"}))
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Int("triggers.matching_agents", len(runtimeConfigs))).
		Info("Found custom agents with matching triggers for pull_request.synchronize event")

	ghPR, err := gh.GetPullRequest(ctx, repo.ID, pr.Number)
	if err != nil {
		return goerrors.Errorf("failed to get pull request details: %w", err)
	}

	// Synchronize proto omits head-repo info, so fork status is computed here from the hydrated PR (fail closed when head is unknown).
	if pullRequestIsFromFork(ghPR, repo.ID) {
		h.obsv.LoggerWithTelemetry(ctx).Info("Skipping pull_request.synchronize event from fork")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "from_fork"}))
		return nil
	}

	actorLogin := ""
	if event.Actor != nil {
		actorLogin = event.Actor.Login
	}

	actorCtx, err := h.resolveActorPermissionContext(ctx, gh, repo, actorLogin, runtimeConfigs)
	if err != nil {
		return goerrors.Errorf("failed to check pull_request.synchronize actor permissions: %w", err)
	}

	runtimeConfigs = h.filterConfigsByActorPermissions(ctx, triggerTags, actorCtx, runtimeConfigs)
	if len(runtimeConfigs) == 0 {
		return nil
	}

	err = h.dispatchTriggerJobs(ctx, "OnPullRequestSynchronize", triggerTags, runtimeConfigs, func(runtimeConfig automations.RuntimeConfig) (bool, error) {
		return h.buildJobForPullRequestSynchronize(ctx, gh, app, runtimeConfig, triggerTags, event, ghRepo, ghPR)
	})
	if err != nil {
		return err
	}

	h.obsv.Increment(ctx, "triggers.handled", triggerTags)
	return nil
}

func (h *Handler) buildJobForPullRequestSynchronize(
	ctx context.Context,
	gh github.ClientInterface,
	app sweagentd.AgenticApp,
	runtimeConfig automations.RuntimeConfig,
	triggerTags stats.Tags,
	event PullRequestSynchronizeEvent,
	ghRepo *gg.Repository,
	ghPR *gg.PullRequest,
) (bool, error) {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.buildJobForPullRequestSynchronize")
	defer span.End()

	repo := event.Repo
	pr := event.PullRequest
	agent := runtimeConfig.CustomAgent

	if prTrigger := agent.Triggers().PullRequestSynchronize; prTrigger != nil {
		skip, filterErr := h.applyPullRequestSynchronizeFilters(ctx, gh, prTrigger, event, ghPR, triggerTags)
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

	headBranch := pr.HeadBranch
	if headBranch == "" {
		headBranch = ghPR.GetHead().GetRef()
	}

	// Treat default-branch head as a business-logic skip, not an error, to avoid Sentry alerts.
	if headBranch != "" && headBranch == ghRepo.GetDefaultBranch() {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("branch", headBranch),
		).Info("pull_request.synchronize head branch equals default branch, skipping to prevent direct commits")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "head_is_default_branch"}))
		return false, nil
	}

	// Defense-in-depth: cap repeated triggers per branch to prevent agent → push → synchronize loops when integration-auth detection misses.
	if h.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentMaxTriggerRetries, repo) {
		count, cErr := h.jobsStore.CountJobsForBranchAndEventType(ctx, repo.OwnerID, repo.ID, headBranch, jobs.EventTypePullRequestSynchronize)
		if cErr != nil {
			h.obsv.LogAndReportError(ctx, cErr, "failed to count prior synchronize jobs for branch")
		} else if count >= maxSynchronizeJobsPerBranch {
			h.obsv.LoggerWithTelemetry(ctx).WithFields(
				kvp.String("branch", headBranch),
				kvp.Int("prior_jobs", count),
			).Info("pull_request.synchronize trigger retry cap reached, skipping")
			h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "retry_cap_reached"}))
			return false, nil
		}
	}

	// Block jobs that branch protection would reject before queueing.
	rulesResult := h.jobService.CheckRules(ctx, gh, app, &jobs.Job{
		ActorID:    jobActor.ID,
		OwnerID:    repo.OwnerID,
		RepoID:     repo.ID,
		RepoNodeID: ghRepo.GetNodeID(),
		AgentID:    app.AppID(),
		BranchName: headBranch,
	}, ghRepo.GetOwner().GetLogin(), repo.Name, headBranch, false)
	if len(rulesResult.Rules) > 0 {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("branch", headBranch),
			kvp.Int("rules.count", len(rulesResult.Rules)),
		).Info("repository rules prevent agent from working on PR head branch, skipping")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "rules_violation"}))
		return false, nil
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, repo.ID)

	ownerNodeID := ghRepo.GetOwner().GetNodeID()
	ownerLogin := ghRepo.GetOwner().GetLogin()

	builder := h.jobService.NewJobBuilder(jobs.AgentActionTask, ghRepo, headBranch).
		WithNewAssignment(repo.OwnerID, repo.ID, ownerNodeID, ghRepo.GetNodeID(), ownerLogin, repo.Name, useAsyncSessions, pullRequestResource(pr.ID)).
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
			return pullRequestSynchronizeProblemStatement(event, ghRepo, ghPR)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestSynchronize,
			URL:         ghPR.GetHTMLURL(),
			Identifiers: eventIdentifiers(pr.ID),
			Content:     ghPR.GetBody(),
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

	h.obsv.LoggerWithTelemetry(ctx).Info("successfully built job for pull_request.synchronize event")
	h.obsv.LoggerWithTelemetry(ctx).Info("queuing job for execution")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return false, goerrors.Errorf("failed to queue job: %w", err)
	}

	return true, nil
}

func pullRequestSynchronizeProblemStatement(event PullRequestSynchronizeEvent, repo *gg.Repository, pr *gg.PullRequest) (jobs.ProblemStatement, error) {
	var sb strings.Builder
	fmt.Fprintf(&sb, "You have been triggered by new commits being pushed to a pull request in the %s repository.\n\n", repo.GetFullName())
	fmt.Fprintf(&sb, "Pull request number: %d\n", pr.GetNumber())
	fmt.Fprintf(&sb, "URL: %s\n", pr.GetHTMLURL())
	if head := pr.GetHead().GetRef(); head != "" {
		fmt.Fprintf(&sb, "Head branch: %s\n", head)
	}
	if base := pr.GetBase().GetRef(); base != "" {
		fmt.Fprintf(&sb, "Base branch: %s\n", base)
	}
	if event.BeforeOID != "" && event.AfterOID != "" {
		fmt.Fprintf(&sb, "Pushed commits: %s..%s\n", event.BeforeOID, event.AfterOID)
	}
	sb.WriteString("\n")
	fmt.Fprintf(&sb, "<pull_request_title>%s</pull_request_title>\n", pr.GetTitle())
	fmt.Fprintf(&sb, "<pull_request_description>%s</pull_request_description>\n\n", pr.GetBody())
	sb.WriteString("You can use the GitHub MCP server to access more details about this pull request, including its diff and review state.\n")

	return jobs.ProblemStatement{Content: sb.String()}, nil
}

// applyPullRequestSynchronizeFilters evaluates query and paths filters against the hydrated PR. Query fails-OPEN; paths fail-CLOSED.
func (h *Handler) applyPullRequestSynchronizeFilters(
	ctx context.Context,
	gh github.ClientInterface,
	prTrigger *sweagentd.CustomAgentPullRequestTrigger,
	event PullRequestSynchronizeEvent,
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
			h.obsv.LoggerWithTelemetry(ctx).Info("Synchronized pull request did not match trigger query filter, skipping")
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
		h.obsv.LoggerWithTelemetry(ctx).Info("Synchronized pull request did not match trigger paths filter, skipping")
		h.obsv.Increment(ctx, "triggers.filtered", triggerTags.Merge(stats.Tags{"filter": "paths"}))
		return true, nil
	}
	return false, nil
}
