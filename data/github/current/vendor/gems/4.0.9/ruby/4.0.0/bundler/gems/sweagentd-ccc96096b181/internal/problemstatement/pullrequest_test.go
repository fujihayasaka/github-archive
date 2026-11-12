package problemstatement

import (
	"cmp"
	"context"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/tips"
	"github.com/stretchr/testify/require"
)

func TestPullRequestCommentOrderingAndFiltering(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	actx.PullRequest.Reviews.Nodes = []github.GQLPullRequestReview{ // out of order
		*testPullRequestReview(*actorWriter(), false, 100, "review writer one", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentLine(*actorWriter(), false, 101, 100, "review 1 comment one", "", 0, 0),
			*prReviewCommentLine(*actorWriter(), true, 102, 100, "review 1 comment minimized", "", 0, 0), // minimized
			*prReviewCommentLine(*actorBot(), false, 104, 100, "review 1 comment bot", "", 0, 0),         // bot
			*prReviewCommentLine(*actorReader(), false, 105, 100, "review 1 comment reader", "", 0, 0),   // reader
			*prReviewCommentLine(*actorCopilot(), false, 103, 100, "review 1 comment copilot", "", 0, 0), // copilot
			*prReviewCommentLine(*actorWriter(), false, 106, 100, "review 1 comment six", "", 0, 0),
		}),
		*testPullRequestReview(*actorWriter(), false, 600, "review writer six", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentFile(*actorWriter(), false, 601, 600, "review 6 comment one", ""),
			*prReviewCommentFile(*actorWriter(), true, 602, 600, "review 6 comment minimized", ""), // minimized
			*prReviewCommentFile(*actorBot(), false, 604, 600, "review 6 comment bot", ""),         // bot
			*prReviewCommentFile(*actorReader(), false, 605, 600, "review 6 comment reader", ""),   // reader
			*prReviewCommentFile(*actorCopilot(), false, 603, 600, "review 6 comment copilot", ""), // copilot
			*prReviewCommentFile(*actorWriter(), false, 606, 600, "review 6 comment six", ""),
		}),
		*testPullRequestReview(*actorWriter(), true, 200, "review minimized", []github.GQLPullRequestReviewComment{ // minimized
			*prReviewCommentLine(*actorWriter(), false, 201, 200, "review 2 comment one", "", 0, 0),
		}),
		*testPullRequestReview(*actorBot(), false, 400, "review bot", []github.GQLPullRequestReviewComment{ // bot
			*prReviewCommentLine(*actorWriter(), false, 401, 400, "review 4 comment one", "", 0, 0),
		}),
		*testPullRequestReview(*actorReader(), false, 500, "review reader", []github.GQLPullRequestReviewComment{ // reader
			*prReviewCommentLine(*actorWriter(), false, 501, 500, "review 5 comment one", "", 0, 0),
		}),
		*testPullRequestReview(*actorCopilot(), false, 300, "review copilot", []github.GQLPullRequestReviewComment{ // copilot
			*prReviewCommentLine(*actorWriter(), false, 301, 300, "review 3 comment one", "", 0, 0),
		}),
		*testPullRequestReview(*actorWriter(), false, 700, "review writer seven", []github.GQLPullRequestReviewComment{ // copilot
			*prReviewCommentLine(*actorWriter(), false, 701, 700, "review 7 comment one", "", 0, 0),
		}),
	}

	oldJob := getJob()
	oldJob.ReviewIDs = getReviewIDs(100, 200, 300, 400, 500) // mark some as processed (old)
	review := actx.PullRequest.Reviews.Nodes[1]
	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         review.Author.GetID(),
		Login:      review.Author.GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{oldJob}, job, appProvider.IsAgenticActor)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content
	commitCount := problemStatement.CommitCount

	require.NotEmpty(t, statement)

	// reviews
	require.Contains(t, statement, "review writer one")
	require.Contains(t, statement, "review writer six")
	require.Contains(t, statement, "review writer seven")
	require.Contains(t, statement, "review copilot")

	require.NotContains(t, statement, "review minimized")
	require.NotContains(t, statement, "review bot")
	require.NotContains(t, statement, "review reader")

	// comments
	require.Contains(t, statement, "comment copilot")
	require.Contains(t, statement, "comment one")
	require.Contains(t, statement, "comment six")

	require.NotContains(t, statement, "comment minimized")
	require.NotContains(t, statement, "comment bot")
	require.NotContains(t, statement, "comment reader")

	type index struct {
		Index     int
		Timestamp int64
	}
	indexes := []index{}

	// Find the indexes of the comments in the statement
	for _, review := range actx.PullRequest.Reviews.Nodes {
		i := strings.Index(statement, review.Body)
		if i >= 0 {
			indexes = append(indexes, index{
				Index:     i,
				Timestamp: review.SubmittedAt.Unix(),
			})
			for _, comment := range review.Comments.Nodes {
				i = strings.Index(statement, comment.Body)
				if i >= 0 {
					indexes = append(indexes, index{
						Index:     i,
						Timestamp: comment.PublishedAt.Unix(),
					})
				}
			}
		}
	}

	// Sort the indexes so we can check the order of the comments
	slices.SortStableFunc(indexes, func(i, j index) int {
		return cmp.Compare(i.Index, j.Index)
	})

	// Check the indexes are sorted by published at date
	isSorted := slices.IsSortedFunc(indexes, func(i, j index) int {
		return cmp.Compare(i.Timestamp, j.Timestamp)
	})

	require.True(t, isSorted, "pull request reviews and comments are not sorted by published at date")

	require.Equal(t, commitCount, actx.PullRequest.Commits.TotalCount)
	require.Contains(t, statement, "The last **5** git commits in this branch")
}

