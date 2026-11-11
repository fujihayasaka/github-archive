package events

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

type isOpen interface {
	isOpen() bool
}

const (
	triggerSkipReasonActorPermissionPolicy        = "actor_permission_policy"
	triggerSkipReasonAutomationOwnerLookup        = "automation_owner_lookup"
	triggerSkipReasonAutomationOwnerWrite         = "automation_owner_write"
	triggerSkipReasonAutomationRequiresActorWrite = "automation_requires_actor_write"
	triggerSkipReasonMissingActorLogin            = "missing_actor_login"
	triggerSkipReasonMissingAutomationOwner       = "missing_automation_owner"
)

func (h *Handler) ShouldIgnorePRCommentOrReview(ctx context.Context, pr isOpen, author *Actor) (bool, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	// Ignore events if the author is Agentic
	_, isAgenticActor := h.appProvider.IsAgenticActor(author)
	if isAgenticActor {
		logger.Info("Ignoring comment or review because the author is Agentic")
		return true, nil
	}

	// Ignore events if the author is a bot
	if strings.EqualFold(author.Type, "bot") {
		logger.Info("Ignoring comment or review because the author is a bot")
		return true, nil
	}

	// Ignore events for closed PRs
	if !pr.isOpen() {
		logger.Info("Ignoring comment or review because the PR is closed")
		return true, nil
	}

	return false, nil
}

func (h *Handler) PRCommentOrReviewAuthorHasPushPermissions(ctx context.Context, gh github.ClientInterface, repo *Repository, author *Actor) (bool, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	// Only process events where the actor has write access to the repo.
	hasPushPermissions, err := h.actorHasPushPermissionsForRepository(ctx, gh, repo.ID, author.Login)
	if err != nil {
		return false, err
	}
	if !hasPushPermissions {
		logger.Info("Ignoring comment or review because the author does not have write access to the repo")
		return false, nil
	}

	return true, nil
}

func (h *Handler) actorHasPushPermissionsForRepository(ctx context.Context, gh github.ClientInterface, repoID int64, actorLogin string) (bool, error) {
	permission, err := gh.GetUserPermissionsForRepositoryByID(ctx, repoID, actorLogin)
	if err != nil {
		return false, goerrors.Errorf("getting user permissions for repository: %w", err)
	}

	return permission.Push, nil
}

// appPermissionsForRepository reports the originating App's contents:write and
// workflows:write on the repository.
func (h *Handler) appPermissionsForRepository(ctx context.Context, appID, repoID int64) (contents, workflows bool, err error) {
	if appID <= 0 {
		return false, false, nil
	}
	perms, err := h.ghTwirp.GetInstallationPermissions(ctx, appID, repoID)
	if err != nil {
		return false, false, goerrors.Errorf("getting installation permissions for originating app: %w", err)
	}
	return perms["contents"] == "write", perms["workflows"] == "write", nil
}

// recordAppWorkflowsAccess returns &false when the originating
// App lacks workflows:write, otherwise nil — letting dotcom's secrets provider
// fall back to the actor-side check rather than overriding it from sweagentd.
func (h *Handler) recordAppWorkflowsAccess(ctx context.Context, ref sweagentd.RepositoryWithActor, workflows bool) *bool {
	if workflows || !h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentScopeGitTokenWorkflows, ref) {
		return nil
	}
	denied := false
	return &denied
}

// actorPermissionContext captures the per-event actor signals consumed by
// shouldSkipTriggerForActorPermissions. It is computed once per event so
// per-automation decisions do not repeat the GitHub permission lookup or
// the org policy RPC.
type actorPermissionContext struct {
	actorLogin              string
	hasPushPermissions      bool
	policyLookupFailed      bool
	allowReadAccessTriggers bool
}

