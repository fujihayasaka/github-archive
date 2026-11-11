package problemstatement

import (
	"container/list"
	"context"
	"fmt"
	"slices"
	"strings"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/tips"
)

// reviewBuilder creates a problem statement for a stacked PR triggered by a review comment reply.
// It focuses on the specific review thread context instead of the full PR context.
type reviewBuilder struct {
	obsv           observability.Exporters
	gh             github.CopilotUserChecker
	actx           *github.PullRequestContext
	job            *jobs.Job
	reviewID       int64
	authorResolver AuthorResolver
}

var _ ProblemStatementBuilder = &reviewBuilder{}

// NewReviewBuilder creates a problem statement builder focused on a specific review thread.
// This is used for stacked PRs that are created in response to a review comment reply.
func NewReviewBuilder(obsv observability.Exporters, gh github.CopilotUserChecker, actx *github.PullRequestContext, job *jobs.Job, reviewID int64, authorResolver AuthorResolver) ProblemStatementBuilder {
	return &reviewBuilder{
		obsv:           obsv,
		gh:             gh,
		actx:           actx,
		job:            job,
		reviewID:       reviewID,
		authorResolver: authorResolver,
	}
}

func (b *reviewBuilder) Build(ctx context.Context) (jobs.ProblemStatement, error) {
	setCtxProblemStatement(ctx, b.obsv, &requestctx.CtxProblemStatement{Source: "review_reply"})

	pr := b.actx.PullRequest

	// Find the review that triggered this
	review := pr.ReviewByID(b.reviewID)
	if review == nil {
		return jobs.ProblemStatement{}, fmt.Errorf("review with ID %d not found", b.reviewID)
	}

	var sb strings.Builder

	// Write header with a brief description
	b.writeHeader(&sb)

	// Write the specific review thread context
	if err := b.writeReviewThread(ctx, &sb, review); err != nil {
		return jobs.ProblemStatement{}, err
	}

	// Write footer
	b.writeFooter(&sb, pr.Commits.TotalCount)

	result, _, resultBase64Length := formattedProblemStatement(ctx, b.obsv, &sb)

	// If the problem statement exceeds the max size, truncate the review comment bodies
	if resultBase64Length > MaxProblemStatementBase64EncodedLength {
		setCtxProblemStatementCommentsTruncated(ctx, b.obsv)
		b.obsv.LoggerWithTelemetry(ctx).Info("problem statement exceeds maximum size, truncating review comments")
		sb.Reset()

		b.writeHeader(&sb)
		if err := b.writeReviewThreadTruncated(ctx, &sb, review, MaxTruncatedCommentBodyLength); err != nil {
			return jobs.ProblemStatement{}, err
		}
		b.writeFooter(&sb, pr.Commits.TotalCount)

		result, _, _ = formattedProblemStatement(ctx, b.obsv, &sb)
	}

	return jobs.ProblemStatement{Content: result, CommitCount: b.actx.PullRequest.Commits.TotalCount, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
}

func (b *reviewBuilder) writeHeader(sb *strings.Builder) {
	// Use the stacked PR title and description from job features.
	// For review-triggered stacked PRs, these are always set by the features builder.
	title := b.job.Features.PullRequest.TitlePlaceholder
	body := b.job.Features.PullRequest.BodyPlaceholder

	newLine(sb)
	sb.WriteString(SectionSeparator)
	sb.WriteString(StackedPullRequestSectionHeader)
	newLine(sb)

	openXMLTag(sb, XMLPRTitle)
	sb.WriteString(title)
	closeXMLTag(sb, XMLPRTitle)

	openXMLTag(sb, XMLPRDescription)

	body = tips.RemoveTips(body)
	sb.WriteString(body)
	closeXMLTag(sb, XMLPRDescription)
	newLine(sb)

	sb.WriteString(SectionSeparator)
	// Add context about what triggered this stacked PR
	sb.WriteString("This stacked PR was created to address a specific review comment on a different pull request.\n")
	sb.WriteString("Focus on addressing the feedback in the review thread below.\n")
	newLine(sb)
}

func (b *reviewBuilder) writeReviewThread(ctx context.Context, sb *strings.Builder, review *github.GQLPullRequestReview) error {
	return b.writeReviewThreadWithMaxLength(ctx, sb, review, 0)
}

func (b *reviewBuilder) writeReviewThreadTruncated(ctx context.Context, sb *strings.Builder, review *github.GQLPullRequestReview, maxCommentBodyLength int) error {
	return b.writeReviewThreadWithMaxLength(ctx, sb, review, maxCommentBodyLength)
}

func (b *reviewBuilder) writeReviewThreadWithMaxLength(ctx context.Context, sb *strings.Builder, review *github.GQLPullRequestReview, maxCommentBodyLength int) error {
	sb.WriteString(PullRequestCommentsHeading)
	openXMLTag(sb, XMLComments)

	// Build the resolved map once for O(1) lookups
	resolvedMap := b.actx.PullRequest.GetReviewThreadResolvedMap()

	// If this is a review comment reply, we need to show the entire thread
	if review.IsReviewCommentReply() {
		replyComment := &review.Comments.Nodes[0]

		// Find the root comment by traversing up the reply chain
		rootComment := b.findRootComment(replyComment)
		if rootComment == nil {
			return fmt.Errorf("could not find root comment for reply")
		}

		// Collect all comments in the thread (root + all replies)
		threadComments := b.collectThreadComments(rootComment)
		// Build the full thread by finding the root comment and all replies
		if err := b.writeReviewCommentThreadWithComments(ctx, sb, rootComment, threadComments, maxCommentBodyLength, resolvedMap); err != nil {
			return err
		}
	} else {
		// This is a top-level review
		// Check if the review body mentions @copilot
		reviewBodyMentionsCopilot := github.DoesMentionCopilot(review.GetBody())

		// Write the review body if present
		reviewComment, err := pullRequestReview(ctx, review, b.gh, b.job, b.authorResolver)
		if err != nil {
			return fmt.Errorf("failed to build review comment: %w", err)
		}

		if reviewComment != nil {
			reviewComment.Body = Truncate(reviewComment.Body, maxCommentBodyLength)
			if err := writeXML(sb, reviewComment); err != nil {
				return err
			}
		}

		// Include all inline comments from the review with their full threads
		// Group comments by their root thread to avoid duplicates
		threadsByRoot := b.groupCommentsByRootThread(review)

		for rootComment, threadComments := range threadsByRoot {
			// If the top review body mentions @copilot, include all inline comments
			// Otherwise, only include threads where @copilot is mentioned
			threadMentionsCopilot := reviewBodyMentionsCopilot
			if !threadMentionsCopilot {
				// Check if any comment in this thread mentions @copilot
				for _, comment := range threadComments {
					if github.DoesMentionCopilot(comment.GetBody()) {
						threadMentionsCopilot = true
						break
					}
				}
			}

			if threadMentionsCopilot {
				// Write the entire thread
				if err := b.writeReviewCommentThreadWithComments(ctx, sb, rootComment, threadComments, maxCommentBodyLength, resolvedMap); err != nil {
					return err
				}
			}
		}
	}

	closeXMLTag(sb, XMLComments)
	newLine(sb)

	return nil
}

// Iteratively traverse up the reply chain to find the root comment
func (b *reviewBuilder) findRootComment(comment *github.GQLPullRequestReviewComment) *github.GQLPullRequestReviewComment {
	current := comment

	for current.ReplyTo != nil {
		// Search through all reviews to find the parent comment
		found := false
		for _, review := range b.actx.PullRequest.Reviews.Nodes {
			for i := range review.Comments.Nodes {
				reviewComment := &review.Comments.Nodes[i]
				// Found the comment that this one is replying to
				if reviewComment.GetID() == current.ReplyTo.GetID() {
					current = reviewComment
					found = true
					break
				}
			}
			if found {
				break
			}
		}

		// If we can't find the parent, treat current as the root
		if !found {
			break
		}
	}

	return current
}

func (b *reviewBuilder) collectThreadComments(rootComment *github.GQLPullRequestReviewComment) []*github.GQLPullRequestReviewComment {
	result := []*github.GQLPullRequestReviewComment{rootComment}

	// Use a queue to iteratively collect all replies in the thread
	// This avoids potential stack overflow from deep comment threads
	queue := list.New()
	queue.PushBack(rootComment.GetID())

	for queue.Len() > 0 {
		parentID := queue.Remove(queue.Front()).(int64)

		// Find all direct replies to this parent
		for _, review := range b.actx.PullRequest.Reviews.Nodes {
			for i := range review.Comments.Nodes {
				comment := &review.Comments.Nodes[i]
				if comment.ReplyTo != nil && comment.ReplyTo.GetID() == parentID {
					result = append(result, comment)
					// Add this comment's ID to the queue to find its replies
					queue.PushBack(comment.GetID())
				}
			}
		}
	}

	// Sort by timestamp to maintain chronological order
	slices.SortStableFunc(result, pullRequestReviewCommentSortFunc)

	return result
}

func (b *reviewBuilder) writeFooter(sb *strings.Builder, commitCount int) {
	sb.WriteString(SectionSeparator)
	if commitCount > 0 {
		sb.WriteString(commitNote(commitCount))
	}
}

// groupCommentsByRootThread groups review comments by their root comment.
// Returns a map where the key is the root comment and the value is a slice of all comments in that thread (including the root).
func (b *reviewBuilder) groupCommentsByRootThread(review *github.GQLPullRequestReview) map[*github.GQLPullRequestReviewComment][]*github.GQLPullRequestReviewComment {
	result := make(map[*github.GQLPullRequestReviewComment][]*github.GQLPullRequestReviewComment)
	processed := make(map[int64]bool)

	// Process each comment in the review
	for i := range review.Comments.Nodes {
		comment := &review.Comments.Nodes[i]

		// Skip if we've already processed this comment as part of another thread
		if processed[comment.GetID()] {
			continue
		}

		// Find the root comment for this thread
		rootComment := b.findRootComment(comment)

		// Skip if we've already processed this root's thread
		if processed[rootComment.GetID()] {
			processed[comment.GetID()] = true
			continue
		}

		// Collect all comments in this thread
		threadComments := b.collectThreadComments(rootComment)
		result[rootComment] = threadComments

		// Mark all comments in this thread as processed
		for _, tc := range threadComments {
			processed[tc.GetID()] = true
		}
	}

	return result
}

// writeReviewCommentThreadWithComments writes a thread with all its comments
func (b *reviewBuilder) writeReviewCommentThreadWithComments(ctx context.Context, sb *strings.Builder, rootComment *github.GQLPullRequestReviewComment, threadComments []*github.GQLPullRequestReviewComment, maxCommentBodyLength int, resolvedMap map[int64]bool) error {
	CommentThreadXMLTag := XMLCommentThread
	if resolvedMap[rootComment.GetID()] {
		CommentThreadXMLTag = XMLCommentThreadResolved
	}
	openXMLTag(sb, CommentThreadXMLTag)

	if rootComment.Path != "" {
		xmlTag(sb, XMLCommentFile, file(rootComment))
	}
	if rootComment.OriginalCommit.OID != "" {
		xmlTag(sb, XMLCommentOriginalCommit, rootComment.OriginalCommit.OID)
	}

	for _, comment := range threadComments {
		rc, err := pullRequestReviewComment(ctx, comment, b.gh, b.job, b.authorResolver, resolvedMap)
		if err != nil {
			return fmt.Errorf("failed to build review comment: %w", err)
		}

		if rc != nil {
			rc.Body = Truncate(rc.Body, maxCommentBodyLength)
			if err := writeXML(sb, rc); err != nil {
				return err
			}
		}
	}

	closeXMLTag(sb, CommentThreadXMLTag)
	return nil
}