func TestAutoFilterOldPRCommentContents(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	actx.PullRequest.Comments.Nodes = []github.GQLIssueComment{
		*testIssueComment(*actorWriter(), false, 101, "comment writer one"),
		*testIssueComment(*actorWriter(), false, 102, "comment writer two"),
		*testIssueComment(*actorWriter(), false, 103, "comment writer three"),
		*testIssueComment(*actorWriter(), false, 104, "comment writer four"),
		*testIssueComment(*actorWriter(), false, 105, "comment writer five"),
	}

	actx.PullRequest.Comments.Nodes[2].Body += strings.Repeat("-", tooBigCharacterCount)

	oldJob := getJob()
	oldJob.CommentIDs = getCommentIDs(100, 200, 300) // mark some as processed (old)
	comment := actx.PullRequest.Comments.Nodes[3]
	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         comment.Author.GetID(),
		Login:      comment.Author.GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{oldJob}, job, appProvider.IsAgenticActor)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content
	commitCount := problemStatement.CommitCount

	require.NotEmpty(t, statement)
	// Too long comment should be truncated
	require.Contains(t, statement, "----...")
	// But all comments should be present
	require.Contains(t, statement, "writer one")
	require.Contains(t, statement, "writer two")
	require.Contains(t, statement, "writer three")
	require.Contains(t, statement, "writer four")
	require.Contains(t, statement, "writer five")

	require.Equal(t, commitCount, actx.PullRequest.Commits.TotalCount)
	require.Contains(t, statement, "The last **5** git commits in this branch")
}

