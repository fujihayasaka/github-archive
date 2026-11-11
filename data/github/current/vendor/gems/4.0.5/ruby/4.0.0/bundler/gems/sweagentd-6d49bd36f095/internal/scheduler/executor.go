package scheduler

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	stats "github.com/github/go-stats"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	"github.com/github/sweagentd/internal/sweagentd"

	"github.com/github/sweagentd/internal/agenticapp"
)

// ErrAutomationsDisabled signals the trigger run was skipped due to the admin automations policy.
var ErrAutomationsDisabled = errors.New("automations disabled for repository")

const triggerSkipReasonAutomationOwnerWrite = "automation_owner_write"

// executorFeatureFlags defines the feature flag checks the executor needs.
type executorFeatureFlags interface {
	IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, repo sweagentd.Repository) bool
	IsEnabledForRepoOrOwnerWithDefaultValue(ctx context.Context, featureFlagName string, defaultValue bool, repo sweagentd.Repository) bool
}

// automationsChecker is the narrow surface of triggers.Checker the executor needs.
type automationsChecker interface {
	AutomationsDisabled(ctx context.Context, agentID, actorID, repoID int64, triggerType string) (bool, error)
}

// Executor handles the actual execution of interval triggers: looking up agent config,
// checking feature flags, building and queuing jobs.
type Executor struct {
	ghFactory        github.ClientFactoryInterface
	checker          automationsChecker
	appProvider      *agenticapp.Provider
	jobSvc           *jobservice.Service
	ffClient         executorFeatureFlags
	obsv             observability.Exporters
	automationLookup automations.Lookup
}

// NewExecutor creates a new Executor.
func NewExecutor(
	ghFactory github.ClientFactoryInterface,
	checker automationsChecker,
	appProvider *agenticapp.Provider,
	jobSvc *jobservice.Service,
	ffClient executorFeatureFlags,
	obsv observability.Exporters,
	automationLookup automations.Lookup,
) *Executor {
	return &Executor{
		ghFactory:        ghFactory,
		checker:          checker,
		appProvider:      appProvider,
		jobSvc:           jobSvc,
		ffClient:         ffClient,
		obsv:             obsv,
		automationLookup: automationLookup,
	}
}

