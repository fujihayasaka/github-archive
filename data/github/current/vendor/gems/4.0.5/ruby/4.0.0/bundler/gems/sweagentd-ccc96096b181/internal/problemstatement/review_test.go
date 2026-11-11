package problemstatement

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/require"
)

// newJobWithReviewFeatures creates a job with review features set for stacked PR scenarios
func newJobWithReviewFeatures(reviewID int64, prNumber int) *jobs.Job {
	return &jobs.Job{
		ReviewIDs: []int64{reviewID},
		Features: jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: fmt.Sprintf("[WIP] Stack PR for #%d", prNumber),
				BodyPlaceholder:  fmt.Sprintf("Thanks for the feedback on #%d. I've created this new PR, which merges into #%d, to address your comment. I will work on the changes and keep this PR's description up to date as I make progress.", prNumber, prNumber),
			},
		},
	}
}

// TestReviewBuilder_TopLevelReview tests a simple top-level review without replies
func TestReviewBuilder_TopLevelReview(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	reviewIndex := 1000
	review := testPullRequestReview(*actorWriter(), false, reviewIndex, "Please fix the linting issues @copilot", []github.GQLPullRequestReviewComment{})
	actualReviewID := review.GetID()

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}
	pr.Commits.TotalCount = 3

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(actualReviewID, pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, actualReviewID, mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)
	require.Contains(t, statement, "Please fix the linting issues @copilot")
	require.Contains(t, statement, "This stacked PR was created to address a specific review comment")
	require.Contains(t, statement, "<pr_title>")
	require.Contains(t, statement, fmt.Sprintf("[WIP] Stack PR for #%d", pr.Number))
	require.Contains(t, statement, "</pr_title>")
	require.Contains(t, statement, "<pr_description>")
	require.Contains(t, statement, "Thanks for the feedback")
	require.Contains(t, statement, "</pr_description>")
	require.Equal(t, 3, ps.CommitCount)
	require.Equal(t, jobs.ProblemStatementContentFilterModeMarkdown, ps.ContentFilterMode)

	// Verify the problem statement source is set correctly
	ctxps, ok := requestctx.ProblemStatement(ctx)
	require.True(t, ok)
	require.Equal(t, "review_reply", ctxps.Source)
}

// TestReviewBuilder_ReviewWithInlineComments tests a review with inline code comments
func TestReviewBuilder_ReviewWithInlineComments(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	reviewIndex := 2000
	comment1 := prReviewCommentLine(*actorWriter(), false, 2001, reviewIndex, "This needs error handling", "src/main.go", 42, 42)
	comment2 := prReviewCommentLine(*actorWriter(), false, 2002, reviewIndex, "Add tests for this function", "src/utils.go", 10, 15)

	review := testPullRequestReview(*actorWriter(), false, reviewIndex, "Code review feedback @copilot", []github.GQLPullRequestReviewComment{*comment1, *comment2})

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(review.GetID(), pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)
	require.Contains(t, statement, "Code review feedback @copilot")
	require.Contains(t, statement, "This needs error handling")
	require.Contains(t, statement, "Add tests for this function")
	require.Contains(t, statement, "src/main.go:42")
	require.Contains(t, statement, "src/utils.go:10-15")
	require.Contains(t, statement, "comment_thread")
}

// TestReviewBuilder_ReviewCommentReply tests a reply to a review comment
func TestReviewBuilder_ReviewCommentReply(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	// Original review with a comment
	originalReviewIndex := 3000
	originalComment := prReviewCommentLine(*actorWriter(), false, 3001, originalReviewIndex, "This code needs better error handling", "src/parser.go", 100, 105)
	originalReview := testPullRequestReview(*actorWriter(), false, originalReviewIndex, "", []github.GQLPullRequestReviewComment{*originalComment})
	originalReview.State = github.GQLPullRequestReviewStateCommented

	// Reply review
	replyReviewIndex := 3010
	replyComment := prReviewCommentLine(*actorWriter(), false, 3011, replyReviewIndex, "@copilot can you fix this?", "src/parser.go", 100, 105)
	replyComment.ReplyTo = &github.GQLReplyTo{ID: github.FullDatabaseID(originalComment.GetID())}
	replyReview := testPullRequestReview(*actorWriter(), false, replyReviewIndex, "", []github.GQLPullRequestReviewComment{*replyComment})
	replyReview.State = github.GQLPullRequestReviewStateCommented

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*originalReview, *replyReview},
		TotalCount: 2,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(replyReview.GetID(), pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, replyReview.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Should include both the original comment and the reply
	require.Contains(t, statement, "This code needs better error handling")
	require.Contains(t, statement, "@copilot can you fix this?")
	require.Contains(t, statement, "src/parser.go:100-105")
	require.Contains(t, statement, "comment_thread")

	// The original comment should appear before the reply in the output
	originalIdx := strings.Index(statement, "This code needs better error handling")
	replyIdx := strings.Index(statement, "@copilot can you fix this?")
	require.Less(t, originalIdx, replyIdx, "Original comment should appear before reply")
}

