package hydro

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	codescanningv0 "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	automationsv0 "github.com/github/hydro-schemas-go/hydro/schemas/copilot_mission_control/v0"
	actionsv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	pull_requestsv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/pull_requests/v1"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/sweagentd"
)

// shouldEnvironmentDispatchEvent checks if the event applies to the current
// environment based on feature flag routing. It returns true if the event
// is flagged in to the current environment, false if not.
func (d *Dispatcher) shouldEnvironmentDispatchEvent(ctx context.Context, actors sweagentd.RepositoryWithActor) bool {
	// FF checks in vexi are in memory and FAST, don't sweat these back to back calls.
	// Use IsEnabledForUserOrRepoOrOwner to also check the repository owner (user or org),
	// ensuring both user-owned and org-owned repos are correctly routed when the FF is enabled on the owner.
	routeUserToStaging := d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_route_user_or_repo_to_staging", actors)
	routeUserToStagingJediKnight := d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_route_user_or_repo_to_staging_jedi_knight", actors)
	routeUserToStagingSithLord := d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_route_user_or_repo_to_staging_sith_lord", actors)
	routeUserToStagingBabyYoda := d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_route_user_or_repo_to_staging_baby_yoda", actors)
	shouldRouteToAStagingEnvironment := routeUserToStaging || routeUserToStagingJediKnight || routeUserToStagingSithLord || routeUserToStagingBabyYoda

	// We're in a staging environment, but we shouldn't be processing according to FFs
	if d.environment == config.EnvironmentStaging && !shouldRouteToAStagingEnvironment {
		return false
	}

	// We're NOT in a staging environment, but FFs indicate we should be routing to staging
	if d.environment != config.EnvironmentStaging && shouldRouteToAStagingEnvironment {
		return false
	}

	if d.environment == config.EnvironmentStaging && shouldRouteToAStagingEnvironment {
		// When multiple flags are enabled simultaneously, we use a priority order
		// to ensure exactly one staging environment processes the event:
		// We can use any order, but just picked alphabetical order here for simplicity:
		//   staging > staging-jedi-knight > staging-sith-lord > staging-baby-yoda
		targetEnvironment := ""
		switch {
		case routeUserToStaging:
			targetEnvironment = "staging"
		case routeUserToStagingJediKnight:
			targetEnvironment = "staging-jedi-knight"
		case routeUserToStagingSithLord:
			targetEnvironment = "staging-sith-lord"
		case routeUserToStagingBabyYoda:
			targetEnvironment = "staging-baby-yoda"
		}
		return d.environmentName == targetEnvironment
	}

	return true
}

// shouldProcessTopic checks if the hydro event should be processed based on
// the topic before unmarshaling the event payload. It returns true if the event
// should be processed, and false if it should be ignored.
func (d *Dispatcher) shouldProcessTopic(ctx context.Context, topic string) bool {
	// Check all cases here to ensure new types are intentionally added/handled.
	switch topic {
	case topics.PullRequestTimelineCommentCreate:
	case topics.PullRequestReviewSubmit:
	case topics.PullRequestClose:
	case topics.PullRequestMerge:
	case topics.WorkflowRunExecution:
	case topics.CodeScanningAlertAssignment:
	case topics.IssueCreateTemplate:
	case topics.PullRequestCreate:
	case topics.PullRequestMergeConflict:
	case topics.PullRequestSynchronize:
	case topics.AutomationRunRequested:
	default:
		d.obsv.LoggerWithTelemetry(ctx).Error("unhandled hydro event topic")
		return false
	}

	// We recognize the topic and didn't conditionally ignore it
	return true
}

// shouldProcessMessage checks if the hydro event message (payload) should be
// processed or ignored. It returns true if we should continue processing the
// message, and false if we should ignore it.
// This is used to filter out messages that we don't care about before processing
// them further using the actual hydro message payload.
//
// NOTE: Only add conditions here that use field values on the hydro event
// payload that we don't included in our event types (e.g. [events.PullRequestCommentCreatedEvent]).
func (d *Dispatcher) shouldProcessMessage(ctx context.Context, message any) bool {
	// Check all cases here to ensure new types are intentionally added/handled.
	switch m := message.(type) {
	case *githubv1.PullRequestReviewSubmit:
	case *githubv1.PullRequestTimelineCommentCreate:
	case *githubv1.PullRequestClose:
	case *githubv1.PullRequestMerge:
	case *actionsv0.WorkflowRunExecution:
	case *codescanningv0.AlertsAssignment:
	case *githubv1.IssueCreateTemplate:
	case *githubv1.PullRequestCreate:
	case *githubv1.PullRequestSynchronize:
	case *pull_requestsv1.MergeConflict:
	case *automationsv0.AutomationRunRequested:
	default:
		d.obsv.LoggerWithTelemetry(ctx).Error("unhandled hydro event message type",
			kvp.String("message_type", fmt.Sprintf("%T", m)))
		return false
	}

	// We recognize the message type and didn't conditionally ignore it
	return true
}

