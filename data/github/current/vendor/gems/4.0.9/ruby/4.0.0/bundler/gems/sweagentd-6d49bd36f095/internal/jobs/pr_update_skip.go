package jobs

import (
	"context"

	"github.com/github/sweagentd/internal/featureflags"
)

// ShouldSkipMidSessionPRUpdate reports whether an intermediate PR title/body
// update should be skipped for the given job.
//
// Mid-session updates are issued repeatedly while the agent is running:
//   - the agent callback partial-result path, and
//   - the runtime report_progress side-effect.
//
// Skipping is centralised here so that every mid-session updater behaves
// consistently. We skip when:
//   - the job is acting on a pull request that was not authored by an agentic
//     actor (the EventType variants ending in NonCopilotPullRequest), or
//   - the job is a subsequent action on an existing PR (fix-pr-comment) and
//     CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs is enabled, or
//   - the job is fixing a failed workflow run and
//     CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs is enabled, or
//   - the job is fixing a Copilot code review finding and
//     CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs is enabled, or
//   - the job was triggered by a pull request event (opened/synchronize) and
//     CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs is enabled.
func ShouldSkipMidSessionPRUpdate(ctx context.Context, ff featureflags.Client, job *Job) bool {
	if job == nil {
		return false
	}

	if job.EventType == EventTypePullRequestCommentNonCopilotPullRequest ||
		job.EventType == EventTypePullRequestReviewNonCopilotPullRequest {
		return true
	}

	if job.Action == AgentActionFixPRComment &&
		ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs, job) {
		return true
	}

	return shouldSkipPRUpdateForExistingPREvent(ctx, ff, job)
}

// ShouldSkipPostSessionPRUpdate reports whether the final PR title/body update
// should be skipped for the given job.
//
// Post-session updates run once when the agent reports its terminal result via
// the agent callback or when sessions-v2 emits a final pr_summary side-effect.
// They preserve the title/body the agent left at the end of the run, so the only
// reason to skip is when we never want this kind of job to touch the PR (today:
// fixing a failed workflow run or code review finding on an existing PR, gated
// on event-specific feature flags).
func ShouldSkipPostSessionPRUpdate(ctx context.Context, ff featureflags.Client, job *Job) bool {
	if job == nil {
		return false
	}
	return shouldSkipPRUpdateForExistingPREvent(ctx, ff, job)
}

func shouldSkipPRUpdateForExistingPREvent(ctx context.Context, ff featureflags.Client, job *Job) bool {
	if ff == nil {
		return false
	}

	switch job.EventType {
	case EventTypeFixFailedWorkflow:
		return ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs, job)
	case EventTypeCodeReviewFixWithCopilot:
		return ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs, job)
	case EventTypePullRequestOpened, EventTypePullRequestSynchronize:
		return ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs, job)
	default:
		return false
	}
}
