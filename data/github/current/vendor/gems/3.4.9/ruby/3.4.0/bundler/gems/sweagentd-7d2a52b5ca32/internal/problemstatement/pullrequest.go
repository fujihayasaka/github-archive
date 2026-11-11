package problemstatement

import (
	"cmp"
	"context"
	"fmt"
	"slices"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/tips"
)

type prBuilder struct {
	obsv           observability.Exporters
	gh             github.CopilotUserChecker
	actx           *github.PullRequestContext
	job            *jobs.Job
	filter         github.FilterCommentOpts
	authorResolver AuthorResolver
	ffClient       featureflags.Client
}

var _ ProblemStatementBuilder = &prBuilder{}

func NewPullRequestBuilder(obsv observability.Exporters, gh github.CopilotUserChecker, actx *github.PullRequestContext, job *jobs.Job, authorResolver AuthorResolver, ffClient featureflags.Client) ProblemStatementBuilder {
	return &prBuilder{
		obsv:           obsv,
		gh:             gh,
		actx:           actx,
		job:            job,
		filter:         defaultFilterOpts(),
		authorResolver: authorResolver,
		ffClient:       ffClient,
	}
}

type commentRef struct {
	ID        int64
	IsReview  bool
	Timestamp int64
}

func (b *prBuilder) Build(ctx context.Context) (jobs.ProblemStatement, error) {
	setCtxProblemStatement(ctx, b.obsv, &requestctx.CtxProblemStatement{Source: "pull_request"})

	sorted := []commentRef{}

	// We need to sort the combined comments/reviews by timestamp, so we'll use
	// a placeholder struct to hold the ID and timestamp of each comment/review.
	comments := b.actx.FilteredComments(b.gh, b.filter)
	reviews := b.actx.FilteredReviews(b.gh, b.filter)
	for _, comment := range comments {
		sorted = append(sorted, commentRef{
			ID:        comment.GetID(),
			IsReview:  false,
			Timestamp: comment.PublishedAt.Unix(),
		})
	}
	for _, review := range reviews {
		sorted = append(sorted, commentRef{
			ID:        review.GetID(),
			IsReview:  true,
			Timestamp: review.PublishedAt.Unix(),
		})
	}
	slices.SortStableFunc(sorted, func(a, b commentRef) int {
		return cmp.Compare(a.Timestamp, b.Timestamp)
	})

	var sb strings.Builder

	if err := b.writeProblemStatement(ctx, &sb, 0, sorted, reviews, 0); err != nil {
		return jobs.ProblemStatement{}, err
	}

	result, _, resultBase64Length := formattedProblemStatement(ctx, b.obsv, &sb)
	// If the problem statement is already less than the max size, we're done
	if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
		return jobs.ProblemStatement{Content: result, CommitCount: b.actx.PullRequest.Commits.TotalCount, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
	}

	// Otherwise, try capping the length of each comment body
	setCtxProblemStatementCommentsTruncated(ctx, b.obsv)
	b.obsv.LoggerWithTelemetry(ctx).Info("problem statement exceeds maximum size, truncating comments to max number of characters")
	sb.Reset()
	if err := b.writeProblemStatement(ctx, &sb, 0, sorted, reviews, MaxTruncatedCommentBodyLength); err != nil {
		return jobs.ProblemStatement{}, err
	}
	result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
	if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
		return jobs.ProblemStatement{Content: result, CommitCount: b.actx.PullRequest.Commits.TotalCount, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
	}

	// If the problem statement is still too long after truncating the comments,
	// begin truncating the body of the pull request itself. Unlike the initial
	// issue problem statement, this should rarely be necessary. The PR body should
	// have already been reduced to a summary on the initial "fix" job.
	//
	// Unlike the issue problem statement generator, for PRs we truncate the body
	// before we start removing comments. This is because the comments/reviews are
	// more likely to contain the historical context, current state, and intended
	// outcome of the pull request than its description.
	setCtxProblemStatementDescriptionTruncated(ctx, b.obsv)
	b.obsv.LoggerWithTelemetry(ctx).Info("problem statement still exceeds maximum size, truncating body")
	sb.Reset()
	maxBodyCharacterLength := b.getApproximateMaxTruncatedPullRequestBodyLength(ctx, sorted, reviews, MaxTruncatedCommentBodyLength)
	if err := b.writeProblemStatement(ctx, &sb, maxBodyCharacterLength, sorted, reviews, MaxTruncatedCommentBodyLength); err != nil {
		return jobs.ProblemStatement{}, err
	}
	result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
	if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
		return jobs.ProblemStatement{Content: result, CommitCount: b.actx.PullRequest.Commits.TotalCount, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
	}

	const additionalBufferIncrement = 20

	// If our characters length math is off by a little, reduce the max body length by
	// 20 characters until we get a problem statement that fits within the size limits
	for maxBodyCharacterLength > additionalBufferIncrement {
		maxBodyCharacterLength -= additionalBufferIncrement
		b.obsv.LoggerWithTelemetry(ctx).Info("problem statement still exceeds maximum size, truncating body with additional buffer")
		sb.Reset()
		if err := b.writeProblemStatement(ctx, &sb, maxBodyCharacterLength, sorted, reviews, MaxTruncatedCommentBodyLength); err != nil {
			return jobs.ProblemStatement{}, err
		}
		result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
		if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
			return jobs.ProblemStatement{Content: result, CommitCount: b.actx.PullRequest.Commits.TotalCount, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
		}
	}

	// If the problem statement is _still_ too long, start removing comments. This
	// should really never happen, but we'll handle it gracefully just in case.
	b.obsv.LoggerWithTelemetry(ctx).Info("problem statement still exceeds maximum size, starting to remove comments")
	numSorted := len(sorted)
	for len(sorted) > 0 {
		sorted = sorted[1:]
		setCtxProblemStatementCommentsRemoved(ctx, b.obsv, numSorted-len(sorted))

		sb.Reset()
		if err := b.writeProblemStatement(ctx, &sb, maxBodyCharacterLength, sorted, reviews, MaxTruncatedCommentBodyLength); err != nil {
			return jobs.ProblemStatement{}, err
		}
		result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
		if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
			return jobs.ProblemStatement{Content: result, CommitCount: b.actx.PullRequest.Commits.TotalCount, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
		}
	}

	// If we still can't get it to fit, return an error. This should never actually happen.
	return jobs.ProblemStatement{}, fmt.Errorf("failed to generate problem statement within size limits")
}

