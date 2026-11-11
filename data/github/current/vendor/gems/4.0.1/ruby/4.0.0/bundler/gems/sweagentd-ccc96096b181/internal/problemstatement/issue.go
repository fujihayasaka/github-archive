package problemstatement

import (
	"cmp"
	"context"
	"slices"
	"strings"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

type issueBuilder struct {
	obsv           observability.Exporters
	gh             github.ClientInterface
	actx           *github.IssueContext
	agentID        int64
	filter         github.FilterCommentOpts
	authorResolver AuthorResolver

	additionalInstructions string // optional additional instructions to include in the problem statement, in addition to the issue's body
	appProvider            *agenticapp.Provider
}

var _ Builder = &issueBuilder{}

// IssueBuilderOpt is a functional option for configuring an issue builder.
type IssueBuilderOpt func(*issueBuilder)

// NewIssueBuilder creates a new problem statement builder for an issue.
func NewIssueBuilder(obsv observability.Exporters, gh github.ClientInterface, actx *github.IssueContext, agentID int64, authorResolver AuthorResolver, p *agenticapp.Provider, opts ...IssueBuilderOpt) Builder {
	ib := &issueBuilder{
		obsv:           obsv,
		gh:             gh,
		actx:           actx,
		agentID:        agentID,
		filter:         defaultFilterOpts(),
		authorResolver: authorResolver,
		appProvider:    p,
	}
	for _, opt := range opts {
		opt(ib)
	}

	return ib
}

// WithAdditionalInstructions adds additional instructions to the problem statement beyond the issue body.
func WithAdditionalInstructions(instructions string) IssueBuilderOpt {
	return func(ib *issueBuilder) {
		ib.additionalInstructions = instructions
	}
}

// Build implements ProblemStatementBuilder.
func (b *issueBuilder) Build(ctx context.Context) (jobs.ProblemStatement, error) {
	setCtxProblemStatement(ctx, b.obsv, &requestctx.CtxProblemStatement{Source: "issue"})

	comments := b.actx.FilteredComments(b.filter, b.appProvider.IsAgenticActor)
	slices.SortStableFunc(comments, func(a, b github.GQLIssueComment) int {
		return cmp.Compare(a.PublishedAt.Unix(), b.PublishedAt.Unix())
	})

	var sb strings.Builder

	var err error

	err = b.writeProblemStatement(ctx, &sb, 0, comments, 0)
	if err != nil {
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
	err = b.writeProblemStatement(ctx, &sb, 0, comments, MaxTruncatedCommentBodyLength)
	if err != nil {
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
		err = b.writeProblemStatement(ctx, &sb, 0, comments, MaxTruncatedCommentBodyLength)
		if err != nil {
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
	err = b.writeProblemStatement(ctx, &sb, maxBodyCharacterLength, comments, MaxTruncatedCommentBodyLength)
	if err != nil {
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
		err = b.writeProblemStatement(ctx, &sb, maxBodyCharacterLength, comments, MaxTruncatedCommentBodyLength)
		if err != nil {
			return jobs.ProblemStatement{}, err
		}
		result, _, resultBase64Length = formattedProblemStatement(ctx, b.obsv, &sb)
		if resultBase64Length <= MaxProblemStatementBase64EncodedLength {
			return jobs.ProblemStatement{Content: result, CommitCount: 0, ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown}, nil
		}
	}

	// If we still can't get it to fit, return an error. This should never actually happen.
	return jobs.ProblemStatement{}, goerrors.New("failed to generate problem statement within size limits")
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
	_, _ = sb.WriteString(SectionSeparator)
	_, _ = sb.WriteString(IssueSectionHeader)
	newLine(sb)

	openXMLTag(sb, XMLIssueTitle)
	_, _ = sb.WriteString(title)
	closeXMLTag(sb, XMLIssueTitle)

	openXMLTag(sb, XMLIssueDescription)

	body = Truncate(body, maxBodyLength)
	_, _ = sb.WriteString(body)
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
	_, _ = sb.WriteString(instructions)
	closeXMLTag(sb, XMLAgentInstructions)
	newLine(sb)
}

func (b *issueBuilder) writeComments(ctx context.Context, sb *strings.Builder, comments []github.GQLIssueComment, maxBodyLength int) error {
	mentionableSlug, err := mentionableSlugForAgent(b.appProvider, b.agentID)
	if err != nil {
		return goerrors.Errorf("failed to get mentionable slug for agent: %w", err)
	}
	_, _ = sb.WriteString(issueCommentsHeading(mentionableSlug))

	openXMLTag(sb, XMLComments)

	for i := range comments {
		c, err := issueComment(ctx, &comments[i], nil, b.authorResolver, b.appProvider.IsAgenticActor)
		if err != nil {
			return goerrors.Errorf("failed to resolve issue comment: %w", err)
		}

		if c != nil {
			c.Body = Truncate(c.Body, maxBodyLength)
			err := writeXML(sb, c)
			if err != nil {
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
	_ = b.writeComments(ctx, &tsb, nil, 0) // Error ignored in throwaway builder for length estimation

	maxBodyCharacterLength -= tsb.Len()
	if maxBodyCharacterLength < 0 {
		maxBodyCharacterLength = 0
	}

	return maxBodyCharacterLength
}