// Execute resolves the matching CMC automation, checks the master kill switch,
// and queues a job for the trigger.
func (e *Executor) Execute(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord) error {
	startTime := time.Now()

	ctx, span := e.obsv.Tracer.Start(ctx, "scheduler.Executor.Execute")
	defer span.End()

	logger := e.obsv.LoggerWithTelemetry(ctx)

	logger.Info("scheduler: executing interval trigger",
		kvp.String("trigger_id", trigger.ID),
		kvp.String("automation_id", trigger.AgentID),
		kvp.String("interval_type", trigger.IntervalType),
	)

	if e.automationLookup == nil {
		// Defensive: reconciler is wired alongside the lookup; advance and skip.
		e.obsv.Increment(ctx, "triggers.skipped", stats.Tags{"trigger_type": "interval", "reason": "no_cmc_lookup"})
		return nil
	}

	// Master kill switch.
	if !e.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentTriggers, &sweagentd.RepositoryAdapter{RepoID: trigger.RepoID, OwnerID: trigger.RepoOwnerID}) {
		logger.Info("custom agent triggers disabled for repo or owner, skipping",
			kvp.String("trigger_id", trigger.ID),
		)
		e.obsv.Increment(ctx, "triggers.skipped", stats.Tags{"trigger_type": "interval", "reason": "feature_flag"})
		return nil
	}

	// Interval-specific kill switch.
	if e.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentTriggersDisableInterval, &sweagentd.RepositoryAdapter{RepoID: trigger.RepoID, OwnerID: trigger.RepoOwnerID}) {
		logger.Info("interval triggers disabled for repo or owner, skipping",
			kvp.String("trigger_id", trigger.ID),
		)
		e.obsv.Increment(ctx, "triggers.skipped", stats.Tags{"trigger_type": "interval", "reason": "interval_disabled"})
		return nil
	}

	// Find agentic app.
	app, err := e.appProvider.FindByID(ctx, 0)
	if err != nil {
		return goerrors.Errorf("failed to find agentic app: %w", err)
	}

	// Automations policy gate. Actor for CMC is the automation owner, set by
	// the reconciler from automation.UserId.
	if e.checker != nil {
		disabled, err := e.checker.AutomationsDisabled(ctx, app.AppID(), trigger.ActorID, trigger.RepoID, "interval")
		if err != nil {
			return goerrors.Errorf("failed to check automations_disabled: %w", err)
		}
		if disabled {
			return ErrAutomationsDisabled
		}
	}

	// Resolve repo identity from GitHub before the CMC lookup so RepoInfo is
	// populated on the matched CustomAgent (the lifecycle event payload
	// carries numeric IDs only — the trigger record has empty owner/name).
	gh, err := e.ghFactory.NewClientFromRepo(ctx, app, trigger.RepoID, trigger.RepoOwnerID)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	repo, err := gh.GetRepositoryByID(ctx, trigger.RepoID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}
	if repo.GetVisibility() == "public" && featureflags.ShouldSkipPublicRepoAutomations(ctx, e.ffClient, &sweagentd.RepositoryAdapter{RepoID: trigger.RepoID, OwnerID: trigger.RepoOwnerID}) {
		logger.Info("interval trigger skipped for public repository",
			kvp.String("trigger_id", trigger.ID),
			kvp.Int64("repo_id", trigger.RepoID),
		)
		e.obsv.Increment(ctx, "triggers.skipped", stats.Tags{"trigger_type": "interval", "reason": "public_repository"})
		return nil
	}

	repoOwnerLogin := repo.GetOwner().GetLogin()
	repoName := repo.GetName()

	// Resolve runtime config via CMC. AgentID is the automation_id.
	configs, err := e.automationLookup.ListForEvent(ctx, automations.ListForEventRequest{
		Event: automations.EventMatchRequest{
			OwnerID:   trigger.RepoOwnerID,
			RepoID:    trigger.RepoID,
			EventName: automations.EventInterval,
		},
		Repo: automations.RepoInfo{
			OwnerLogin: repoOwnerLogin,
			RepoName:   repoName,
		},
	})
	if err != nil {
		return intervalTriggerJobError("cmc_lookup_error", goerrors.Errorf("failed to look up CMC automation config: %w", err))
	}

	var matched *automations.RuntimeConfig
	for i := range configs {
		if configs[i].AutomationID == trigger.AgentID {
			matched = &configs[i]
			break
		}
	}
	if matched == nil {
		// Automation no longer active in CMC; the reconciler will clean up
		// the local record on its DELETED event. Skip + advance to avoid busy-loop.
		logger.Info("scheduler: CMC automation no longer active — skipping",
			kvp.String("trigger_id", trigger.ID),
			kvp.String("automation_id", trigger.AgentID),
		)
		e.obsv.Increment(ctx, "triggers.skipped", stats.Tags{"trigger_type": "interval", "reason": "cmc_automation_missing"})
		return nil
	}

	skip, err := e.shouldSkipForAutomationOwnerPermissions(ctx, gh, trigger)
	if err != nil {
		return err
	}
	if skip {
		return nil
	}

	// Enrich context with custom agent identity for telemetry — mirrors the
	// legacy path so CMC-fired jobs emit the same custom_agent.* Datadog tags.
	_ = requestctx.AddCustomAgent(ctx, &requestctx.CtxCustomAgent{
		Name:    matched.CustomAgent.Name(),
		Scope:   matched.CustomAgent.Scope(),
		RepoID:  trigger.RepoID,
		OwnerID: trigger.RepoOwnerID,
	})

	// Enrich context with the automation owner for telemetry.
	_ = requestctx.AddUser(ctx, &requestctx.UserInfo{
		ID:    uint64(trigger.ActorID),
		Login: trigger.ActorLogin,
	})

	// Build job with CMC's runtime config. WithCustomAgent on both assignment
	// and builder is required — without it Build() falls back to the default
	// Copilot agent.
	resource := intervalTriggerResource(trigger)
	ps := intervalTriggerProblemStatement(trigger, matched.CustomAgent, repoOwnerLogin, repoName)
	useAsyncSessions := e.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, &sweagentd.RepositoryAdapter{RepoID: trigger.RepoID, OwnerID: trigger.RepoOwnerID})

	_, job, err := e.jobSvc.NewJobBuilder(jobs.AgentActionTask, repo, repo.GetDefaultBranch()).
		WithNewAssignmentWithCustomAgent(
			trigger.RepoOwnerID, trigger.RepoID,
			repo.GetOwner().GetNodeID(), repo.GetNodeID(),
			repoOwnerLogin, repoName,
			useAsyncSessions, matched.CustomAgent,
			resource,
		).
		WithActor(trigger.ActorID, trigger.ActorLogin, trigger.ActorLogin, "").
		WithTrigger().
		WithAutomationID(trigger.AgentID).
		WithCustomAgent(matched.CustomAgent).
		WithAgentID(app.AppID()).
		WithEvent(jobservice.Event{
			Type: jobs.EventTypeIntervalTriggered,
			URL:  fmt.Sprintf("https://github.com/%s/%s", repoOwnerLogin, repoName),
		}).
		WithProblemStatement(&ps).
		WithFeatures(jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				BaseRef: repo.GetDefaultBranch(),
			},
		}).
		WithNewSession().
		WithAINameGen().
		Build(ctx, gh)
	if err != nil {
		return goerrors.Errorf("failed to build job: %w", err)
	}

	_ = requestctx.AddJob(ctx, &requestctx.CtxJob{
		ID:        job.ID,
		RepoID:    trigger.RepoID,
		OwnerID:   trigger.RepoOwnerID,
		EventType: string(jobs.EventTypeIntervalTriggered),
		ActorID:   trigger.ActorID,
	})

	// 9. Queue job.
	_, err = e.jobSvc.QueueJobForExecution(ctx, job)
	if err != nil {
		return goerrors.Errorf("failed to queue job: %w", err)
	}

	e.obsv.DistributionMs(ctx, "scheduler.executor.duration_ms", stats.Tags{"trigger_type": "interval", "interval_type": trigger.IntervalType}, time.Since(startTime))
	e.obsv.Increment(ctx, "triggers.fired", stats.Tags{"trigger_type": "interval", "interval_type": trigger.IntervalType})

	logger.Info("interval trigger job queued",
		kvp.String("trigger_id", trigger.ID),
		kvp.String("automation_id", trigger.AgentID),
	)

	return nil
}