// resolveActorPermissionContext gathers actor signals for an event once.
// The Twirp policy lookup is skipped when the actor already has write access,
// or when every matching automation requires actor write itself (in which case
// the org policy result would not be used).
func (h *Handler) resolveActorPermissionContext(
	ctx context.Context,
	gh github.ClientInterface,
	repo sweagentd.Repository,
	actorLogin string,
	runtimeConfigs []automations.RuntimeConfig,
) (actorPermissionContext, error) {
	actorCtx := actorPermissionContext{actorLogin: actorLogin}
	if actorLogin == "" {
		return actorCtx, nil
	}

	hasPushPermissions, err := h.actorHasPushPermissionsForRepository(ctx, gh, repo.GetRepositoryID(), actorLogin)
	if err != nil {
		return actorCtx, err
	}
	actorCtx.hasPushPermissions = hasPushPermissions
	if hasPushPermissions {
		return actorCtx, nil
	}

	anyAllowsRead := false
	for _, rc := range runtimeConfigs {
		if !rc.RequireActorWritePermission {
			anyAllowsRead = true
			break
		}
	}
	if !anyAllowsRead {
		return actorCtx, nil
	}

	// Read-access actor with at least one automation that may allow reads.
	// Consult the dotcom org+repo policy via the Rails Twirp handler, which
	// ANDs the two layers under "least permissive wins". If the call fails,
	// fall back to default-deny so we never accidentally relax enforcement.
	policy, err := h.ghTwirp.SweagentdAPI().GetEffectiveTriggerActorPolicy(ctx, &sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest{
		RepositoryId: uint64(repo.GetRepositoryID()),
	})
	if err != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).WithFields(
			kvp.Int64("owner_id", repo.GetOwnerID()),
			kvp.Int64("repo_id", repo.GetRepositoryID()),
		).Warn("failed to fetch trigger actor policy, falling back to default-deny")
		actorCtx.policyLookupFailed = true
		return actorCtx, nil
	}
	actorCtx.allowReadAccessTriggers = policy.GetAllowReadAccessTriggers()
	return actorCtx, nil
}

// shouldSkipTriggerForActorPermissions decides whether a single automation
// should be skipped for this event, given the precomputed actor context and
// the automation's RequireActorWritePermission flag. Performs no I/O.
func shouldSkipTriggerForActorPermissions(actorCtx actorPermissionContext, requireActorWritePermission bool) bool {
	if actorCtx.actorLogin == "" {
		return true
	}
	if actorCtx.hasPushPermissions {
		return false
	}
	if requireActorWritePermission {
		return true
	}
	if actorCtx.policyLookupFailed {
		return true
	}
	return !actorCtx.allowReadAccessTriggers
}

// filterConfigsByActorPermissions returns the subset of runtimeConfigs that
// pass the per-event actor-permission gate. For each blocked config it emits
// a "triggers.skipped" metric and a structured log line tagged with the
// automation_id so a per-config skip can be attributed back to its automation.
func (h *Handler) filterConfigsByActorPermissions(
	ctx context.Context,
	triggerTags stats.Tags,
	actorCtx actorPermissionContext,
	runtimeConfigs []automations.RuntimeConfig,
) []automations.RuntimeConfig {
	allowed := make([]automations.RuntimeConfig, 0, len(runtimeConfigs))
	for _, runtimeConfig := range runtimeConfigs {
		if !shouldSkipTriggerForActorPermissions(actorCtx, runtimeConfig.RequireActorWritePermission) {
			allowed = append(allowed, runtimeConfig)
			continue
		}
		skipReason := triggerSkipReasonActorPermissionPolicy
		skipMessage := "Ignoring trigger event because actor-permission policy requires write access"
		if actorCtx.actorLogin == "" {
			skipReason = triggerSkipReasonMissingActorLogin
			skipMessage = "Ignoring trigger event because actor login is missing and actor permissions cannot be verified"
		} else if runtimeConfig.RequireActorWritePermission {
			skipReason = triggerSkipReasonAutomationRequiresActorWrite
			skipMessage = "Ignoring trigger event because automation requires actor write access"
		}
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("trigger_type", triggerTags["trigger_type"]),
			kvp.String("actor_login", actorCtx.actorLogin),
			kvp.String("automation_id", runtimeConfig.AutomationID),
		).Info(skipMessage)
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": skipReason}))
	}
	return allowed
}

func (h *Handler) jobActorForRuntimeConfig(ctx context.Context, gh github.ClientInterface, repo sweagentd.Repository, runtimeConfig automations.RuntimeConfig, triggerTags stats.Tags) (*jobs.JobActor, bool, error) {
	if runtimeConfig.AutomationOwnerID == 0 {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("automation_id", runtimeConfig.AutomationID),
		).Warn("automation runtime config missing owner identity; skipping trigger job")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": triggerSkipReasonMissingAutomationOwner}))
		return nil, false, nil
	}

	user, err := gh.GetUserByID(ctx, uint64(runtimeConfig.AutomationOwnerID))
	if err != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).WithFields(
			kvp.String("automation_id", runtimeConfig.AutomationID),
			kvp.Int64("automation_owner_id", runtimeConfig.AutomationOwnerID),
		).Warn("failed to resolve automation owner login; skipping trigger job")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": triggerSkipReasonAutomationOwnerLookup}))
		return nil, false, nil
	}
	owner := jobs.JobActor{
		ID:    runtimeConfig.AutomationOwnerID,
		Login: user.GetLogin(),
	}
	if owner.Login == "" {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("automation_id", runtimeConfig.AutomationID),
			kvp.Int64("automation_owner_id", runtimeConfig.AutomationOwnerID),
		).Warn("automation owner login is empty; skipping trigger job")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": triggerSkipReasonAutomationOwnerLookup}))
		return nil, false, nil
	}

	hasPushPermissions, err := h.actorHasPushPermissionsForRepository(ctx, gh, repo.GetRepositoryID(), owner.Login)
	if err != nil {
		return nil, false, err
	}
	if !hasPushPermissions {
		h.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("automation_id", runtimeConfig.AutomationID),
			kvp.Int64("automation_owner_id", runtimeConfig.AutomationOwnerID),
			kvp.String("automation_owner_login", owner.Login),
		).Info("automation owner does not have write access to the repo; skipping trigger job")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": triggerSkipReasonAutomationOwnerWrite}))
		return nil, false, nil
	}

	jobActor, err := h.fillJobActorDetails(ctx, &owner)
	if err != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).WithFields(
			kvp.String("automation_id", runtimeConfig.AutomationID),
			kvp.Int64("automation_owner_id", runtimeConfig.AutomationOwnerID),
		).Warn("failed to fill automation owner actor details; skipping trigger job")
		h.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": triggerSkipReasonAutomationOwnerLookup}))
		return nil, false, nil
	}
	return jobActor, true, nil
}