// TestReviewBuilder_MultipleRepliesInThread tests a thread with multiple replies
func TestReviewBuilder_MultipleRepliesInThread(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	// Root comment
	rootReviewIndex := 4000
	rootComment := prReviewCommentLine(*actorWriter(), false, 4001, rootReviewIndex, "What about edge cases?", "src/validator.go", 50, 50)
	rootReview := testPullRequestReview(*actorWriter(), false, rootReviewIndex, "", []github.GQLPullRequestReviewComment{*rootComment})
	rootReview.State = github.GQLPullRequestReviewStateCommented

	// First reply
	reply1ReviewIndex := 4010
	reply1Comment := prReviewCommentLine(*actorAdmin(), false, 4011, reply1ReviewIndex, "Good point, we should handle null values", "src/validator.go", 50, 50)
	reply1Comment.ReplyTo = &github.GQLReplyTo{ID: github.FullDatabaseID(rootComment.GetID())}
	reply1Review := testPullRequestReview(*actorAdmin(), false, reply1ReviewIndex, "", []github.GQLPullRequestReviewComment{*reply1Comment})
	reply1Review.State = github.GQLPullRequestReviewStateCommented

	// Second reply (to the first reply)
	reply2ReviewIndex := 4020
	reply2Comment := prReviewCommentLine(*actorWriter(), false, 4021, reply2ReviewIndex, "@copilot please implement this", "src/validator.go", 50, 50)
	reply2Comment.ReplyTo = &github.GQLReplyTo{ID: github.FullDatabaseID(reply1Comment.GetID())}
	reply2Review := testPullRequestReview(*actorWriter(), false, reply2ReviewIndex, "", []github.GQLPullRequestReviewComment{*reply2Comment})
	reply2Review.State = github.GQLPullRequestReviewStateCommented

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*rootReview, *reply1Review, *reply2Review},
		TotalCount: 3,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(reply2Review.GetID(), pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, reply2Review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Should include all three comments in the thread
	require.Contains(t, statement, "What about edge cases?")
	require.Contains(t, statement, "Good point, we should handle null values")
	require.Contains(t, statement, "@copilot please implement this")

	// Verify they appear in chronological order
	rootIdx := strings.Index(statement, "What about edge cases?")
	reply1Idx := strings.Index(statement, "Good point, we should handle null values")
	reply2Idx := strings.Index(statement, "@copilot please implement this")
	require.Less(t, rootIdx, reply1Idx, "Root comment should appear before first reply")
	require.Less(t, reply1Idx, reply2Idx, "First reply should appear before second reply")
}