func TestPRCommentCountAutoReduction(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	actx.PullRequest.Comments.Nodes = []github.GQLIssueComment{
		*testIssueComment(*actorWriter(), false, 101, "comment writer one"),
		*testIssueComment(*actorWriter(), false, 102, "comment writer two"),
		*testIssueComment(*actorWriter(), false, 103, "comment writer three"),
		*testIssueComment(*actorWriter(), false, 104, "comment writer four"),
		*testIssueComment(*actorWriter(), false, 105, "comment writer five"),
	}

	actx.PullRequest.Comments.Nodes[2].Body += strings.Repeat("-", tooBigCharacterCount)
	actx.PullRequest.Comments.Nodes[3].Body += strings.Repeat("-", tooBigCharacterCount)

	oldJob := getJob()
	oldJob.CommentIDs = getCommentIDs(100, 200, 300) // mark some as processed (old)
	comment := actx.PullRequest.Comments.Nodes[3]
	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         comment.Author.GetID(),
		Login:      comment.Author.GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{oldJob}, job, appProvider.IsAgenticActor)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content
	commitCount := problemStatement.CommitCount

	require.NotEmpty(t, statement)
	// Too long comment should be truncated
	require.Contains(t, statement, "----...")
	// But all comments should be present
	require.Contains(t, statement, "writer one")
	require.Contains(t, statement, "writer two")
	require.Contains(t, statement, "writer three")
	require.Contains(t, statement, "writer four")
	require.Contains(t, statement, "writer five")

	require.Equal(t, commitCount, actx.PullRequest.Commits.TotalCount)
	require.Contains(t, statement, "The last **5** git commits in this branch")
}

func TestPullRequestBuilderUsesAgentMentionSlug(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	actx := getPullRequestContext()

	copilot := agenticapptest.NewTestCopilot(t)
	customApp := agenticapptest.NewTestApp(12345)
	appProvider := agenticapp.NewProvider(copilot, customApp)

	job := getJob()
	job.AgentID = customApp.AppID()

	problemStatement, err := NewPullRequestBuilder(
		obsv,
		actx,
		job,
		mockAuthorResolver{},
		appProvider,
	).Build(ctx)
	require.NoError(t, err)

	mentionableSlug, err := mentionableSlugForAgent(appProvider, job.AgentID)
	require.NoError(t, err)
	require.Contains(t, problemStatement.Content, pullRequestCommentsHeading(mentionableSlug))
}

func TestReviewFileAndLineNumbers(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	actx.PullRequest.Reviews.Nodes = []github.GQLPullRequestReview{ // out of order
		*testPullRequestReview(*actorWriter(), false, 100, "review writer one", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentLine(*actorWriter(), false, 101, 100, "review 1 comment line multi", "my/line/path", 8, 20),
			*prReviewCommentLine(*actorWriter(), false, 102, 100, "review 1 comment line single", "my/one/path", 8, 8),
			*prReviewCommentFile(*actorWriter(), false, 103, 100, "review 1 comment file", "my/file/path"),
		}),
	}

	review := actx.PullRequest.Reviews.Nodes[0]
	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         review.Author.GetID(),
		Login:      review.Author.GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{}, job, appProvider.IsAgenticActor)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content

	require.NotEmpty(t, statement)

	require.Contains(t, statement, "review writer one")
	require.Contains(t, statement, "review 1 comment line multi")
	require.Contains(t, statement, "my/line/path:8-20")
	require.Contains(t, statement, "review 1 comment line single")
	require.Contains(t, statement, "my/one/path:8")
	require.Contains(t, statement, "review 1 comment file")
	require.Contains(t, statement, "my/file/path")
}

func TestReviewCommentsArePresentForNew(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	actx.PullRequest.Reviews.Nodes = []github.GQLPullRequestReview{ // out of order
		*testPullRequestReview(*actorWriter(), false, 100, "review writer one", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentLine(*actorWriter(), false, 101, 100, "review 1 comment line multi", "my/line/path", 8, 20),
			*prReviewCommentLine(*actorWriter(), false, 102, 100, "review 1 comment line single", "my/one/path", 8, 8),
			*prReviewCommentFile(*actorWriter(), false, 103, 100, "review 1 comment file", "my/file/path"),
		}),
		*testPullRequestReview(*actorWriter(), false, 200, "review writer two", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentLine(*actorWriter(), false, 201, 200, "review 2 comment line multi", "my/line/path", 8, 20),
			*prReviewCommentLine(*actorWriter(), false, 202, 200, "review 2 comment line single", "my/one/path", 8, 8),
			*prReviewCommentFile(*actorWriter(), false, 203, 200, "review 2 comment file", "my/file/path"),
		}),
	}

	for _, review := range actx.PullRequest.Reviews.Nodes {
		fmt.Println(review.PublishedAt)
		for _, comment := range review.Comments.Nodes {
			fmt.Println(comment.PublishedAt)
		}
	}

	oldJob := getJob()
	oldJob.ReviewIDs = getReviewIDs(100) // mark some as processed (old)
	review := actx.PullRequest.Reviews.Nodes[1]
	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         review.Author.GetID(),
		Login:      review.Author.GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{oldJob}, job, appProvider.IsAgenticActor)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content

	require.NotEmpty(t, statement)

	rid, _ := idsFromStrings(NameForIDsPullRequestReview, strconv.Itoa(200))
	require.Contains(t, statement, fmt.Sprintf("<comment_id>%d</comment_id>", rid))

	// First review comments in a thread should include the comment ID
	for _, id := range getReviewCommentIDs(201, 202, 203) {
		require.Contains(t, statement, fmt.Sprintf("<comment_id>%d</comment_id>", id))
	}
}

