package events

import (
	"context"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/jobs"
)

// OnPullRequestStateChanged handles pull request state change events (reopen, close, merge)
// and updates the ResourceState for all sessions associated with the pull request.
func (h *Handler) OnPullRequestStateChanged(ctx context.Context, event PullRequestStateChangedEvent) error {
	if event.PullRequest == nil || event.PullRequest.ID == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("pull request is required for state change event, skipping session update")
		return nil
	}

	if event.PullRequest.State == "" {
		h.obsv.LoggerWithTelemetry(ctx).Info("pull request state is required for state change event, skipping session update")
		return nil
	}

	var resourceState capi.ResourceState
	switch event.PullRequest.State {
	case PullRequestStateOpen:
		if event.PullRequest.IsDraft != nil && *event.PullRequest.IsDraft {
			resourceState = capi.ResourceStateDraft
		} else {
			resourceState = capi.ResourceStateOpen
		}
	case PullRequestStateClosed:
		resourceState = capi.ResourceStateClosed
	case PullRequestStateMerged:
		resourceState = capi.ResourceStateMerged
	default:
		h.obsv.LoggerWithTelemetry(ctx).Info("unknown PR state, skipping session update")
		return nil
	}

	assignment, err := h.jobsStore.GetAssignmentForPR(ctx, event.Repo.OwnerID, event.Repo.ID, &event.PullRequest.ID, &event.PullRequest.Number)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to get assignment for pull request")
		return nil
	}
	if assignment == nil {
		return nil
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("processing session updates for assignment")

	assignmentJobs, err := h.jobService.GetJobsForAssignment(ctx, assignment)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to get jobs by assignment")
		return nil
	}

	var patches []capi.SessionPatch
	for _, job := range assignmentJobs {
		if job.SessionID == "" {
			continue // Skip jobs without sessions
		}

		patches = append(patches, capi.SessionPatch{
			UserID:        uint64(job.ActorID),
			SessionID:     job.SessionID,
			ResourceState: string(resourceState),
		})
	}

	if len(patches) == 0 {
		h.obsv.LoggerWithTelemetry(ctx).Info("no sessions to update for assignment")
		return nil
	}

	token, err := tokens.GetUserToServerToken(ctx, h.ghTwirp.SweagentdAPI(), &event)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to get token for user")
		return nil
	}
	sessionClient := h.capiClient.NewSessionClient(event.Actor.ID, token)

	err = sessionClient.PatchSessions(ctx, patches)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to patch sessions")
		return nil
	}

	// Cancel running jobs when PR is closed or merged
	if event.PullRequest.State == PullRequestStateClosed || event.PullRequest.State == PullRequestStateMerged {
		var runningJobs []*jobs.Job
		for _, job := range assignmentJobs {
			if job.IsRunning() {
				runningJobs = append(runningJobs, job)
			}
		}

		h.obsv.LoggerWithTelemetry(ctx).Info("cancelling running jobs for closed/merged PR")

		// Confirm there are any running jobs before creating GitHub client to
		// avoid unnecessary token minting
		if len(runningJobs) == 0 {
			h.obsv.LoggerWithTelemetry(ctx).Info("no running jobs to cancel for closed/merged PR")
			return nil
		}

		// The owner/repository is the same for all jobs in the assignment, so we
		// can use the first job to create the GitHub client
		ghClient, err := h.ghFactory.NewClientForRepo(ctx, runningJobs[0])
		if err != nil {
			h.obsv.LogAndReportError(ctx, err, "failed to create GitHub client for job")
			return nil
		}

		for _, job := range runningJobs {
			h.obsv.LoggerWithTelemetry(ctx).Info("cancelling job for closed/merged PR")
			if err := h.jobExecutor.CancelJob(ctx, ghClient, job); err != nil {
				h.obsv.LogAndReportError(ctx, err, "failed to cancel job for closed/merged PR")
			}
		}
	}

	return nil
}
