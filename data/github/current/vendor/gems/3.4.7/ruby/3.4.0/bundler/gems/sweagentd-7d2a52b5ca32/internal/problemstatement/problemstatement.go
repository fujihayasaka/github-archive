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

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
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

	// MaxProblemStatementBase64EncodedLength is the maximum length of the base64
	// encoded problem statement. If the problem statement exceeds this length,
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
	//
	// A base64 encoded string is approximately 33% larger than the original string.
	// so the value of 40000 here is equivalent to around 30000 characters.
	MaxProblemStatementLength              = 30_000
	MaxProblemStatementBase64EncodedLength = 40_000 // ~30000 characters
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
)

type AuthorResolver interface {
	Resolve(ctx context.Context, userID uint64, login string) (string, error)
}

// WithAgentInstructions adds the custom agent instructions to the job's problem statement to return a final problem statement.
func WithAgentInstructions(ctx context.Context, problemStatement string, instructions sweagentd.CustomAgentInstructions) string {
	var sb strings.Builder
	instructions.WritePrompt(&sb)

	if i := sb.String(); i != "" {
		problemStatement = fmt.Sprintf("%s\n%s", i, problemStatement)
	}

	if utf8.RuneCountInString(problemStatement) > MaxProblemStatementLength {
		runes := []rune(problemStatement)
		problemStatement = string(runes[:MaxProblemStatementLength-3]) + "..."
	}

	return problemStatement
}

const (
	SectionSeparator string = "----\n"

	IssueSectionHeader              string = "*This section details on the original issue you should resolve*"
	PullRequestSectionHeader        string = "*This section includes details on the pull request with code changes you have already submitted to fix the problem above.*"
	StackedPullRequestSectionHeader string = "*This section includes details on the stacked pull request you are creating to address the problem above.*"
	FailedWorkflowRunSectionHeader  string = "*This section includes logs from the failed CI workflow run*"

	IssueCommentsHeading       string = "## Comments on the Issue (you are @copilot in this section)\n"
	PullRequestCommentsHeading string = "## Comments on the PR (you are @copilot in this section)\n"
)

func commitNote(commitCount int) string {
	return fmt.Sprintf("The last **%d** git commits in this branch are the changes you have made so far. Use those as your change commit history.", commitCount)
}

type Comment struct {
	XMLName   xml.Name
	ID        int64  `xml:"comment_id,omitempty"`
	New       bool   `xml:"-"`
	Timestamp int64  `xml:"-"`
	Author    string `xml:"author,omitempty"`
	Body      string `xml:",innerxml"`
}