// shouldProcessEvent checks event should be processed based on our event object.
// It returns true if the event should be processed, and false if it should be
// ignored.
//
// This is used to filter out events that we don't care about before processing
// them further. This is useful for performance reasons, as it avoids minting
// tokens and performing unnecessary API calls for events that we don't care about.
func (d *Dispatcher) shouldProcessEvent(ctx context.Context, event any) bool {
	// Check all cases here to ensure new types are intentionally added/handled.
	switch e := event.(type) {
	case *events.PullRequestCommentCreatedEvent:
		return e.GetAgentID() != 0

	case *events.PullRequestReviewSubmitEvent:
		return e.GetAgentID() != 0

	case *events.PullRequestStateChangedEvent:
		if d.canProcessTriggers() {
			return d.shouldProcessPullRequestMergedTriggerEvent(ctx, e)
		}
		if e.GetAgentID() != 0 {
			return true
		}
		// Fall back to checking for an existing assignment when the PR
		// author isn't an agent.
		if !d.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentPRStateChangeAssignmentCheck, e) {
			return false
		}
		hasAssignment, err := d.eventHandler.HasAssignmentForPR(ctx, e.GetOwnerID(), e.GetRepositoryID(), e.PullRequest)
		if err != nil {
			d.obsv.LogAndReportError(ctx, err, "failed to check PR assignment in store")
			return false
		}
		return hasAssignment

	case *events.WorkflowRunCompletedEvent:
		if e.IsAgentCompletion() {
			// Agent run completions are processed by the service, not the
			// worker. The worker (which can process triggers) should skip these.
			if d.canProcessTriggers() {
				return false
			}
			return e.GetAgentID() != 0
		}
		// Non-agent workflow runs: check for workflow_run automations (worker only).
		// Cheap checks run first to short-circuit before the lookup.
		if e.GetAgentID() == 0 {
			return false
		}
		if !d.canProcessTriggers() {
			return false
		}
		hasTriggers, err := d.automationLookup.HasActiveForEvent(ctx, automations.EventMatchRequest{
			OwnerID:            e.GetOwnerID(),
			RepoID:             e.GetRepositoryID(),
			EventName:          automations.EventWorkflowRun,
			ActivityType:       automations.ActivityWorkflowRunFailed,
			WorkflowConclusion: automations.WorkflowConclusion(e.WorkflowRun.Conclusion),
		})
		if err != nil {
			d.obsv.LogAndReportError(ctx, err, "failed to check workflow run triggers in store")
			return false
		}
		return hasTriggers

	case *events.CodeScanningAlertsAssignmentEvent:
		return e.GetAgentID() != 0

	case *events.IssueCreatedEvent:
		// Automation trigger events are filtered by the automation lookup. Cheap
		// checks (agent ID, feature flag, nil lookup) run first to short-circuit
		// before the backing implementation does any store/API work.
		if e.GetAgentID() == 0 {
			return false
		}
		if !d.canProcessTriggers() {
			return false
		}
		if !d.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentIssueOpenedTrigger, e) {
			return false
		}
		hasTriggers, err := d.automationLookup.HasActiveForEvent(ctx, automations.EventMatchRequest{
			OwnerID:      e.GetOwnerID(),
			RepoID:       e.GetRepositoryID(),
			EventName:    automations.EventIssues,
			ActivityType: automations.ActivityIssueOpened,
		})
		if err != nil {
			// TODO: Reconsider whether store lookup errors should be retriable
			// instead of dropping the event. For now, log and skip to avoid
			// reprocessing loops while we work out trigger reliability.
			d.obsv.LogAndReportError(ctx, err, "failed to check triggers in store")
			return false
		}
		return hasTriggers

	case *events.PullRequestOpenedEvent:
		if e.GetAgentID() == 0 {
			return false
		}
		if !d.canProcessTriggers() {
			return false
		}
		// Per-event FF enables independent rollout from other trigger families.
		if !d.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentPullRequestOpenedTrigger, e) {
			return false
		}
		// Skip fork PRs: untrusted contributors should not trigger automated agent runs.
		if e.IsFromFork() {
			return false
		}
		hasTriggers, err := d.automationLookup.HasActiveForEvent(ctx, automations.EventMatchRequest{
			OwnerID:      e.GetOwnerID(),
			RepoID:       e.GetRepositoryID(),
			EventName:    automations.EventPullRequest,
			ActivityType: automations.ActivityPullRequestOpened,
		})
		if err != nil {
			d.obsv.LogAndReportError(ctx, err, "failed to check pull_request triggers in store")
			return false
		}
		return hasTriggers

	case *events.MergeConflictEvent:
		if e.GetAgentID() == 0 {
			return false
		}
		if !d.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentMergeConflictTrigger, e.GetRepositoryID()) {
			return false
		}
		return true

	case *events.AutomationRunRequestedEvent:
		repo := &sweagentd.RepositoryAdapter{RepoID: e.GetRepositoryID(), OwnerID: e.GetOwnerID()}
		if e.Event == string(automations.EventManual) &&
			!d.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentTriggersDisableManual, repo) {
			return false
		}
		// CMC already validated auth, repo access, and automation state before
		// publishing the Hydro event.
		return true

	case *events.PullRequestSynchronizeEvent:
		if e.GetAgentID() == 0 {
			return false
		}
		if !d.canProcessTriggers() {
			return false
		}
		if !d.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentPullRequestSynchronizeTrigger, e) {
			return false
		}
		// Fork status can't be computed here: the synchronize proto carries no head-repo signal, so the handler checks it after hydrating the PR.
		hasTriggers, err := d.automationLookup.HasActiveForEvent(ctx, automations.EventMatchRequest{
			OwnerID:      e.GetOwnerID(),
			RepoID:       e.GetRepositoryID(),
			EventName:    automations.EventPullRequest,
			ActivityType: automations.ActivityPullRequestSynchronize,
		})
		if err != nil {
			d.obsv.LogAndReportError(ctx, err, "failed to check pull_request.synchronize triggers in store")
			return false
		}
		return hasTriggers

	default:
		d.obsv.LoggerWithTelemetry(ctx).Error("unhandled event type")
		return false
	}
}