// TestReviewBuilder_ReviewNotFound tests error handling when review is not found
func TestReviewBuilder_ReviewNotFound(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{},
		TotalCount: 0,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(999, pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, 999, mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	_, err = builder.Build(ctx)
	require.Error(t, err)
	require.Contains(t, err.Error(), "review with ID 999 not found")
}

// TestReviewBuilder_Truncation tests that long review comments are truncated properly
func TestReviewBuilder_Truncation(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	// Create a very long review body
	longBody := strings.Repeat("This is a very long review comment that will need to be truncated. ", 1000)
	reviewIndex := 5000
	review := testPullRequestReview(*actorWriter(), false, reviewIndex, longBody, []github.GQLPullRequestReviewComment{})

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(review.GetID(), pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Verify the problem statement is within size limits
	base64Length := base64Length(statement)
	require.LessOrEqual(t, base64Length, MaxProblemStatementBase64EncodedLength)

	// Verify truncation was tracked in context
	ctxps, ok := requestctx.ProblemStatement(ctx)
	require.True(t, ok)
	if base64Length > MaxProblemStatementBase64EncodedLength/2 {
		// If it got large enough that truncation might have happened
		require.True(t, ctxps.TruncatedComments, "Truncation tracking should be set if needed")
	}
}

// TestReviewBuilder_ReviewBodyMentionsCopilot_IncludesAllThreads tests that when the review body
// mentions @copilot, all inline comment threads are included in the problem statement.
func TestReviewBuilder_ReviewBodyMentionsCopilot_IncludesAllThreads(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	reviewIndex := 6000
	// Comment 1: mentions @copilot
	comment1 := prReviewCommentLine(*actorWriter(), false, 6001, reviewIndex, "This needs @copilot attention", "src/main.go", 42, 42)
	// Comment 2: does NOT mention @copilot
	comment2 := prReviewCommentLine(*actorWriter(), false, 6002, reviewIndex, "Please fix this indentation", "src/utils.go", 10, 15)

	// Review body mentions @copilot, so both threads should be included
	review := testPullRequestReview(*actorWriter(), false, reviewIndex, "Please review these changes @copilot", []github.GQLPullRequestReviewComment{*comment1, *comment2})

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(review.GetID(), pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Both comments should be included because the review body mentions @copilot
	require.Contains(t, statement, "Please review these changes @copilot")
	require.Contains(t, statement, "This needs @copilot attention")
	require.Contains(t, statement, "Please fix this indentation")
	require.Contains(t, statement, "src/main.go:42")
	require.Contains(t, statement, "src/utils.go:10-15")
}

// TestReviewBuilder_OnlyThreadsWithCopilotMention tests that when the review body does NOT
// mention @copilot, only threads where @copilot is mentioned are included.
func TestReviewBuilder_OnlyThreadsWithCopilotMention(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	reviewIndex := 7000
	// Comment 1: mentions @copilot
	comment1 := prReviewCommentLine(*actorWriter(), false, 7001, reviewIndex, "Can you fix this @copilot?", "src/main.go", 42, 42)
	// Comment 2: does NOT mention @copilot
	comment2 := prReviewCommentLine(*actorWriter(), false, 7002, reviewIndex, "Please fix this indentation", "src/utils.go", 10, 15)

	// Review body does NOT mention @copilot, so only comment1's thread should be included
	review := testPullRequestReview(*actorWriter(), false, reviewIndex, "Some review feedback", []github.GQLPullRequestReviewComment{*comment1, *comment2})

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(review.GetID(), pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Only comment1 should be included because it mentions @copilot
	require.Contains(t, statement, "Some review feedback")
	require.Contains(t, statement, "Can you fix this @copilot?")
	require.Contains(t, statement, "src/main.go:42")

	// Comment2 should NOT be included because it doesn't mention @copilot
	require.NotContains(t, statement, "Please fix this indentation")
	require.NotContains(t, statement, "src/utils.go:10-15")
}

// TestReviewBuilder_ThreadWithReplyMentioningCopilot tests that when a reply in a thread
// mentions @copilot, the entire thread (including the root) is included.
func TestReviewBuilder_ThreadWithReplyMentioningCopilot(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	// Root comment (does NOT mention @copilot)
	rootReviewIndex := 8000
	rootComment := prReviewCommentLine(*actorWriter(), false, 8001, rootReviewIndex, "This code looks suspicious", "src/validator.go", 50, 50)
	rootReview := testPullRequestReview(*actorWriter(), false, rootReviewIndex, "Code review", []github.GQLPullRequestReviewComment{*rootComment})
	rootReview.State = github.GQLPullRequestReviewStateCommented

	// Reply that mentions @copilot
	replyReviewIndex := 8010
	replyComment := prReviewCommentLine(*actorAdmin(), false, 8011, replyReviewIndex, "@copilot can you refactor this?", "src/validator.go", 50, 50)
	replyComment.ReplyTo = &github.GQLReplyTo{ID: github.FullDatabaseID(rootComment.GetID())}
	replyReview := testPullRequestReview(*actorAdmin(), false, replyReviewIndex, "Code review", []github.GQLPullRequestReviewComment{*replyComment})
	replyReview.State = github.GQLPullRequestReviewStateCommented

	// Another root comment that does NOT mention @copilot
	otherReviewIndex := 8020
	otherComment := prReviewCommentLine(*actorWriter(), false, 8021, otherReviewIndex, "Fix the spacing here", "src/parser.go", 100, 100)
	otherReview := testPullRequestReview(*actorWriter(), false, otherReviewIndex, "Code review", []github.GQLPullRequestReviewComment{*otherComment})
	otherReview.State = github.GQLPullRequestReviewStateCommented

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = PullRequestTitle
	pr.Body = PullRequestBody
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*rootReview, *replyReview, *otherReview},
		TotalCount: 3,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(replyReview.GetID(), pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, replyReview.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// The entire thread (root + reply) should be included because the reply mentions @copilot
	require.Contains(t, statement, "This code looks suspicious")
	require.Contains(t, statement, "@copilot can you refactor this?")
	require.Contains(t, statement, "src/validator.go:50")

	// The other comment should NOT be included
	require.NotContains(t, statement, "Fix the spacing here")
	require.NotContains(t, statement, "src/parser.go:100")
}

// TestReviewBuilder_IncludesPRTitleAndDescription tests that the review builder includes PR title and description
func TestReviewBuilder_IncludesPRTitleAndDescription(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	// Create a review
	reviewIndex := 9000
	review := testPullRequestReview(*actorWriter(), false, reviewIndex, "@copilot please help with this", []github.GQLPullRequestReviewComment{})

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = "Fix authentication bug"
	pr.Body = "This PR fixes the authentication bug by updating the token validation logic."
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}
	pr.Commits.TotalCount = 2

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := &jobs.Job{
		ReviewIDs: []int64{review.GetID()},
		Features: jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: "Fix authentication bug",
				BodyPlaceholder:  "This PR fixes the authentication bug by updating the token validation logic.",
			},
		},
	}

	builder := NewReviewBuilder(obsv, actx, job, review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Verify PR title and description are included with proper XML tags
	require.Contains(t, statement, "<pr_title>")
	require.Contains(t, statement, "Fix authentication bug")
	require.Contains(t, statement, "</pr_title>")
	require.Contains(t, statement, "<pr_description>")
	require.Contains(t, statement, "This PR fixes the authentication bug by updating the token validation logic.")
	require.Contains(t, statement, "</pr_description>")

	// Verify the problem statement structure includes the section header
	require.Contains(t, statement, StackedPullRequestSectionHeader)

	// Verify review content is still included
	require.Contains(t, statement, "@copilot please help with this")
}

// TestReviewBuilder_RemovesTipsFromPRBody tests that tips are removed from PR body
func TestReviewBuilder_RemovesTipsFromPRBody(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	// Create a review
	reviewIndex := 9100
	review := testPullRequestReview(*actorWriter(), false, reviewIndex, "@copilot please help", []github.GQLPullRequestReviewComment{})

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = "Test PR"
	// PR body with tips section that should be removed
	pr.Body = "This is the main content.\n\n<!-- START COPILOT CODING AGENT TIPS -->\n---\n\n### Tips\nSome tips here"
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	// Body with tips section that should be removed
	bodyWithTips := "This is the main content.\n\n<!-- START COPILOT CODING AGENT TIPS -->\n---\n\n### Tips\nSome tips here"

	job := &jobs.Job{
		ReviewIDs: []int64{review.GetID()},
		Features: jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: "Test PR",
				BodyPlaceholder:  bodyWithTips,
			},
		},
	}

	builder := NewReviewBuilder(obsv, actx, job, review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Verify main content is present
	require.Contains(t, statement, "This is the main content.")

	// Verify tips section is removed
	require.NotContains(t, statement, "START COPILOT CODING AGENT TIPS")
	require.NotContains(t, statement, "Some tips here")
}

// TestReviewBuilder_UsesJobFeaturesForPRTitleAndDescription tests that when job features are present,
// they are used instead of the original PR title and description
func TestReviewBuilder_UsesJobFeaturesForPRTitleAndDescription(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	// Create a review
	reviewIndex := 9200
	review := testPullRequestReview(*actorWriter(), false, reviewIndex, "@copilot please help", []github.GQLPullRequestReviewComment{})

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = "Original PR Title"
	pr.Body = "Original PR Body"
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}

	actx := &github.PullRequestContext{
		PullRequest: pr,
	}

	job := &jobs.Job{
		ReviewIDs: []int64{review.GetID()},
		Features: jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: "[WIP] Stack PR for addressing review comments",
				BodyPlaceholder:  "This is a stack PR created to address review comments",
			},
		},
	}

	builder := NewReviewBuilder(obsv, actx, job, review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Verify the stacked PR title from job features is used
	require.Contains(t, statement, "[WIP] Stack PR for addressing review comments")
	require.NotContains(t, statement, "Original PR Title")

	// Verify the stacked PR body from job features is used
	require.Contains(t, statement, "This is a stack PR created to address review comments")
	require.NotContains(t, statement, "Original PR Body")
}