func TestTipSectionIsRemoved(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	actx.PullRequest.Reviews.Nodes = []github.GQLPullRequestReview{ // out of order
		*testPullRequestReview(*actorWriter(), false, 100, "review writer one", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentLine(*actorWriter(), false, 101, 100, "review 1 comment line multi", "my/line/path", 8, 20),
			*prReviewCommentLine(*actorWriter(), false, 102, 100, "review 1 comment line single", "my/one/path", 8, 8),
			*prReviewCommentFile(*actorWriter(), false, 103, 100, "review 1 comment file", "my/file/path"),
		}),
	}

	// Add a tip
	actx.PullRequest.Body = actx.PullRequest.Body + tips.PullRequestBodyTipSeparator + github.FeedbackTip

	review := actx.PullRequest.Reviews.Nodes[0]
	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         review.Author.GetID(),
		Login:      review.Author.GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{}, job, appProvider.IsAgenticActor)

	require.Contains(t, actx.PullRequest.Body, github.FeedbackTip)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content

	require.NotEmpty(t, statement)
	require.NotContains(t, statement, github.FeedbackTip)
	require.NotContains(t, statement, tips.PullRequestBodyTipSeparator)
}

func TestBestPracticesTipIsRemoved(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	actx.PullRequest.Reviews.Nodes = []github.GQLPullRequestReview{ // out of order
		*testPullRequestReview(*actorWriter(), false, 100, "review writer one", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentLine(*actorWriter(), false, 101, 100, "review 1 comment line multi", "my/line/path", 8, 20),
			*prReviewCommentLine(*actorWriter(), false, 102, 100, "review 1 comment line single", "my/one/path", 8, 8),
			*prReviewCommentFile(*actorWriter(), false, 103, 100, "review 1 comment file", "my/file/path"),
		}),
	}

	// Add a tips advert
	actx.PullRequest.Body = actx.PullRequest.Body + tips.PullRequestBodyTipSeparator + github.BestPracticesTip

	review := actx.PullRequest.Reviews.Nodes[0]
	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         review.Author.GetID(),
		Login:      review.Author.GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{}, job, appProvider.IsAgenticActor)

	require.Contains(t, actx.PullRequest.Body, github.BestPracticesTip)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content

	require.NotEmpty(t, statement)
	require.NotContains(t, statement, github.BestPracticesTip)
}

