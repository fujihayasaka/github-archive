package events

import (
	"context"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/telemetry"
)

// OnPullRequestStateChanged routes to the merged-trigger firing path on Worker (automationLookup wired) and to the job-cancellation path on Service.
func (h *Handler) OnPullRequestStateChanged(ctx context.Context, event PullRequestStateChangedEvent) error {
	if h.automationLookup != nil {
		return h.firePullRequestMergedTriggers(ctx, event)
	}
	return h.cancelJobsForPullRequestStateChange(ctx, event)
}

// cancelJobsForPullRequestStateChange cancels running jobs when a PR is closed or merged.
func (h *Handler) cancelJobsForPullRequestStateChange(ctx context.Context, event PullRequestStateChangedEvent) error {
	if event.PullRequest == nil || event.PullRequest.ID == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("pull request is required for state change event, skipping")
		return nil
	}

	if event.PullRequest.State == "" {
		h.obsv.LoggerWithTelemetry(ctx).Info("pull request state is required for state change event, skipping")
		return nil
	}

	// Only cancel jobs when PR is closed or merged
	if event.PullRequest.State != PullRequestStateClosed && event.PullRequest.State != PullRequestStateMerged {
		h.obsv.LoggerWithTelemetry(ctx).Info("pull request state is not closed or merged, skipping job cancellation")
		return nil
	}

	assignment, err := h.getAssignmentForPRDirect(ctx, event.Repo, &event.PullRequest.ID, &event.PullRequest.Number)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to get assignment for pull request")
		return nil
	}
	if assignment == nil {
		return nil
	}

	assignmentJobs, err := h.jobService.GetJobsForAssignment(ctx, assignment)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to get jobs by assignment")
		return nil
	}

	var runningJobs []*jobs.Job
	var mostRecentJob *jobs.Job
	for _, job := range assignmentJobs {
		if mostRecentJob == nil || job.CreatedAt > mostRecentJob.CreatedAt {
			mostRecentJob = job
		}
		if job.IsRunning() {
			runningJobs = append(runningJobs, job)
		}
	}

	// Publish a standard event for the most recent job in the assignment
	if mostRecentJob != nil {
		tp := telemetry.NewTelemetryPublisher(h.obsv, h.ghTwirp, h.ffClient)
		tp.PublishPullRequestStateChangedStandardEvent(ctx, mostRecentJob, event.PullRequest.State, event.Timestamp)
	}

	if len(runningJobs) == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("no running jobs to cancel for closed/merged PR")
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("cancelling running jobs for closed/merged PR")

	// Fall back to the job's AgentID when the PR author isn't an agent.
	agentID := event.AgentID
	if agentID == 0 {
		agentID = runningJobs[0].AgentID
	}

	app, err := h.appProvider.FindByID(ctx, agentID)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to find app for assignment job")
		return nil
	}

	ghClient, err := h.ghFactory.NewClientForRepo(ctx, app, runningJobs[0])
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to create GitHub client for job")
		return nil
	}

	repo, err := ghClient.GetRepositoryByID(ctx, assignment.RepoID)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to get repository associated with assignment")
		return nil
	}

	flagEnabled := h.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentSkipPRCloseCancel, event.Repo)

	for _, job := range runningJobs {
		if flagEnabled && h.shouldSkipPRCloseCancel(ctx, job.AgentID) {
			h.obsv.LoggerWithTelemetry(ctx).Info("skipping job cancel for closed/merged PR (app opted out)")
			h.obsv.Increment(ctx, "pull_request_state_change.skipped", nil)
			continue
		}
		h.obsv.LoggerWithTelemetry(ctx).Info("cancelling job for closed/merged PR")
		if err := h.jobExecutor.CancelJob(ctx, ghClient, job, repo.GetOwner().GetLogin(), repo.GetName()); err != nil {
			h.obsv.LogAndReportError(ctx, err, "failed to cancel job for closed/merged PR")
		} else {
			h.obsv.Increment(ctx, "pull_request_state_change.job_cancelled", nil)
		}
	}

	return nil
}

// shouldSkipPRCloseCancel reports whether the agentic app behind agentID has
// opted out of automatic job cancellation on PR close/merge via
// sweagentd.AgenticAppSkipPRCloseCancel. Missing apps and apps that don't
// implement the interface return false (preserve the default cancel
// behaviour).
func (h *Handler) shouldSkipPRCloseCancel(ctx context.Context, agentID int64) bool {
	app, err := h.appProvider.FindByID(ctx, agentID)
	if err != nil || app == nil {
		return false
	}
	skipper, ok := app.(sweagentd.AgenticAppSkipPRCloseCancel)
	return ok && skipper.SkipPRCloseCancel()
}