// shouldCheckActorEnablement checks if the event type requires a check to
// determine if the actor/repo is enabled for our service.
//
//   - Events triggered by a user that result in our service doing work on behalf
//     of that user (e.g. assigning an issue, creating a comment/review, etc.) require
//     the enablement check to ensure the user/repo is allowed to use our service.
//   - Events that we subscribe to in order to update our internal state (e.g. pull
//     request state changes) do not require the enablement check.
func (d *Dispatcher) shouldCheckActorEnablement(ctx context.Context, event any) bool {
	// Check all cases here to ensure new types are intentionally added/handled.
	switch e := event.(type) {
	case *events.PullRequestCommentCreatedEvent:
		_ = e // used by type switch
	case *events.PullRequestReviewSubmitEvent:
	case *events.PullRequestStateChangedEvent:
		if d.canProcessTriggers() {
			// Worker fires pull_request.merged triggers; PR author may lack Copilot access, but repo enablement is still required.
			break
		}
		return false // Service path: no enablement check for cancellation.
	case *events.WorkflowRunCompletedEvent:
		if !e.IsAgentCompletion() {
			// For workflow_run trigger events, check enablement to verify
			// the repo is enabled for the agent, similar to issue triggers.
			break
		}
		// The user in this event is actually Copilot, not the user that triggered
		// the workflow run. We do however still need to check if the repo is
		// enabled because we may start pending jobs as a result of this event.
	case *events.CodeScanningAlertsAssignmentEvent:
	case *events.IssueCreatedEvent:
		// For custom agent trigger events, the actor may not have Copilot
		// access themselves. We've already verified the repo has trigger-
		// configured agents in shouldProcessEvent, so we still check
		// enablement to verify the repo itself is enabled for the agent.
	case *events.PullRequestOpenedEvent:
		// PR author may lack Copilot access; repo enablement is still required.
	case *events.PullRequestSynchronizeEvent:
		// Push actor may lack Copilot access; repo enablement is still required.
	case *events.MergeConflictEvent:
		// Merge conflict events have no actor. We still check enablement
		// to verify the repo is enabled for the agent.
	case *events.AutomationRunRequestedEvent:
		// CMC already validated user auth, repo access, and automation state.
		// No additional enablement check needed.
		return false
	default:
		d.obsv.LoggerWithTelemetry(ctx).Error("unhandled event type for enablement check")
		// We should never reach this point, but if we do, we err on the side of
		// caution and assume we need to check enablement.
		return true
	}

	return true
}

// shouldProcessPullRequestMergedTriggerEvent gates Worker-side pull_request.merged trigger processing (Service cancellation is unaffected).
func (d *Dispatcher) shouldProcessPullRequestMergedTriggerEvent(ctx context.Context, e *events.PullRequestStateChangedEvent) bool {
	if e.PullRequest == nil || e.PullRequest.State != events.PullRequestStateMerged {
		return false
	}
	if !d.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentPullRequestMergedTrigger, e) {
		return false
	}
	// Skip merges where the PR author is an agentic bot to prevent agent → merge → agent loops.
	if d.appProvider != nil {
		if _, ok := d.appProvider.LookupBotID(e.PullRequest.AuthorID); ok {
			return false
		}
	}
	hasTriggers, err := d.automationLookup.HasActiveForEvent(ctx, automations.EventMatchRequest{
		OwnerID:      e.GetOwnerID(),
		RepoID:       e.GetRepositoryID(),
		EventName:    automations.EventPullRequest,
		ActivityType: automations.ActivityPullRequestMerged,
	})
	if err != nil {
		d.obsv.LogAndReportError(ctx, err, "failed to check pull_request.merged triggers in store")
		return false
	}
	return hasTriggers
}