func TestReviewBuilder_ResolvedThreads(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()

	// Create review comments for resolved and unresolved threads
	resolvedComment := prReviewCommentLine(*actorWriter(), false, 2001, 2000, "This comment is in a resolved thread @copilot", "main.go", 10, 15)
	unresolvedComment := prReviewCommentLine(*actorWriter(), false, 2002, 2000, "This comment is in an unresolved thread @copilot", "main.go", 20, 25)

	review := testPullRequestReview(*actorWriter(), false, 2000, "Review with resolved and unresolved threads", []github.GQLPullRequestReviewComment{
		*resolvedComment,
		*unresolvedComment,
	})

	pr := getPullRequestContext().PullRequest
	pr.Number = PullRequestNumber
	pr.Title = "Original PR Title"
	pr.Body = "Original PR Body"
	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		Nodes:      []github.GQLPullRequestReview{*review},
		TotalCount: 1,
	}

	// Add review threads with resolved/unresolved status
	pr.ReviewThreads = github.GQLConnection[github.GQLPullRequestReviewThread]{
		TotalCount: 2,
		Nodes: []github.GQLPullRequestReviewThread{
			{
				IsResolved: true,
				Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
					TotalCount: 1,
					Nodes:      []github.GQLPullRequestReviewComment{*resolvedComment},
				},
			},
			{
				IsResolved: false,
				Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
					TotalCount: 1,
					Nodes:      []github.GQLPullRequestReviewComment{*unresolvedComment},
				},
			},
		},
	}

	actx := &github.PullRequestContext{
		Repository:  getPullRequestContext().Repository,
		PullRequest: pr,
	}

	job := newJobWithReviewFeatures(review.GetID(), pr.Number)

	builder := NewReviewBuilder(obsv, actx, job, review.GetID(), mockAuthorResolver{}, agenticapptest.NewTestProvider(t))

	ps, err := builder.Build(ctx)
	require.NoError(t, err)

	statement := ps.Content
	require.NotEmpty(t, statement)

	// Verify the resolved thread has is_resolved="true"
	require.Contains(t, statement, "This comment is in a resolved thread", "should contain the resolved comment")
	require.Contains(t, statement, `<comment_thread_resolved>`, "should have <comment_thread_resolved> for resolved thread")

	// Verify the unresolved thread has is_resolved="false"
	require.Contains(t, statement, "This comment is in an unresolved thread", "should contain the unresolved comment")
	require.Contains(t, statement, `<comment_thread>`, "should have <comment_thread> for unresolved thread")

	// Critical: Comments in resolved threads should be marked as OLD, not NEW
	// This is because resolved threads are considered "done" and should not trigger new work
	require.Contains(t, statement, "<comment_old>", "should contain old comment tags")

	// The resolved comment should be marked as old (resolved = already handled)
	require.Contains(t, statement, `<comment_old>
<author>@actor-write</author>
This comment is in a resolved thread @copilot
</comment_old>`, "resolved comment should be marked as old")

	// The unresolved comment should be marked as new (needs attention) with a comment_id
	unresolvedCommentIDs := getReviewCommentIDs(2002)
	require.Contains(t, statement, fmt.Sprintf("<comment_id>%d</comment_id>", unresolvedCommentIDs[0]), "unresolved comment should have comment_id")
	require.Contains(t, statement, `This comment is in an unresolved thread @copilot`, "should contain unresolved comment text")

	// Verify the unresolved comment is wrapped in comment_new tags
	require.Regexp(t, `<comment_new>\s*<comment_id>\d+</comment_id>\s*<author>@actor-write</author>\s*This comment is in an unresolved thread @copilot\s*</comment_new>`, statement, "unresolved comment should be marked as new")
}