func TestCopilotCommentAreTreatedAsOld(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	actx.PullRequest.Reviews.Nodes = []github.GQLPullRequestReview{ // out of order
		*testPullRequestReview(*actorWriter(), false, 100, "review writer one", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentLine(*actorWriter(), false, 101, 100, "review 1 comment one", "", 0, 0),
			*prReviewCommentLine(*actorWriter(), true, 102, 100, "review 1 comment minimized", "", 0, 0), // minimized
			*prReviewCommentLine(*actorBot(), false, 104, 100, "review 1 comment bot", "", 0, 0),         // bot
			*prReviewCommentLine(*actorReader(), false, 105, 100, "review 1 comment reader", "", 0, 0),   // reader
			*prReviewCommentLine(*actorCopilot(), false, 103, 100, "review 1 comment copilot", "", 0, 0), // copilot
			*prReviewCommentLine(*actorWriter(), false, 106, 100, "review 1 comment six", "", 0, 0),
		}),
		*testPullRequestReview(*actorWriter(), false, 600, "review writer six", []github.GQLPullRequestReviewComment{ // out of order
			*prReviewCommentFile(*actorWriter(), false, 601, 600, "review 6 comment one", ""),
			*prReviewCommentFile(*actorWriter(), true, 602, 600, "review 6 comment minimized", ""), // minimized
			*prReviewCommentFile(*actorBot(), false, 604, 600, "review 6 comment bot", ""),         // bot
			*prReviewCommentFile(*actorReader(), false, 605, 600, "review 6 comment reader", ""),   // reader
			*prReviewCommentFile(*actorCopilot(), false, 603, 600, "review 6 comment copilot", ""), // copilot
			*prReviewCommentFile(*actorWriter(), false, 606, 600, "review 6 comment six", ""),
		}),
	}

	actx.PullRequest.Comments.Nodes = []github.GQLIssueComment{
		*testIssueComment(*actorWriter(), false, 200, "comment writer one"),
		*testIssueComment(*actorCopilot(), false, 201, "comment copilot two"),
		*testIssueComment(*actorWriter(), false, 202, "comment writer three"),
		*testIssueComment(*actorCopilot(), false, 203, "comment copilot four"),
	}

	oldJob := getJob()
	oldJob.ReviewIDs = []int64{}  // all reviews are new
	oldJob.CommentIDs = []int64{} // all comments are new

	review := actx.PullRequest.Reviews.Nodes[0]
	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         review.Author.GetID(),
		Login:      review.Author.GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{oldJob}, job, appProvider.IsAgenticActor)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content

	require.NotEmpty(t, statement)

	// First review comments in a thread should include the comment ID
	for _, id := range getReviewIDs(100, 600) {
		require.Contains(t, statement, fmt.Sprintf("<comment_id>%d</comment_id>", id))
	}

	for _, id := range getReviewCommentIDs(101, 106, 601, 606) {
		require.Contains(t, statement, fmt.Sprintf("<comment_id>%d</comment_id>", id))
	}

	for _, id := range getReviewCommentIDs(102, 103, 104, 105, 602, 603, 604, 605) {
		require.NotContains(t, statement, fmt.Sprintf("<comment_id>%d</comment_id>", id))
	}

	// All copilot comments should be marked as old
	require.Contains(t, statement, "<comment_old>\n<author>@copilot</author>")
	require.NotContains(t, statement, "<comment_new>\n<author>@copilot</author>")
}

