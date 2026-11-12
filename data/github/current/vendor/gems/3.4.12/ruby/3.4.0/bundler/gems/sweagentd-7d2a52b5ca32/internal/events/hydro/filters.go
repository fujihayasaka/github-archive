package hydro

import (
	"context"
	"fmt"

	codescanningv0 "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	actionsv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/sweagentd"
)

// shouldEnvironmentDispatchEvent checks if the event applies to the current
// environment based on feature flag routing. It returns true if the event
// is flagged in to the current environment, false if not.
func (d *Dispatcher) shouldEnvironmentDispatchEvent(ctx context.Context, actors sweagentd.RepositoryWithActor) bool {
	actorID := actors.GetActorID()
	repositoryID := actors.GetRepositoryID()

	// FF checks in vexi are in memory and FAST, don't sweat these back to back calls.
	routeUserToStaging := d.ffClient.IsEnabledForUserOrRepo(ctx, "sweagentd_route_user_or_repo_to_staging", actorID, repositoryID)
	routeUserToStagingJediKnight := d.ffClient.IsEnabledForUserOrRepo(ctx, "sweagentd_route_user_or_repo_to_staging_jedi_knight", actorID, repositoryID)
	routeUserToStagingSithLord := d.ffClient.IsEnabledForUserOrRepo(ctx, "sweagentd_route_user_or_repo_to_staging_sith_lord", actorID, repositoryID)
	shouldRouteToAStagingEnvironment := routeUserToStaging || routeUserToStagingJediKnight || routeUserToStagingSithLord

	// We're in a staging environment, but we shouldn't be processing according to FFs
	if d.environment == config.EnvironmentStaging && !shouldRouteToAStagingEnvironment {
		return false
	}

	// We're NOT in a staging environment, but FFs indicate we should be routing to staging
	if d.environment != config.EnvironmentStaging && shouldRouteToAStagingEnvironment {
		return false
	}

	if d.environment == config.EnvironmentStaging && shouldRouteToAStagingEnvironment {
		// If we're still here, we're just making sure we match the right staging environment
		if routeUserToStaging && d.environmentName != "staging" {
			return false
		}
		if routeUserToStagingJediKnight && d.environmentName != "staging-jedi-knight" {
			return false
		}
		if routeUserToStagingSithLord && d.environmentName != "staging-sith-lord" {
			return false
		}
	}

	return true
}

// shouldProcessTopic checks if the hydro event should be processed based on
// the topic before unmarshaling the event payload. It returns true if the event
// should be processed, and false if it should be ignored.
func (d *Dispatcher) shouldProcessTopic(ctx context.Context, topic string) bool {
	// Check all cases here to ensure new types are intentionally added/handled.
	switch topic {
	case topics.IssueUpdateAssignee:
	case topics.PullRequestTimelineCommentCreate:
	case topics.PullRequestReviewSubmit:
	case topics.PullRequestReopen:
		return d.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentPRStateEventsEnabled)
	case topics.PullRequestClose:
		return d.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentPRStateEventsEnabled)
	case topics.PullRequestMerge:
		return d.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentPRStateEventsEnabled)
	case topics.ComputeUsage:
	case topics.WorkflowRunExecution:
	case topics.CodeScanningAlertAssignment:
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
// payload that we don't included in our event types (e.g. [events.IssueAssignmentEvent]).
func (d *Dispatcher) shouldProcessMessage(ctx context.Context, message any) bool {
	// Check all cases here to ensure new types are intentionally added/handled.
	switch m := message.(type) {
	case *githubv1.IssueUpdateAssignee:
	case *githubv1.PullRequestReviewSubmit:
	case *githubv1.PullRequestTimelineCommentCreate:
	case *githubv1.PullRequestReopen:
	case *githubv1.PullRequestClose:
	case *githubv1.PullRequestMerge:
	case *actionsv0.ComputeUsage:
		// We currently only care about "dynamic" workflow runs (i.e. those that
		// are triggered started by an API call)
		return m.InvokingEventType == "dynamic"
	case *actionsv0.WorkflowRunExecution:
		// TODO(colbylwilliams):
		// We're currently consuming two workflow event types:
		//  - ComputeUsage: published on completion of workflow *jobs*, and
		//  - WorkflowRunExecution: published on completion of workflow *runs*,
		//    (a collection of one or more workflow jobs)
		//
		// We will eventually migrate to only consuming the WorkflowRunExecution
		// event, but today we only use the WorkflowRunExecution event to handle
		// the (edge) case where the workflow run is cancelled or fails before
		// a workflow job is created (i.e. we never receive a ComputeUsage event).
		//
		// Check here for that edge case and return false otherwise.
		return m.Conclusion == "startup_failure"
	case *codescanningv0.AlertsAssignment:
	default:
		d.obsv.LoggerWithTelemetry(ctx).Error("unhandled hydro event message type")
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
	case *events.IssueAssignmentEvent:
		// Prevent duplicate job creation if user is enabled for enhanced issue assignment via Jobs API
		if e.Action == events.IssueAssignmentEventActionAssigned && d.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentIssuesCrossRepoAssignment, e.Actor.ID) {
			d.obsv.LoggerWithTelemetry(ctx).Info("Feature flag to prevent issue assigned event handling enabled")
			return false
		}
	case *events.PullRequestCommentCreatedEvent:
	case *events.PullRequestReviewSubmitEvent:
	case *events.PullRequestStateChangedEvent:
		// Only process events for PRs that Copilot (we) authored
		return e.PullRequest.HeadBranchHasPrefix(fmt.Sprintf("%s/", github.CopilotBranchPrefix))
	case *events.WorkflowRunCompletedEvent:
		// We currently only care about dynamic workflow runs created by our service
		return e.WorkflowRun.PathHasPrefix("dynamic/copilot-swe-agent/")
	case *events.CodeScanningAlertsAssignmentEvent:
	default:
		d.obsv.LoggerWithTelemetry(ctx).Error("unhandled event type")
		return false
	}

	// We recognize the event type and didn't conditionally ignore it
	return true
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
	switch event.(type) {
	case *events.IssueAssignmentEvent:
	case *events.PullRequestCommentCreatedEvent:
	case *events.PullRequestReviewSubmitEvent:
	case *events.PullRequestStateChangedEvent:
		return false // We don't check enablement for PR state changes
	case *events.WorkflowRunCompletedEvent:
		// The user in this event is actually Copilot, not the user that triggered
		// the workflow run. We do however still need to check if the repo is
		// enabled because we may start pending jobs as a result of this event.
	case *events.CodeScanningAlertsAssignmentEvent:
	default:
		d.obsv.LoggerWithTelemetry(ctx).Error("unhandled event type for enablement check")
		// We should never reach this point, but if we do, we err on the side of
		// caution and assume we need to check enablement.
		return true
	}

	return true
}
