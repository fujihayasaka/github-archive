package problemstatement

import (
	"container/list"
	"context"
	"slices"
	"strings"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/tips"
)

// reviewBuilder creates a problem statement for a stacked PR triggered by a review comment reply.
// It focuses on the specific review thread context instead of the full PR context.
type reviewBuilder struct {
	obsv           observability.Exporters
	actx           *github.PullRequestContext
	job            *jobs.Job
	reviewID       int64
	authorResolver AuthorResolver
	appProvider    *agenticapp.Provider
}

var _ Builder = &reviewBuilder{}

// NewReviewBuilder creates a problem statement builder focused on a specific review thread.
// This is used for stacked PRs that are created in response to a review comment reply.
func NewReviewBuilder(
	obsv observability.Exporters,
	actx *github.PullRequestContext,
	job *jobs.Job,
	reviewID int64,
	authorResolver AuthorResolver,
	appProvider *agenticapp.Provider,
) Builder {
	return &reviewBuilder{
		obsv:           obsv,
		actx:           actx,
		job:            job,
		reviewID:       reviewID,
		authorResolver: authorResolver,
		appProvider:    appProvider,
	}
}

func (b *reviewBuilder) Build(ctx context.Context) (jobs.ProblemStatement, error) {
	setCtxProblemStatement(ctx, b.obsv, &requestctx.CtxProblemStatement{Source: "review_reply"})

	pr := b.actx.PullRequest

	// Find the review that triggered this
	review := pr.ReviewByID(b.reviewID)
	if review == nil {
		return jobs.ProblemStatement{}, goerrors.Errorf("review with ID %d not found", b.reviewID)
	}

	var sb strings.Builder

	// Write header with a brief description
	b.writeHeader(&sb)

	// Write the specific review thread context
	err := b.writeReviewThread(ctx, &sb, review)
	if err != nil {
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
		err = b.writeReviewThreadTruncated(ctx, &sb, review, MaxTruncatedCommentBodyLength)
		if err != nil {
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
	_, _ = sb.WriteString(SectionSeparator)
	_, _ = sb.WriteString(StackedPullRequestSectionHeader)
	newLine(sb)

	openXMLTag(sb, XMLPRTitle)
	_, _ = sb.WriteString(title)
	closeXMLTag(sb, XMLPRTitle)

	openXMLTag(sb, XMLPRDescription)

	body = tips.RemoveTips(body)
	_, _ = sb.WriteString(body)
	closeXMLTag(sb, XMLPRDescription)
	newLine(sb)

	_, _ = sb.WriteString(SectionSeparator)
	// Add context about what triggered this stacked PR
	_, _ = sb.WriteString("This stacked PR was created to address a specific review comment on a different pull request.\n")
	_, _ = sb.WriteString("Focus on addressing the feedback in the review thread below.\n")
	newLine(sb)
}

func (b *reviewBuilder) writeReviewThread(ctx context.Context, sb *strings.Builder, review *github.GQLPullRequestReview) error {
	return b.writeReviewThreadWithMaxLength(ctx, sb, review, 0)
}

func (b *reviewBuilder) writeReviewThreadTruncated(ctx context.Context, sb *strings.Builder, review *github.GQLPullRequestReview, maxCommentBodyLength int) error {
	return b.writeReviewThreadWithMaxLength(ctx, sb, review, maxCommentBodyLength)
}

func (b *reviewBuilder) writeReviewThreadWithMaxLength(ctx context.Context, sb *strings.Builder, review *github.GQLPullRequestReview, maxCommentBodyLength int) error {
	mentionableSlug, err := mentionableSlugForAgent(ctx, b.appProvider, b.job.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to get mentionable slug for agent: %w", err)
	}
	_, _ = sb.WriteString(pullRequestCommentsHeading(mentionableSlug))
	openXMLTag(sb, XMLComments)

	// Build the resolved map once for O(1) lookups
	resolvedMap := b.actx.GetReviewThreadResolvedMap()

	// If this is a review comment reply, we need to show the entire thread
	if review.IsReviewCommentReply() { //nolint:nestif // complexity with if/else is acceptable here for readability
		replyComment := &review.Comments.Nodes[0]

		// Find the root comment by traversing up the reply chain
		rootComment := b.findRootComment(replyComment)
		if rootComment == nil {
			return goerrors.New("could not find root comment for reply")
		}

		// Collect all comments in the thread (root + all replies)
		threadComments := b.collectThreadComments(rootComment)
		// Build the full thread by finding the root comment and all replies
		err := b.writeReviewCommentThreadWithComments(ctx, sb, rootComment, threadComments, maxCommentBodyLength, resolvedMap)
		if err != nil {
			return err
		}
	} else {
		// This is a top-level review
		// Check if the review body mentions @copilot
		_, reviewBodyMentionsCopilot := b.appProvider.IsAgenticMention(review.GetBody())

		// Write the review body if present
		reviewComment, err := pullRequestReview(ctx, review, b.job, b.authorResolver, b.appProvider.IsAgenticActor)
		if err != nil {
			return goerrors.Errorf("failed to build review comment: %w", err)
		}

		if reviewComment != nil {
			reviewComment.Body = Truncate(reviewComment.Body, maxCommentBodyLength)
			err := writeXML(sb, reviewComment)
			if err != nil {
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
					if _, ok := b.appProvider.IsAgenticMention(comment.GetBody()); ok {
						threadMentionsCopilot = true
						break
					}
				}
			}

			if threadMentionsCopilot {
				// Write the entire thread
				err := b.writeReviewCommentThreadWithComments(ctx, sb, rootComment, threadComments, maxCommentBodyLength, resolvedMap)
				if err != nil {
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
		for i := range b.actx.PullRequest.Reviews.Nodes {
			review := &b.actx.PullRequest.Reviews.Nodes[i]
			for ii := range review.Comments.Nodes {
				reviewComment := &review.Comments.Nodes[ii]
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
		element := queue.Remove(queue.Front())
		parentID, ok := element.(int64)
		if !ok {
			// This should never happen as we only push int64 values to the queue,
			// but we skip invalid elements to be safe
			continue
		}

		// Find all direct replies to this parent
		for i := range b.actx.PullRequest.Reviews.Nodes {
			review := &b.actx.PullRequest.Reviews.Nodes[i]
			for ii := range review.Comments.Nodes {
				comment := &review.Comments.Nodes[ii]
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
	_, _ = sb.WriteString(SectionSeparator)
	if commitCount > 0 {
		_, _ = sb.WriteString(commitNote(commitCount))
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
	commentThreadXMLTag := XMLCommentThread
	if resolvedMap[rootComment.GetID()] {
		commentThreadXMLTag = XMLCommentThreadResolved
	}
	openXMLTag(sb, commentThreadXMLTag)

	if rootComment.Path != "" {
		xmlTag(sb, XMLCommentFile, file(rootComment))
	}
	if rootComment.OriginalCommit.OID != "" {
		xmlTag(sb, XMLCommentOriginalCommit, rootComment.OriginalCommit.OID)
	}

	for _, comment := range threadComments {
		rc, err := pullRequestReviewComment(ctx, comment, b.job, b.authorResolver, resolvedMap, b.appProvider.IsAgenticActor)
		if err != nil {
			return goerrors.Errorf("failed to build review comment: %w", err)
		}

		if rc != nil {
			rc.Body = Truncate(rc.Body, maxCommentBodyLength)
			err := writeXML(sb, rc)
			if err != nil {
				return err
			}
		}
	}

	closeXMLTag(sb, commentThreadXMLTag)
	return nil
}