func TestPullRequestBuilder_AuthorResolverIntegration(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	actx := getPullRequestContext()

	// Add different types of comments and reviews to test author resolution
	actx.PullRequest.Comments.Nodes = []github.GQLIssueComment{
		*testIssueComment(*actorWriter(), false, 101, "Issue comment from writer user"),
		*testIssueComment(*actorCopilot(), false, 102, "Issue comment from copilot"),
	}

	actx.PullRequest.Reviews.Nodes = []github.GQLPullRequestReview{
		*testPullRequestReview(*actorWriter(), false, 200, "Review from writer user", []github.GQLPullRequestReviewComment{
			*prReviewCommentLine(*actorWriter(), false, 201, 200, "Review comment from writer user", "", 0, 0),
			*prReviewCommentLine(*actorCopilot(), false, 202, 200, "Review comment from copilot", "", 0, 0),
		}),
		*testPullRequestReview(*actorCopilot(), false, 300, "Review from copilot", []github.GQLPullRequestReviewComment{
			*prReviewCommentLine(*actorWriter(), false, 301, 300, "Review comment reply from writer", "", 0, 0),
		}),
	}

	// Create a job to trigger the problem statement building
	assigner := *actorWriter()
	job := assignment.NewJob(jobs.AgentActionFixPRComment,
		jobs.JobActor{
			ID:         assigner.GetID(),
			Login:      assigner.GetLogin(),
			TrackingID: "tracking-id",
		},
		actx.PullRequest.HeadRef.Name)

	// Set up the job to include all comments/reviews as new
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{}, job, appProvider.IsAgenticActor)

	expectedDisplayLogin := "resolved-writer"
	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{expectedID: uint64(assigner.GetID()), expectedDisplayLogin: expectedDisplayLogin}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content
	require.NotEmpty(t, statement)

	// Verify that the resolved display login is used for the writer user in issue comments
	require.Contains(t, statement, "@"+expectedDisplayLogin, "problem statement should contain resolved display login")
	require.Contains(t, statement, "Issue comment from writer user")

	// Verify that the resolved display login is used for the writer user in reviews and review comments
	require.Contains(t, statement, "Review from writer user")
	require.Contains(t, statement, "Review comment from writer user")
	require.Contains(t, statement, "Review comment reply from writer")

	// Verify that copilot comments use @copilot (not resolved via author resolver)
	require.Contains(t, statement, "@copilot")
	require.Contains(t, statement, "Issue comment from copilot")
	require.Contains(t, statement, "Review from copilot")
	require.Contains(t, statement, "Review comment from copilot")

	// Ensure we don't have the original login in the statement since it should be resolved
	require.NotContains(t, statement, "@"+actorWriter().GetLogin(), "should not contain original login, should be resolved")
}

type mockAuthorResolver struct {
	expectedID           uint64
	expectedDisplayLogin string
}

func (m mockAuthorResolver) Resolve(ctx context.Context, authorID uint64, authorLogin string) (string, error) {
	if authorID == m.expectedID {
		return m.expectedDisplayLogin, nil
	}

	return authorLogin, nil
}

func TestPullRequestReviewThreadResolved(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}
	assignment := getAssignment()

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)

	actx := getPullRequestContext()

	// Create review comments for two threads
	resolvedComment := prReviewCommentLine(*actorWriter(), false, 100, 10, "This is a resolved comment", "file1.go", 10, 15)
	unresolvedComment := prReviewCommentLine(*actorWriter(), false, 101, 10, "This is an unresolved comment", "file2.go", 20, 25)

	actx.PullRequest.Reviews.Nodes = []github.GQLPullRequestReview{
		*testPullRequestReview(*actorWriter(), false, 10, "review with threads", []github.GQLPullRequestReviewComment{
			*resolvedComment,
			*unresolvedComment,
		}),
	}

	// Create review threads with resolved/unresolved status
	actx.PullRequest.ReviewThreads = github.GQLConnection[github.GQLPullRequestReviewThread]{
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

	job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
		ID:         actorWriter().GetID(),
		Login:      actorWriter().GetLogin(),
		TrackingID: "tracking-id",
	}, actx.PullRequest.HeadRef.Name)

	// Mark review as new (unprocessed) so comments are eligible to be marked as new
	jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{}, job, appProvider.IsAgenticActor)

	problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content
	require.NotEmpty(t, statement)

	require.Contains(t, statement, "This is a resolved comment", "should contain the resolved comment")
	require.Contains(t, statement, `<comment_thread_resolved>`, "should have <comment_thread_resolved> for resolved thread")

	require.Contains(t, statement, "This is an unresolved comment", "should contain the unresolved comment")
	require.Contains(t, statement, `<comment_thread>`, "should have <comment_thread> for unresolved thread")

	// Critical: Comments in resolved threads should be marked as OLD, not NEW
	// This is because resolved threads are considered "done" and should not trigger new work
	require.Contains(t, statement, "<comment_old>", "should contain old comment tags")

	// The resolved comment should be marked as old (resolved = already handled)
	// Note: The XML format doesn't include <body> tags - the body is directly in the comment element
	require.Contains(t, statement, `<comment_old>
<author>@actor-write</author>
This is a resolved comment
</comment_old>`, "resolved comment should be marked as old")

	// The unresolved comment should be marked as new (needs attention) with a comment_id
	unresolvedCommentIDs := getReviewCommentIDs(101)
	require.Contains(t, statement, fmt.Sprintf("<comment_id>%d</comment_id>", unresolvedCommentIDs[0]), "unresolved comment should have comment_id")
	require.Contains(t, statement, `This is an unresolved comment`, "should contain unresolved comment text")

	// Verify the unresolved comment is wrapped in comment_new tags
	require.Regexp(t, `<comment_new>\s*<comment_id>\d+</comment_id>\s*<author>@actor-write</author>\s*This is an unresolved comment\s*</comment_new>`, statement, "unresolved comment should be marked as new")
}

