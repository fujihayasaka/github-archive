package jobutils

import (
	"context"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
)

// AddReactionsForReview adds the 👀 reaction to the PR review and all of its comments.
func AddReactionsForReview(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, review *github.GQLPullRequestReview) error {
	// We add 👀 to the review only if the reviewer left a top-level comment when
	// submitting the review. Top-level comments appear in the UI similar to a "normal"
	// comments, but are not returned by the comments or review comments API endpoints.
	// The UI supports reactions on top-level comments, but the REST API does not. So we
	// use the GraphQL mutation instead.
	if (review.Commented() || review.ChangesRequested()) && review.Body != "" {
		err := review.AddReaction(ctx, gh, github.GQLReactionContentEyes)
		if err != nil {
			obsv.LogAndReportError(ctx, err, "failed to add reaction")
		}
	}

	// TODO(colbylwilliams):
	// Need to confirm, but I believe every PR review comment *reply* creates a new, separate
	// PR review. If this is the case, we can work under the assumption that every PR review
	// comment is authored by the author of the parent PR review. As such, we can just use
	// the review author when checking whether or not to include this comment in the job.
	for i := range review.Comments.Nodes {
		err := review.Comments.Nodes[i].AddReaction(ctx, gh, github.GQLReactionContentEyes)
		if err != nil {
			obsv.LogAndReportError(ctx, err, "failed to add reaction")
		}
	}

	return nil
}

// RemoveReactionsForJob removes the 👀 reaction from the PR comments, reviews and all their comments.
func RemoveReactionsForJob(
	ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, actx *github.PullRequestContext, job *jobs.Job, isAgentic agenticapp.IsAgenticFunc,
) {
	// currently we only will want to remove reactions for PR reviews and comments

	// Loop through the reviewIDs and remove the 👀 reaction from the review and all of its comments
	for _, reviewID := range job.ReviewIDs {
		for i := range actx.PullRequest.Reviews.Nodes {
			if actx.PullRequest.Reviews.Nodes[i].GetID() == reviewID {
				err := actx.PullRequest.Reviews.Nodes[i].RemoveReaction(ctx, gh, github.GQLReactionContentEyes, isAgentic)
				if err != nil {
					obsv.LogAndReportError(ctx, err, "failed to remove reaction")
				}

				for j := range actx.PullRequest.Reviews.Nodes[i].Comments.Nodes {
					err := actx.PullRequest.Reviews.Nodes[i].Comments.Nodes[j].RemoveReaction(ctx, gh, github.GQLReactionContentEyes, isAgentic)
					if err != nil {
						obsv.LogAndReportError(ctx, err, "failed to remove reaction")
					}
				}
			}
		}
	}

	// Loop through the commentIDs and remove the 👀 reaction from the comments
	for _, commentID := range job.CommentIDs {
		for i := range actx.PullRequest.Comments.Nodes {
			if actx.PullRequest.Comments.Nodes[i].GetID() == commentID {
				err := actx.PullRequest.Comments.Nodes[i].RemoveReaction(ctx, gh, github.GQLReactionContentEyes, isAgentic)
				if err != nil {
					obsv.LogAndReportError(ctx, err, "failed to remove reaction")
				}
			}
		}
	}
}