func (e *Executor) shouldSkipForAutomationOwnerPermissions(ctx context.Context, gh github.ClientInterface, trigger *schedulerstore.IntervalTriggerRecord) (bool, error) {
	logger := e.obsv.LoggerWithTelemetry(ctx)

	if trigger.ActorLogin == "" {
		logger.Info("interval trigger skipped because automation owner login is missing",
			kvp.String("trigger_id", trigger.ID),
			kvp.String("automation_id", trigger.AgentID),
			kvp.Int64("automation_owner_id", trigger.ActorID),
		)
		e.obsv.Increment(ctx, "triggers.skipped", stats.Tags{"trigger_type": "interval", "reason": "missing_automation_owner"})
		return true, nil
	}

	permission, err := gh.GetUserPermissionsForRepositoryByID(ctx, trigger.RepoID, trigger.ActorLogin)
	if err != nil {
		return false, goerrors.Errorf("failed to check automation owner permissions: %w", err)
	}
	if permission.Push {
		return false, nil
	}

	logger.Info("interval trigger skipped because automation owner does not have write access to the repo",
		kvp.String("trigger_id", trigger.ID),
		kvp.String("automation_id", trigger.AgentID),
		kvp.Int64("automation_owner_id", trigger.ActorID),
		kvp.String("automation_owner_login", trigger.ActorLogin),
	)
	e.obsv.Increment(ctx, "triggers.skipped", stats.Tags{"trigger_type": "interval", "reason": triggerSkipReasonAutomationOwnerWrite})
	return true, nil
}

func intervalTriggerResource(trigger *schedulerstore.IntervalTriggerRecord) jobs.AssignmentResource {
	return jobs.AssignmentResource{
		Type: "interval_trigger",
		ID:   trigger.ID,
	}
}

func intervalTriggerProblemStatement(trigger *schedulerstore.IntervalTriggerRecord, agent sweagentd.CustomAgent, repoOwnerLogin, repoName string) jobs.ProblemStatement {
	content := fmt.Sprintf("Scheduled %s interval trigger for automation %q in %s/%s",
		trigger.IntervalType, agent.Name(), repoOwnerLogin, repoName)
	return jobs.ProblemStatement{
		Content:           content,
		ContentFilterMode: jobs.ProblemStatementContentFilterModeNone,
	}
}
