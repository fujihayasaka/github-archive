package events

import (
	"context"
	"fmt"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/limiter"
)

func (h *Handler) OnIssueUnassigned(ctx context.Context, event IssueAssignmentEvent) error {
	// Determine if this event should be ignored: use singular Assignee if feature flag enabled, otherwise legacy slice logic
	var ignoreEvent bool
	// Feature flag enabled: use singular Assignee if present; fallback to legacy slice if empty
	if event.Assignee != "" {
		// Ignore if removed user is not Copilot
		ignoreEvent = !h.ghFactory.UserIsCopilot(event.Assignee)
	} else {
		h.obsv.LoggerWithTelemetry(ctx).Warn("empty Assignee field; falling back to Assignees slice")
		ignoreEvent = h.ghFactory.ContainsCopilotUser(event.Assignees)
	}
	if ignoreEvent {
		return nil
	}

	repo := event.Repo
	issue := event.Issue

	assignment, err := h.getAssignmentForIssue(ctx, repo.OwnerID, repo.ID, issue.ID)
	if err != nil {
		return fmt.Errorf("getting assignment: %w", err)
	}

	// If we don't have an active assignment, then the bot was never assigned.
	if assignment == nil {
		return nil
	}

	gh, err := h.ghFactory.NewClientForRepo(ctx, &event)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	err = h.onIssueUnassigned(ctx, gh, assignment, event)
	if err != nil {
		if limiter.IsAnyRateLimitError(err) {
			return err
		}
		// TODO: (colbylwilliams) determine if we still need this
		return jobutils.NewUnhandledErrorWithIssueComment(ctx, err, assignment, false, event.Actor.Login, issue.Number)
	}
	return nil
}

func (h *Handler) onIssueUnassigned(ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, event IssueAssignmentEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onIssueUnassigned")
	defer span.End()

	issue := event.Issue

	// If we have an active assignment, we can assume that the bot was unassigned.
	// so we can just mark the assignment as inactive and remove the reaction.
	if err := h.jobsStore.DetachAssignmentResources(ctx, assignment); err != nil {
		return fmt.Errorf("failed to patch assignment: %w", err)
	}

	if err := gh.RemoveReactionFromIssue(ctx, assignment.RepoOwner, assignment.RepoName, issue.Number); err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to remove reaction")
	}

	return nil
}