func (h *Handler) dispatchTriggerJobs(
	ctx context.Context,
	triggerName string,
	triggerTags stats.Tags,
	runtimeConfigs []automations.RuntimeConfig,
	buildAndQueue func(runtimeConfig automations.RuntimeConfig) (bool, error),
) error {
	// Each iteration stamps the current custom agent into request context for
	// per-agent logs/metrics; clear it when done so later logs aren't attributed
	// to the last processed agent.
	clearCustomAgentFromRequestContext(ctx, h.obsv)
	defer clearCustomAgentFromRequestContext(ctx, h.obsv)

	for _, runtimeConfig := range runtimeConfigs {
		agent := runtimeConfig.CustomAgent
		addCustomAgentToRequestContext(ctx, h.obsv, agent)
		h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("trigger_name", triggerName)).
			Info("Building and queuing job for custom agent trigger event")

		queued, err := buildAndQueue(runtimeConfig)
		if err == nil {
			if !queued {
				continue
			}
			h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("trigger_name", triggerName)).
				Info("successfully built and queued job for trigger event")
			h.obsv.Increment(ctx, "triggers.job_queued", triggerTags)
			continue
		}

		h.obsv.LoggerWithTelemetry(ctx).WithError(err).WithFields(kvp.String("trigger_name", triggerName)).
			Error("failed to build or queue job for trigger event")
		h.obsv.Increment(ctx, "triggers.job_error", triggerTags)

		switch {
		case jobservice.IsBuilderFinalizedJobError(err):
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).WithFields(kvp.String("trigger_name", triggerName)).
				Info("job builder finalized error encountered, continuing to next agent")
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
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).WithFields(kvp.String("trigger_name", triggerName)).
				Info("rate limit error encountered, stopping processing of trigger event to retry later")
			return err
		default:
			h.obsv.LogAndReportError(ctx, err, "unexpected error building or queuing job for trigger event")
			continue
		}
	}

	return nil
}

// pullRequestResource creates an assignment resource for a pull request
func pullRequestResource(id int64) jobs.AssignmentResource {
	return jobs.AssignmentResource{
		Type: "pull_request",
		ID:   strconv.FormatInt(id, 10),
	}
}

func eventIdentifiers(ids ...int64) []string {
	strIDs := make([]string, 0, len(ids))
	for _, id := range ids {
		strIDs = append(strIDs, strconv.FormatInt(id, 10))
	}
	return strIDs
}

// preModelPicker is the Unix timestamp for 2025-12-08T00:00:00Z
// This avoids unexpected 3 PRU charges for follow-up comments on old assignments that were
// "locked" on Opus before the multiplier rollout. This code can be removed after a few weeks
// when this edge case becomes extremely rare.
var preModelPicker = time.Date(2025, 12, 8, 0, 0, 0, 0, time.UTC)

// shouldInheritModel determines if a job for the given assignment
// should inherit the model from the most recent job.
// Returns false if an explicit model was requested via @copilot+model syntax.
func shouldInheritModel(assignment *jobs.Assignment, mostRecentJob *jobs.Job, requestedModel string) bool {
	// Don't inherit if an explicit model was requested
	if requestedModel != "" {
		return false
	}

	if mostRecentJob == nil {
		return false
	}

	// Only inherit if there is a most recent model
	if mostRecentJob.Model == "" {
		return false
	}

	// Only inherit if the assignment was created after the model picker was introduced
	if time.Unix(assignment.CreatedAt, 0).Before(preModelPicker) {
		return false
	}

	return true
}
