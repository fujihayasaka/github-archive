// Package problemstatement contains logic for creating problem statements for job.
package problemstatement

import (
	"cmp"
	"context"
	"encoding/base64"
	"encoding/xml"
	"fmt"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

const (
	// MaxTruncatedCommentBodyLength is the maximum number of characters to include
	// for each comment body when they are truncated in an attempt to reduce the
	// size of the generated problem statement. The comment bodies are truncated
	// when the initial attempt to generate the problem statement yields a value
	// that exceeds the maximum allowed size. If the generated statement still
	// exceeds the maximum size after truncating the comment bodies, we may start
	// removing comments from oldest to newest or truncate the issue/pull request
	// description (depending on the type of problem statement being generated).
	//
	// Truncating the comment bodies first prevents a single, large comment from
	// causing dropped comments or truncation of other important information.
	// This is the maximum length of the comment body characters, not the length
	// of the base64 encoded string.
	MaxTruncatedCommentBodyLength = 2_000 // 2000

	// MaxProblemStatementLength is the maximum length of the problem statement
	// in characters before base64 encoding. This is approximately 30000 characters.
	// A base64 encoded string is approximately 33% larger than the original string,
	// so this becomes around 40000 characters when encoded.
	MaxProblemStatementLength = 30_000

	// MaxProblemStatementBase64EncodedLength is the maximum length of the base64
	// encoded problem statement (around 40000 characters, which is approximately
	// 30000 characters before encoding). If the problem statement exceeds this length,
	// problem statement generators should do their best to intelligently and
	// incrementally truncate the components that make up the problem statement
	// until the generated value (base64 encoded) fits within this size limit.
	// This is the length of the base64 encoded problem statement string.
	//
	// We constrain by the length of the base64 encoded value because that is how
	// the problem statement represented when it is passed as an input to Actions
	// and eventually exposed to the runtime as an environment variable. This is
	// important because Actions has a size limit of ~65535 for the combined inputs
	// that we must consider. See [launcher.validateInputs] for more details.
	//
	// The size of the problem statement may also be constrained by model token limits.
	MaxProblemStatementBase64EncodedLength = 40_000
)

// A list of XML tags that are used in the problem statement XML structure.
// This list needs to be mirrored on the runtime's allow-list filter for XML parsing.
const (
	XMLComments              string = "comments"
	XMLIssueTitle            string = "issue_title"
	XMLIssueDescription      string = "issue_description"
	XMLPRTitle               string = "pr_title"
	XMLPRDescription         string = "pr_description"
	XMLPRReviews             string = "pr_reviews"
	XMLPRComments            string = "pr_comments"
	XMLCommentThread         string = "comment_thread"
	XMLCommentThreadResolved string = "comment_thread_resolved"
	XMLCommentFile           string = "file"
	XMLCommentOriginalCommit string = "original_commit"
	XMLCommentPrefix         string = "comment_"
	XMLCommentOld            string = "comment_old" // should begin with XMLCommentPrefix
	XMLCommentNew            string = "comment_new" // should begin with XMLCommentPrefix
	XMLAgentInstructions     string = "agent_instructions"
	XMLStackedPRContext      string = "stacked_pr_context"
)

// AuthorResolver resolves author information for comments and reviews.
type AuthorResolver interface {
	Resolve(ctx context.Context, userID uint64, login string) (string, error)
}

const (
	// SectionSeparator is the separator used between sections in the problem statement.
	SectionSeparator string = "----\n"

	// IssueSectionHeader is the header for the issue section.
	IssueSectionHeader string = "*This section details on the original issue you should resolve*"
	// PullRequestSectionHeader is the header for the pull request section.
	PullRequestSectionHeader string = "*This section includes details on the pull request with code changes you have already submitted to fix the problem above.*"
	// StackedPullRequestSectionHeader is the header for the stacked pull request section.
	StackedPullRequestSectionHeader string = "*This section includes details on the stacked pull request you are creating to address the problem above.*"
	// FailedWorkflowRunSectionHeader is the header for the failed workflow run section.
	FailedWorkflowRunSectionHeader string = "*This section includes logs from the failed CI workflow run*"

	// IssueCommentsHeadingFormat is the format string for issue comments headings.
	IssueCommentsHeadingFormat string = "## Comments on the Issue (you are @%s in this section)\n"
	// PullRequestCommentsHeadingFormat is the format string for pull request comments headings.
	PullRequestCommentsHeadingFormat string = "## Comments on the PR (you are @%s in this section)\n"
)

// StackedPRContextMessage returns a message explaining that this is a stacked PR.
// It includes the base branch, default branch, and head branch names to help CCA
// understand that CI failures may be coming from the base branch.
func StackedPRContextMessage(baseBranch, defaultBranch, headBranch string) string {
	return fmt.Sprintf(
		"The pull request you are currently working on is a stacked pull request on top of another pull request. The base branch is `%s`, not the default branch `%s`. "+
			"If you are asked to fix CI, build, test, or workflow failures, check the GitHub Actions workflow runs for the original branch (`%s`) first. "+
			"If you don't find relevant failures there, then check your branch (`%s`).",
		baseBranch, defaultBranch, baseBranch, headBranch,
	)
}

func commitNote(commitCount int) string {
	return fmt.Sprintf("The last **%d** git commits in this branch are the changes you have made so far. Use those as your change commit history.", commitCount)
}

func issueCommentsHeading(slug string) string {
	return fmt.Sprintf(IssueCommentsHeadingFormat, slug)
}

func pullRequestCommentsHeading(slug string) string {
	return fmt.Sprintf(PullRequestCommentsHeadingFormat, slug)
}

// mentionableSlugForAgent returns the mentionable slug for the agent associated with the job. ex. @copilot, @claude[agent] or @codex[agent]
func mentionableSlugForAgent(p *agenticapp.Provider, agentID int64) (string, error) {
	app, err := p.FindByID(agentID)
	if err != nil {
		return "", err
	}

	return app.MentionableSlug(), nil
}

// Comment represents a comment in a problem statement.
type Comment struct {
	XMLName   xml.Name
	ID        int64  `xml:"comment_id,omitempty"`
	New       bool   `xml:"-"`
	Timestamp int64  `xml:"-"`
	Author    string `xml:"author,omitempty"`
	Body      string `xml:",innerxml"`
}

// Builder is an interface for building problem statements for jobs.
type Builder interface {
	// Build returns a problem statement for a given job.
	Build(ctx context.Context) (jobs.ProblemStatement, error)
}

func defaultFilterOpts() github.FilterCommentOpts {
	return github.FilterCommentOpts{
		IncludeMinimized:                   false,
		IncludeOtherBots:                   false,
		IncludeUsersWithoutPushPermissions: false, // https://github.com/github/sweagentd/issues/623
		IncludeCopilotReviews:              true,  // must be true to include inline review comment replies
	}
}

func issueComment(ctx context.Context, comment *github.GQLIssueComment, job *jobs.Job, authorResolver AuthorResolver, isAgentic agenticapp.IsAgenticFunc) (*Comment, error) {
	if comment.Body == "" {
		return nil, nil
	}
	_, isAgenticAuthor := isAgentic(comment.Author)
	isNew := !isAgenticAuthor

	// we only filter old job commentsIDs for pull request problem statements
	// for issue problem statements job will be nil and we'll include all comments
	if job != nil && job.CommentIDs != nil && len(job.CommentIDs) > 0 {
		isNew = slices.Contains(job.CommentIDs, comment.GetID()) && isNew
	}

	resolvedAuthor, err := author(ctx, authorResolver, comment.Author, isAgentic)
	if err != nil {
		return nil, goerrors.Errorf("failed to get author: %w", err)
	}

	var id int64
	if isNew {
		id = comment.GetID()
	}
	return &Comment{
		XMLName:   xmlName(isNew),
		ID:        id,
		New:       isNew,
		Timestamp: comment.PublishedAt.Unix(),
		Author:    resolvedAuthor,
		Body:      body(comment.Body),
	}, nil
}

func pullRequestReview(ctx context.Context, review *github.GQLPullRequestReview, job *jobs.Job, authorResolver AuthorResolver, isAgentic agenticapp.IsAgenticFunc) (*Comment, error) {
	if review.Body == "" {
		return nil, nil
	}
	_, isAgenticAuthor := isAgentic(review.Author)
	isNew := slices.Contains(job.ReviewIDs, review.GetID()) && !isAgenticAuthor

	resolvedAuthor, err := author(ctx, authorResolver, review.Author, isAgentic)
	if err != nil {
		return nil, goerrors.Errorf("failed to get author: %w", err)
	}

	var id int64
	if isNew {
		id = review.GetID()
	}
	return &Comment{
		XMLName:   xmlName(isNew),
		ID:        id,
		New:       isNew,
		Timestamp: review.PublishedAt.Unix(),
		Author:    resolvedAuthor,
		Body:      body(review.Body),
	}, nil
}

func pullRequestReviewComment(ctx context.Context, reviewComment *github.GQLPullRequestReviewComment, job *jobs.Job, authorResolver AuthorResolver, resolvedMap map[int64]bool, isAgentic agenticapp.IsAgenticFunc) (*Comment, error) {
	if reviewComment.Body == "" {
		return nil, nil
	}

	// Hasn't been handled in a past Job + Isn't authored by Copilot + Review thread isn't marked as resolved
	_, isAgenticAuthor := isAgentic(reviewComment.Author)
	isNew := slices.Contains(job.ReviewIDs, reviewComment.PullRequestReview.GetID()) && !isAgenticAuthor && !resolvedMap[reviewComment.GetID()]

	resolvedAuthor, err := author(ctx, authorResolver, reviewComment.Author, isAgentic)
	if err != nil {
		return nil, goerrors.Errorf("failed to get author: %w", err)
	}

	var id int64
	if isNew {
		id = reviewComment.GetID()
	}
	return &Comment{
		XMLName:   xmlName(isNew),
		ID:        id,
		New:       isNew,
		Timestamp: reviewComment.PublishedAt.Unix(),
		Author:    resolvedAuthor,
		Body:      body(reviewComment.Body),
	}, nil
}

func pullRequestReviewCommentSortFunc(a, b *github.GQLPullRequestReviewComment) int {
	return cmp.Compare(a.PublishedAt.Unix(), b.PublishedAt.Unix())
}

func xmlName(isNew bool) xml.Name {
	if isNew {
		return xml.Name{Local: XMLCommentNew}
	}
	return xml.Name{Local: XMLCommentOld}
}

func author(ctx context.Context, authorResolver AuthorResolver, a github.GQLActor, isAgentic agenticapp.IsAgenticFunc) (authorLogin string, err error) {
	app, isAgenticActor := isAgentic(a)
	switch {
	case isAgenticActor:
		return "@" + app.MentionableSlug(), nil

	case a.IsBot():
		return a.GetLogin() + "[bot]", nil

	default:
		displayLogin, err := authorResolver.Resolve(ctx, uint64(a.GetID()), a.GetLogin())
		if err != nil {
			return "", goerrors.Errorf("failed to resolve display login for user ID: %w", err)
		}

		return "@" + displayLogin, nil
	}
}

func body(s string) string {
	if s == "" {
		return s
	}
	return fmt.Sprintf("\n%s", s)
}

func file(comment *github.GQLPullRequestReviewComment) string {
	if comment.Path == "" {
		return ""
	}
	start, end := lines(comment)
	if start == 0 && end == 0 {
		return comment.Path
	}
	if start == end {
		return fmt.Sprintf("%s:%d", comment.Path, start)
	}
	return fmt.Sprintf("%s:%d-%d", comment.Path, start, end)
}

// When PR review comment is made, then code changes are subsequently pushed to the PR, the line
// numbers may change. This function returns the start and end line numbers of the code changes
// in the review as they are at the time we create the problem statement.
func lines(comment *github.GQLPullRequestReviewComment) (start, end int) {
	if comment.Line == 0 {
		end = comment.OriginalLine
	} else {
		end = comment.Line
	}
	if comment.StartLine == 0 {
		if comment.OriginalStartLine == 0 {
			start = end
		} else {
			start = comment.OriginalStartLine
		}
	} else {
		start = comment.StartLine
	}
	return start, end
}

// Truncate truncates a string to the given number of UTF-8 characters, appending "..." to the end.
// If the provided length is less than or equal to 0, or the string is already
// shorter than the given length, the string is returned as-is.
func Truncate(s string, n int) string {
	if n <= 0 {
		return s
	}

	runeCount := utf8.RuneCountInString(s)
	if runeCount > n {
		runes := []rune(s)
		if n <= 3 {
			return string(runes[:n])
		}
		return string(runes[:n-3]) + "..."
	}
	return s
}

// base64Length returns the length of the base64 encoded string of the given input.
func base64Length(s string) int {
	return len(base64.StdEncoding.EncodeToString([]byte(s)))
}

// In order to get the format we want, we marshal indent the XML with "-" as the
// prefix and no indenting. We then replace the prefix with "" and add newlines
// between the elements where we want them.
func writeXML(sb *strings.Builder, c *Comment) error {
	xb, err := xml.MarshalIndent(c, "-", "")
	if err != nil {
		return err
	}
	_, _ = sb.Write(xb)
	_, _ = sb.WriteString("\n")
	return nil
}

// Once we have the XML, we need to format it to match the format we want by
// replacing the prefix and adding newlines between specific elements.
func formatXML(xs string) string {
	xs = strings.ReplaceAll(xs, "-<", "<")

	// add an extra newline between the closing tag and the opening tag of the
	// next element to make the XML more readable.
	for _, node := range []string{XMLCommentOld, XMLCommentNew, XMLCommentOld, XMLPRComments, XMLCommentThread, XMLCommentOriginalCommit} {
		// TODO(colbylwilliams): do we really need to have old twice?
		o := fmt.Sprintf("</%s>\n<%s", node, XMLCommentPrefix)
		n := fmt.Sprintf("</%s>\n\n<%s", node, XMLCommentPrefix)
		xs = strings.ReplaceAll(xs, o, n)
	}
	return xs
}

func openXMLTag(sb *strings.Builder, tag string) {
	_, _ = sb.WriteString("\n<")
	_, _ = sb.WriteString(tag)
	_, _ = sb.WriteString(">\n")
}

func closeXMLTag(sb *strings.Builder, tag string) {
	_, _ = sb.WriteString("\n</")
	_, _ = sb.WriteString(tag)
	_, _ = sb.WriteString(">\n")
}

func xmlTag(sb *strings.Builder, tag, content string) {
	_, _ = sb.WriteString("<")
	_, _ = sb.WriteString(tag)
	_, _ = sb.WriteString(">")
	_, _ = sb.WriteString(content)
	_, _ = sb.WriteString("</")
	_, _ = sb.WriteString(tag)
	_, _ = sb.WriteString(">\n")
}

func newLine(sb *strings.Builder) {
	_, _ = sb.WriteString("\n")
}

func formattedProblemStatement(ctx context.Context, obsv observability.Exporters, sb *strings.Builder) (ps string, length, base64length int) {
	result := formatXML(sb.String())
	resultLength := len(result)
	resultBase64Length := base64Length(result)

	updateCtxProblemStatementLength(ctx, obsv, resultLength, resultBase64Length)

	return result, resultLength, resultBase64Length
}

func getCtxProblemStatement(ctx context.Context) *requestctx.CtxProblemStatement {
	ctxps, ok := requestctx.ProblemStatement(ctx)
	if !ok {
		ctxps = &requestctx.CtxProblemStatement{}
	}
	return ctxps
}

func setCtxProblemStatement(ctx context.Context, obsv observability.Exporters, ctxps *requestctx.CtxProblemStatement) {
	if ctxps == nil {
		return
	}
	err := requestctx.AddProblemStatement(ctx, ctxps)
	if err != nil {
		obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add problem statement context")
	}
}

func updateCtxProblemStatementLength(ctx context.Context, obsv observability.Exporters, length, base64Length int) {
	ctxps := getCtxProblemStatement(ctx)
	ctxps.Length = length
	ctxps.Base64Length = base64Length
	setCtxProblemStatement(ctx, obsv, ctxps)
}

func setCtxProblemStatementCommentsTruncated(ctx context.Context, obsv observability.Exporters) {
	ctxps := getCtxProblemStatement(ctx)
	ctxps.TruncatedComments = true
	setCtxProblemStatement(ctx, obsv, ctxps)
}

func setCtxProblemStatementDescriptionTruncated(ctx context.Context, obsv observability.Exporters) {
	ctxps := getCtxProblemStatement(ctx)
	ctxps.TruncatedDescription = true
	setCtxProblemStatement(ctx, obsv, ctxps)
}

func setCtxProblemStatementCommentsRemoved(ctx context.Context, obsv observability.Exporters, count int) {
	ctxps := getCtxProblemStatement(ctx)
	ctxps.RemovedComments = true
	ctxps.RemovedCommentsCount = count
	setCtxProblemStatement(ctx, obsv, ctxps)
}

// extractPRBodySections splits a PR body into core, original prompt, and user suffix sections.
// Returns (coreBody, originalPrompt, userSuffix)
func extractPRBodySections(body string) (coreBody, originalPrompt, userSuffix string) {
	originalPromptIndex := strings.Index(body, jobservice.PullRequestBodyOriginalPromptSeparator)
	userSuffixIndex := strings.Index(body, jobservice.PullRequestBodySuffixSeparator)

	// New format: core -> original prompt -> user suffix
	if originalPromptIndex != -1 && userSuffixIndex != -1 && originalPromptIndex < userSuffixIndex {
		coreBody = body[:originalPromptIndex]
		originalPrompt = body[originalPromptIndex:userSuffixIndex]
		userSuffix = body[userSuffixIndex:]
		return coreBody, originalPrompt, userSuffix
	}

	// Only original prompt separator found
	if originalPromptIndex != -1 {
		coreBody = body[:originalPromptIndex]
		originalPrompt = body[originalPromptIndex:]
		return coreBody, originalPrompt, ""
	}

	// Old format or only user suffix separator: core -> user suffix (includes original prompt)
	if userSuffixIndex != -1 {
		coreBody = body[:userSuffixIndex]
		userSuffix = body[userSuffixIndex:]
		return coreBody, "", userSuffix
	}

	// No separators found
	return body, "", ""
}
