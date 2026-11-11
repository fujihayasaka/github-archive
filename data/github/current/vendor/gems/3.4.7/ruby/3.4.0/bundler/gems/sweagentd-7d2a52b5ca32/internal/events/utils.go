package events

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
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

	// Ignore events if the author is Copilot
	isCopilot := h.ghFactory.UserIsCopilot(author.Login)
	if h.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgenticAppsProvider, author.GetActorID()) {
		isCopilot = h.appProvider.IsAgenticActor(author)
	}

	if isCopilot {
		logger.Info("Ignoring comment or review because the author is Copilot")
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

// issueResource creates an assignment resource for an issue
func issueResource(id int64) jobs.AssignmentResource {
	return jobs.AssignmentResource{
		Type: "issue",
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