type ProblemStatementBuilder interface {
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

func issueComment(ctx context.Context, comment *github.GQLIssueComment, gh github.CopilotUserChecker, job *jobs.Job, authorResolver AuthorResolver) (*Comment, error) {
	if comment.Body == "" {
		return nil, nil
	}
	new := !comment.Author.IsCopilot(gh)

	// we only filter old job commentsIDs for pull request problem statements
	// for issue problem statements job will be nil and we'll include all comments
	if job != nil && job.CommentIDs != nil && len(job.CommentIDs) > 0 {
		new = slices.Contains(job.CommentIDs, comment.GetID()) && new
	}

	resolvedAuthor, err := author(ctx, authorResolver, comment.Author, gh)
	if err != nil {
		return nil, fmt.Errorf("failed to get author: %w", err)
	}

	var id int64
	if new {
		id = comment.GetID()
	}
	return &Comment{
		XMLName:   xmlName(new),
		ID:        id,
		New:       new,
		Timestamp: comment.PublishedAt.Unix(),
		Author:    resolvedAuthor,
		Body:      body(comment.Body),
	}, nil
}

func issueCommentSortFunc(a, b github.GQLIssueComment) int {
	return cmp.Compare(a.PublishedAt.Unix(), b.PublishedAt.Unix())
}

func pullRequestReview(ctx context.Context, review *github.GQLPullRequestReview, gh github.CopilotUserChecker, job *jobs.Job, authorResolver AuthorResolver) (*Comment, error) {
	if review.Body == "" {
		return nil, nil
	}
	new := slices.Contains(job.ReviewIDs, review.GetID()) && !review.Author.IsCopilot(gh)

	resolvedAuthor, err := author(ctx, authorResolver, review.Author, gh)
	if err != nil {
		return nil, fmt.Errorf("failed to get author: %w", err)
	}

	var id int64
	if new {
		id = review.GetID()
	}
	return &Comment{
		XMLName:   xmlName(new),
		ID:        id,
		New:       new,
		Timestamp: review.PublishedAt.Unix(),
		Author:    resolvedAuthor,
		Body:      body(review.Body),
	}, nil
}

func pullRequestReviewSortFunc(a, b *github.GQLPullRequestReview) int {
	return cmp.Compare(a.PublishedAt.Unix(), b.PublishedAt.Unix())
}

func pullRequestReviewComment(ctx context.Context, reviewComment *github.GQLPullRequestReviewComment, gh github.CopilotUserChecker, job *jobs.Job, authorResolver AuthorResolver, resolvedMap map[int64]bool) (*Comment, error) {
	if reviewComment.Body == "" {
		return nil, nil
	}

	// Hasn't been handled in a past Job + Isn't authored by Copilot + Review thread isn't marked as resolved
	new := slices.Contains(job.ReviewIDs, reviewComment.PullRequestReview.GetID()) && !reviewComment.Author.IsCopilot(gh) && !resolvedMap[reviewComment.GetID()]

	resolvedAuthor, err := author(ctx, authorResolver, reviewComment.Author, gh)
	if err != nil {
		return nil, fmt.Errorf("failed to get author: %w", err)
	}

	var id int64
	if new {
		id = reviewComment.GetID()
	}
	return &Comment{
		XMLName:   xmlName(new),
		ID:        id,
		New:       new,
		Timestamp: reviewComment.PublishedAt.Unix(),
		Author:    resolvedAuthor,
		Body:      body(reviewComment.Body),
	}, nil
}

func pullRequestReviewCommentSortFunc(a, b *github.GQLPullRequestReviewComment) int {
	return cmp.Compare(a.PublishedAt.Unix(), b.PublishedAt.Unix())
}

func xmlName(new bool) xml.Name {
	if new {
		return xml.Name{Local: XMLCommentNew}
	}
	return xml.Name{Local: XMLCommentOld}
}

func author(ctx context.Context, authorResolver AuthorResolver, a github.GQLActor, gh github.CopilotUserChecker) (authorLogin string, err error) {
	if a.IsCopilot(gh) {
		return "@copilot", nil
	} else if a.IsBot() {
		return a.GetLogin() + "[bot]", nil
	} else {
		displayLogin, err := authorResolver.Resolve(ctx, uint64(a.GetID()), a.GetLogin())
		if err != nil {
			return "", fmt.Errorf("failed to resolve display login for user ID: %w", err)
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
func lines(comment *github.GQLPullRequestReviewComment) (int, int) {
	var end, start int
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
	sb.Write(xb)
	sb.WriteString("\n")
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
	sb.WriteString("\n<")
	sb.WriteString(tag)
	sb.WriteString(">\n")
}

func closeXMLTag(sb *strings.Builder, tag string) {
	sb.WriteString("\n</")
	sb.WriteString(tag)
	sb.WriteString(">\n")
}

func xmlTag(sb *strings.Builder, tag string, content string) {
	sb.WriteString("<")
	sb.WriteString(tag)
	sb.WriteString(">")
	sb.WriteString(content)
	sb.WriteString("</")
	sb.WriteString(tag)
	sb.WriteString(">\n")
}

func newLine(sb *strings.Builder) {
	sb.WriteString("\n")
}

func newLines(sb *strings.Builder, n int) {
	for range n {
		newLine(sb)
	}
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
	if err := requestctx.AddProblemStatement(ctx, ctxps); err != nil {
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

// Removes any lines after PullRequestBodySuffixSeparator that specify what issue the PR fixes.
func RemoveFixesInSuffix(body string) string {
	// Find the suffix separator
	suffixIndex := strings.Index(body, jobutils.PullRequestBodySuffixSeparator)
	if suffixIndex == -1 {
		// No suffix separator found, return the body as-is
		return body
	}

	// Split into prefix and suffix
	prefix := body[:suffixIndex+len(jobutils.PullRequestBodySuffixSeparator)]
	suffix := body[suffixIndex+len(jobutils.PullRequestBodySuffixSeparator):]

	// Process the suffix line by line
	lines := strings.Split(suffix, "\n")
	var filteredLines []string

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		// Skip lines that start with "Fixes", "* Fixes", or "- Fixes"
		if strings.HasPrefix(trimmed, "Fixes") || strings.HasPrefix(trimmed, "* Fixes") || strings.HasPrefix(trimmed, "- Fixes") {
			continue
		}
		filteredLines = append(filteredLines, line)
	}

	return prefix + strings.Join(filteredLines, "\n")
}
