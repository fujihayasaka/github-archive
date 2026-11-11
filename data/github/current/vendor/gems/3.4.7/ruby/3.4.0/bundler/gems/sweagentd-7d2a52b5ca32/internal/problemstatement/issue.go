package problemstatement

import (
	"context"
	"fmt"
	"slices"
	"strings"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

type issueBuilder struct {
	obsv           observability.Exporters
	gh             github.ClientInterface
	actx           *github.IssueContext
	filter         github.FilterCommentOpts
	authorResolver AuthorResolver

	additionalInstructions string // optional additional instructions to include in the problem statement, in addition to the issue's body
}

var _ ProblemStatementBuilder = &issueBuilder{}

type IssueBuilderOpt func(*issueBuilder)

func NewIssueBuilder(obsv observability.Exporters, gh github.ClientInterface, actx *github.IssueContext, authorResolver AuthorResolver, opts ...IssueBuilderOpt) ProblemStatementBuilder {
	ib := &issueBuilder{
		obsv:           obsv,
		gh:             gh,
		actx:           actx,
		filter:         defaultFilterOpts(),
		authorResolver: authorResolver,
	}
	for _, opt := range opts {
		opt(ib)
	}

	return ib
}

func WithAdditionalInstructions(instructions string) IssueBuilderOpt {
	return func(ib *issueBuilder) {
		ib.additionalInstructions = instructions
	}
}

// Build implements ProblemStatementBuilder.
func (b *issueBuilder) Build(ctx context.Context) (jobs.ProblemStatement, error) {
	setCtxProblemStatement(ctx, b.obsv, &requestctx.CtxProblemStatement{Source: "issue"})

	comments := b.actx.FilteredComments(b.gh, b.filter)
	slices.SortStableFunc(comments, issueCommentSortFunc)

	var sb strings.Builder

	if err := b.writeProblemStatement(ctx, &sb, 0, comments, 0); err != nil {
		return jobs.ProblemStatement{}, err
	}
	result, _, resultBase64Length := formattedProblemStatement(ctx, b.obsv, &sb)
	// If the problem statement is already less than the max size, we're done
	if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
		return jobs.ProblemStatement{Content: result, CommitCount: 0, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
	}

	// Otherwise, try capping the length of each comment body
	setCtxProblemStatementCommentsTruncated(ctx, b.obsv)
	b.obsv.LoggerWithTelemetry(ctx).Info("problem statement exceeds maximum size, truncating comments to max number of characters")
	sb.Reset()
	if err := b.writeProblemStatement(ctx, &sb, 0, comments, MaxTruncatedCommentBodyLength); err != nil {
		return jobs.ProblemStatement{}, err
	}
	result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
	if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
		return jobs.ProblemStatement{Content: result, CommitCount: 0, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
	}

	// If the problem statement is still too long, start removing comments
	b.obsv.LoggerWithTelemetry(ctx).Info("problem statement still exceeds maximum size, starting to remove comments")
	numComments := len(comments)
	for len(comments) > 0 {
		comments = comments[1:]
		setCtxProblemStatementCommentsRemoved(ctx, b.obsv, numComments-len(comments))

		sb.Reset()
		if err := b.writeProblemStatement(ctx, &sb, 0, comments, MaxTruncatedCommentBodyLength); err != nil {
			return jobs.ProblemStatement{}, err
		}
		result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
		if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
			return jobs.ProblemStatement{Content: result, CommitCount: 0, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
		}
	}

	// If we've removed all the comments and it's still too long, we'll have to
	// truncate the body of the issue itself.
	setCtxProblemStatementDescriptionTruncated(ctx, b.obsv)
	b.obsv.LoggerWithTelemetry(ctx).Info("problem statement still exceeds maximum size, truncating body")
	sb.Reset()
	maxBodyCharacterLength := b.getApproximateMaxTruncatedIssueBodyLength(ctx)
	if err := b.writeProblemStatement(ctx, &sb, maxBodyCharacterLength, comments, MaxTruncatedCommentBodyLength); err != nil {
		return jobs.ProblemStatement{}, err
	}
	result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
	if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
		return jobs.ProblemStatement{Content: result, CommitCount: 0, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
	}

	const additionalBufferIncrement = 20

	// If our characters length math is off by a little, reduce the max body length by
	// 20 characters until we get a problem statement that fits within the size limits
	for maxBodyCharacterLength > additionalBufferIncrement {
		maxBodyCharacterLength -= additionalBufferIncrement
		b.obsv.LoggerWithTelemetry(ctx).Info("problem statement still exceeds maximum size, truncating body with additional buffer")
		sb.Reset()
		if err := b.writeProblemStatement(ctx, &sb, maxBodyCharacterLength, comments, MaxTruncatedCommentBodyLength); err != nil {
			return jobs.ProblemStatement{}, err
		}
		result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
		if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
			return jobs.ProblemStatement{Content: result, CommitCount: 0, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
		}
	}

	// If we still can't get it to fit, return an error. This should never actually happen.
	return jobs.ProblemStatement{}, fmt.Errorf("failed to generate problem statement within size limits")
}

func (b *issueBuilder) writeProblemStatement(ctx context.Context, sb *strings.Builder, maxIssueBodyLength int, comments []github.GQLIssueComment, maxCommentBodyLength int) error {
	// If we have additional instructions, they take priority over the issue body
	// when calculating how much space we have.
	maxInstructionsLength := 0
	if b.additionalInstructions != "" {
		maxInstructionsLength = min(len(b.additionalInstructions), maxIssueBodyLength)
	}
	maxHeaderLength := max(0, maxIssueBodyLength-maxInstructionsLength)

	b.writeHeader(sb, b.actx.Issue.Title, b.actx.Issue.Body, maxHeaderLength)
	b.writeAdditionalInstructions(sb, b.additionalInstructions, maxInstructionsLength)
	err := b.writeComments(ctx, sb, comments, maxCommentBodyLength)
	return err
}

func (b *issueBuilder) writeHeader(sb *strings.Builder, title, body string, maxBodyLength int) {
	newLine(sb)
	sb.WriteString(SectionSeparator)
	sb.WriteString(IssueSectionHeader)
	newLine(sb)

	openXMLTag(sb, XMLIssueTitle)
	sb.WriteString(title)
	closeXMLTag(sb, XMLIssueTitle)

	openXMLTag(sb, XMLIssueDescription)

	body = Truncate(body, maxBodyLength)
	sb.WriteString(body)
	closeXMLTag(sb, XMLIssueDescription)
	newLine(sb)
}

func (b *issueBuilder) writeAdditionalInstructions(sb *strings.Builder, instructions string, maxBodyLength int) {
	if instructions == "" {
		return
	}

	openXMLTag(sb, XMLAgentInstructions)
	newLine(sb)

	instructions = Truncate(instructions, maxBodyLength)
	sb.WriteString(instructions)
	closeXMLTag(sb, XMLAgentInstructions)
	newLine(sb)
}

func (b *issueBuilder) writeComments(ctx context.Context, sb *strings.Builder, comments []github.GQLIssueComment, maxBodyLength int) error {
	sb.WriteString(IssueCommentsHeading)

	openXMLTag(sb, XMLComments)

	for _, comment := range comments {
		c, err := issueComment(ctx, &comment, b.gh, nil, b.authorResolver)
		if err != nil {
			return fmt.Errorf("failed to resolve issue comment: %w", err)
		}

		if c != nil {
			c.Body = Truncate(c.Body, maxBodyLength)
			if err := writeXML(sb, c); err != nil {
				return err
			}
		}
	}

	closeXMLTag(sb, XMLComments)
	newLine(sb)

	return nil
}

// getApproximateMaxTruncatedIssueBodyLength calculates the maximum length of the
// issue body that can be used to ensure the entire problem statement fits within
// the size limits. It does this by estimating the length of the header and comments
// that will be included in the problem statement, and subtracting that from the
// maximum allowed size for the base64 encoded problem statement.
func (b *issueBuilder) getApproximateMaxTruncatedIssueBodyLength(ctx context.Context) int {
	maxBodyCharacterLength := int(MaxProblemStatementBase64EncodedLength * 0.75)

	// create throwaway builder to compute the characters used by everything
	// except the body of the issue to estimate how many characters we need to
	// truncate the body to fit within the size limits
	var tsb strings.Builder
	b.writeHeader(&tsb, b.actx.Issue.Title, "", 0)
	b.writeAdditionalInstructions(&tsb, b.additionalInstructions, 0)
	b.writeComments(ctx, &tsb, nil, 0)

	maxBodyCharacterLength -= tsb.Len()
	if maxBodyCharacterLength < 0 {
		maxBodyCharacterLength = 0
	}

	return maxBodyCharacterLength
}