func (b *prBuilder) writeProblemStatement(ctx context.Context, sb *strings.Builder, maxBodyLength int, sorted []commentRef, reviews []github.GQLPullRequestReview, maxCommentBodyLength int) error {
	b.writeHeader(ctx, sb, b.actx.PullRequest.Title, b.actx.PullRequest.Body, maxBodyLength)
	if err := b.writeComments(ctx, sb, sorted, reviews, maxCommentBodyLength); err != nil {
		return err
	}
	b.writeFooter(sb, b.actx.PullRequest.Commits.TotalCount)
	return nil
}

func (b *prBuilder) writeHeader(ctx context.Context, sb *strings.Builder, title, body string, maxBodyLength int) {
	newLine(sb)
	sb.WriteString(SectionSeparator)
	sb.WriteString(PullRequestSectionHeader)
	newLine(sb)

	openXMLTag(sb, XMLPRTitle)
	sb.WriteString(title)
	closeXMLTag(sb, XMLPRTitle)

	openXMLTag(sb, XMLPRDescription)

	body = tips.RemoveTips(body)
	if b.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentPRBodyRemoveFixesInSuffix, b.job) {
		body = RemoveFixesInSuffix(body)
	}
	body = Truncate(body, maxBodyLength)

	sb.WriteString(body)
	closeXMLTag(sb, XMLPRDescription)
	newLine(sb)
}

type commentGroup int

const (
	CommentGroupNone commentGroup = iota
	CommentGroupPRComments
	CommentGroupPRReviews
)

func (b *prBuilder) writeComments(ctx context.Context, sb *strings.Builder, sorted []commentRef, reviews []github.GQLPullRequestReview, maxCommentBodyLength int) error {
	sb.WriteString(PullRequestCommentsHeading)

	openXMLTag(sb, XMLComments)

	group := CommentGroupNone

	// Build the resolved map once for O(1) lookups
	resolvedMap := b.actx.PullRequest.GetReviewThreadResolvedMap()

	for _, s := range sorted {
		if s.IsReview {
			if review := reviewByID(reviews, s.ID); review != nil {
				// Write the top-level review comment
				r, err := pullRequestReview(ctx, review, b.gh, b.job, b.authorResolver)
				if err != nil {
					return fmt.Errorf("failed to build review %w", err)
				}

				if r != nil {
					group.open(sb, CommentGroupPRComments)
					r.Body = Truncate(r.Body, maxCommentBodyLength)
					if err := writeXML(sb, r); err != nil {
						return err
					}
				}

				// Skip reviews that only contain a reply to another review's
				// comment. We'll include the reply in the comment's thread.
				if review.IsReviewCommentReply() {
					continue
				}

				if review.Comments.Len() > 0 {
					group.open(sb, CommentGroupPRReviews)
				}

				for _, reviewComment := range review.Comments.Nodes {
					// Wrap all review comments in a thread. Even if there's only one
					// comment, the thread indicates that the comment can be replied to.
					CommentThreadXMLTag := XMLCommentThread
					if resolvedMap[reviewComment.GetID()] {
						CommentThreadXMLTag = XMLCommentThreadResolved
					}

					openXMLTag(sb, CommentThreadXMLTag)

					xmlTag(sb, XMLCommentFile, file(&reviewComment))
					xmlTag(sb, XMLCommentOriginalCommit, reviewComment.OriginalCommit.AbbreviatedOID)

					rc, err := pullRequestReviewComment(ctx, &reviewComment, b.gh, b.job, b.authorResolver, resolvedMap)
					if err != nil {
						return fmt.Errorf("failed to build review %w", err)
					}

					if rc != nil {
						rc.Body = Truncate(rc.Body, maxCommentBodyLength)
						if err := writeXML(sb, rc); err != nil {
							return err
						}
					}

					// Write all replies to the review comment in the thread
					for _, reply := range getReplies(&reviewComment, reviews) {
						re, err := pullRequestReviewComment(ctx, reply, b.gh, b.job, b.authorResolver, resolvedMap)
						if err != nil {
							return fmt.Errorf("failed to build review reply %w", err)
						}

						if re != nil {
							re.Body = Truncate(re.Body, maxCommentBodyLength)
							if re.New {
								// Overwrite the ID to the review comment ID
								re.ID = reviewComment.GetID()
							}
							if err := writeXML(sb, re); err != nil {
								return err
							}
						}
					}

					closeXMLTag(sb, CommentThreadXMLTag)
				}
			}
		} else {
			if comment := b.actx.PullRequest.CommentByID(s.ID); comment != nil {
				ic, err := issueComment(ctx, comment, b.gh, b.job, b.authorResolver)
				if err != nil {
					return fmt.Errorf("failed to build issue comment %w", err)
				}

				if ic != nil {
					group.open(sb, CommentGroupPRComments)
					ic.Body = Truncate(ic.Body, maxCommentBodyLength)
					if err := writeXML(sb, ic); err != nil {
						return err
					}
				}
			}
		}
	}

	group.close(sb)

	closeXMLTag(sb, XMLComments)
	newLine(sb)

	return nil
}