func TestStackedPRContext(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	appProvider := agenticapptest.NewTestProviderWithLogins(t, GitHubAppLogin, GitHubBotLogin)
	assignment := getAssignment()

	t.Run("includes stacked PR context when base branch differs from default", func(t *testing.T) {
		actx := getPullRequestContext()
		// Set up a stacked PR: base branch is "feature-branch", not "main"
		actx.PullRequest.BaseRef = github.GQLRef{Name: "feature-branch"}
		actx.PullRequest.HeadRef = github.GQLRef{Name: "my-fix-branch"}
		actx.Repository.DefaultBranchRef = &github.GQLRef{Name: "main"}

		job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
			ID:         actorWriter().GetID(),
			Login:      actorWriter().GetLogin(),
			TrackingID: "tracking-id",
		}, actx.PullRequest.HeadRef.Name)

		problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
		require.NoError(t, err)

		statement := problemStatement.Content
		require.NotEmpty(t, statement)

		// Should include stacked PR context
		require.Contains(t, statement, "<stacked_pr_context>", "should contain stacked PR context opening tag")
		require.Contains(t, statement, "</stacked_pr_context>", "should contain stacked PR context closing tag")
		require.Contains(t, statement, "feature-branch", "should mention the base branch name")
		require.Contains(t, statement, "main", "should mention the default branch name")
		require.Contains(t, statement, "my-fix-branch", "should mention the head branch name")
		require.Contains(t, statement, "stacked pull request", "should explain this is a stacked PR")
	})

	t.Run("excludes stacked PR context when base branch is default branch", func(t *testing.T) {
		actx := getPullRequestContext()
		// Standard PR: base branch is "main", same as default
		actx.PullRequest.BaseRef = github.GQLRef{Name: "main"}
		actx.Repository.DefaultBranchRef = &github.GQLRef{Name: "main"}

		job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
			ID:         actorWriter().GetID(),
			Login:      actorWriter().GetLogin(),
			TrackingID: "tracking-id",
		}, actx.PullRequest.HeadRef.Name)

		problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
		require.NoError(t, err)

		statement := problemStatement.Content
		require.NotEmpty(t, statement)

		// Should not include stacked PR context
		require.NotContains(t, statement, "<stacked_pr_context>", "should not contain stacked PR context for regular PRs")
	})

	t.Run("excludes stacked PR context when base branch is empty", func(t *testing.T) {
		actx := getPullRequestContext()
		// Base branch not set (empty)
		actx.PullRequest.BaseRef = github.GQLRef{Name: ""}
		actx.Repository.DefaultBranchRef = &github.GQLRef{Name: "main"}

		job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
			ID:         actorWriter().GetID(),
			Login:      actorWriter().GetLogin(),
			TrackingID: "tracking-id",
		}, actx.PullRequest.HeadRef.Name)

		problemStatement, err := NewPullRequestBuilder(obsv, actx, job, mockAuthorResolver{}, appProvider).Build(ctx)
		require.NoError(t, err)

		statement := problemStatement.Content
		require.NotEmpty(t, statement)

		// Should not include stacked PR context
		require.NotContains(t, statement, "<stacked_pr_context>", "should not contain stacked PR context when base branch is empty")
	})
}
