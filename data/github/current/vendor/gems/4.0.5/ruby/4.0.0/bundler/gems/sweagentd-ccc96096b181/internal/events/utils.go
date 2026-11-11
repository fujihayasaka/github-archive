package events

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
)

type isOpen interface {
	isOpen() bool
}

func (h *Handler) ShouldIgnorePRCommentOrReview(ctx context.Context, pr isOpen, author *Actor) (bool, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	// Ignore events for closed PRs
	if !pr.isOpen() {
		logger.Info("Ignoring comment or review because the PR is closed")
		return true, nil
	}

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

	return false, nil
}

func (h *Handler) PRCommentOrReviewAuthorHasPushPermissions(ctx context.Context, gh github.ClientInterface, repo *Repository, author *Actor) (bool, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	// Only process events where the actor has write access to the repo
	permission, err := gh.GetUserPermissionsForRepositoryByID(ctx, repo.ID, author.Login)
	if err != nil {
		return false, fmt.Errorf("getting user permissions for repository: %w", err)
	}
	if !permission.Push {
		logger.Info("Ignoring comment or review because the author does not have write access to the repo")
		return false, nil
	}

	return true, nil
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