func (b *prBuilder) writeFooter(sb *strings.Builder, commitCount int) {
	sb.WriteString(SectionSeparator)
	if commitCount > 0 {
		sb.WriteString(commitNote(commitCount))
	}
}

// getApproximateMaxTruncatedPullRequestBodyLength calculates the maximum length of the
// pull request body that can be used to ensure the entire problem statement fits within
// the size limits. It does this by estimating the length of the header, comments and
// footer that will be included in the problem statement, and subtracting that from the
// maximum allowed size for the base64 encoded problem statement.
func (b *prBuilder) getApproximateMaxTruncatedPullRequestBodyLength(ctx context.Context, sorted []commentRef, reviews []github.GQLPullRequestReview, maxCommentBodyLength int) int {
	maxBodyCharacterLength := int(MaxProblemStatementBase64EncodedLength * 0.75)

	// create throwaway builder to compute the characters used by everything
	// except the body of the pull request to estimate how many characters we
	// need to truncate the body to fit within the size limits
	var tsb strings.Builder
	b.writeHeader(ctx, &tsb, b.actx.PullRequest.Title, "", 0)
	b.writeComments(ctx, &tsb, sorted, reviews, maxCommentBodyLength)
	b.writeFooter(&tsb, b.actx.PullRequest.Commits.TotalCount)

	maxBodyCharacterLength -= tsb.Len()
	if maxBodyCharacterLength < 0 {
		maxBodyCharacterLength = 0
	}

	return maxBodyCharacterLength
}

func getReplies(comment *github.GQLPullRequestReviewComment, reviews []github.GQLPullRequestReview) []*github.GQLPullRequestReviewComment {
	var replies []*github.GQLPullRequestReviewComment
	for _, review := range reviews {
		for _, reviewComment := range review.Comments.Nodes {
			if reviewComment.ReplyTo != nil && reviewComment.ReplyTo.GetID() == comment.GetID() {
				replies = append(replies, &reviewComment)
			}
		}
	}
	slices.SortStableFunc(replies, pullRequestReviewCommentSortFunc)
	return replies
}

func reviewByID(reviews []github.GQLPullRequestReview, id int64) *github.GQLPullRequestReview {
	for _, review := range reviews {
		if review.GetID() == id {
			return &review
		}
	}
	return nil
}

func (g *commentGroup) open(sb *strings.Builder, group commentGroup) {
	if *g == group {
		return
	}

	closeCommentGroup(sb, *g)

	switch group {
	case CommentGroupPRComments:
		openXMLTag(sb, XMLPRComments)
		newLine(sb)
	case CommentGroupPRReviews:
		openXMLTag(sb, XMLPRReviews)
	}

	*g = group
}

func (g *commentGroup) close(sb *strings.Builder) {
	closeCommentGroup(sb, *g)
	*g = CommentGroupNone
}

func closeCommentGroup(sb *strings.Builder, group commentGroup) {
	if group == CommentGroupNone {
		return
	}
	switch group {
	case CommentGroupPRComments:
		closeXMLTag(sb, XMLPRComments)
	case CommentGroupPRReviews:
		closeXMLTag(sb, XMLPRReviews)
	}
}
