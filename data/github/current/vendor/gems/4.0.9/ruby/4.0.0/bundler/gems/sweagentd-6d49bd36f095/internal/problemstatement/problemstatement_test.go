package problemstatement

import (
	"encoding/base64"
	"hash/maphash"
	"math"
	mathrand "math/rand"
	"strconv"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/stretchr/testify/require"
)

var seed = maphash.MakeSeed()

var baseTime = time.Now().Add(-(time.Hour * 1000)) // 1000 hours ago

const tooBigCharacterCount = MaxProblemStatementBase64EncodedLength + 1

// idsFromString returns a deterministic ID and NodeID from a string.
// This is useful for ensuring the IDs represent the same entity across different
// types and test runs resolve to the same ID.
func idsFromString(str string) (int64, string) {
	nid := base64.StdEncoding.EncodeToString([]byte(str))
	// limit the length of the node id to 40 characters
	nid = nid[:int(math.Min(40, float64(len(nid))))]
	id := int64(maphash.String(seed, str)) & 0x7FFFFFFFFFFFFFFF
	return id, nid
}

// idsFromStrings returns a deterministic ID and NodeID from a string and a list of strings.
// This is useful for ensuring the IDs represent the same entity across different
// types and test runs resolve to the same ID. It calls [idsFromString] with the result
// of [nameForIDsFromStrings].
func idsFromStrings(base string, other ...string) (int64, string) {
	return idsFromString(nameForIDsFromStrings(base, other...))
}

// nameForIDsFromStrings returns a deterministic string from a string and a list of strings.
// The result is a string that is the concatenation of the base string and the other strings.
func nameForIDsFromStrings(base string, other ...string) string {
	var sb strings.Builder
	_, _ = sb.WriteString(base)
	for _, str := range other {
		_, _ = sb.WriteString(str)
	}
	return sb.String()
}

const (
	RepoName       string = "repo"
	RepoOwner      string = "owner"
	GitHubAppLogin string = "copilot-swe-agent"
	GitHubBotLogin string = "Copilot"
)

const (
	IssueNumber        = 1
	IssueTitle  string = "issue title"
	IssueBody   string = "issue body"

	IssueCommentBody string = "issue comment body with a mention to @copilot in it"
)

const (
	PullRequestNumber        = 2
	PullRequestTitle  string = "pr title"
	PullRequestBody   string = "pr body"

	PullRequestReviewBody        string = "pr review body"
	PullRequestReviewCommentBody string = "pr review comment body"
)

const (
	ActorLoginBot    string = "actor-bot"
	ActorLoginAdmin  string = "actor-admin"
	ActorLoginWriter string = "actor-write"
	ActorLoginReader string = "actor-read"
	ActorLoginNone   string = "actor-none"
)

const (
	NameForIDsIssue                    string = "issue"
	NameForIDsPullRequest              string = "pr"
	NameForIDsIssueComment             string = "issue_comment"
	NameForIDsPullRequestReview        string = "pr_review"
	NameForIDsPullRequestReviewComment string = "pr_review_comment"
)

func actor(login, actorType string) *github.GQLActor {
	id, nodeID := idsFromString(login)
	actor := github.NewGQLActor(id, nodeID, login, actorType, login)
	return &actor
}
func actorBot() *github.GQLActor {
	return actor(ActorLoginBot, github.GQLActorTypeBot)
}
func actorAdmin() *github.GQLActor {
	return actor(ActorLoginAdmin, github.GQLActorTypeUser)
}
func actorWriter() *github.GQLActor {
	return actor(ActorLoginWriter, github.GQLActorTypeUser)
}
func actorReader() *github.GQLActor {
	return actor(ActorLoginReader, github.GQLActorTypeUser)
}
func actorNone() *github.GQLActor {
	return actor(ActorLoginNone, github.GQLActorTypeUser)
}
func actorCopilot() *github.GQLActor {
	return actor(GitHubBotLogin, github.GQLActorTypeBot)
}

func user(login string) *github.GQLUser {
	id, nodeID := idsFromString(login)
	user := github.GQLUser{
		ID:     id,
		NodeID: nodeID,
		Login:  login,
		Name:   login,
	}
	return &user
}
func userAdmin() *github.GQLUser {
	return user(ActorLoginAdmin)
}
func userWriter() *github.GQLUser {
	return user(ActorLoginWriter)
}
func userReader() *github.GQLUser {
	return user(ActorLoginReader)
}
func userNone() *github.GQLUser {
	return user(ActorLoginNone)
}
func userBot() *github.GQLUser {
	return user(GitHubBotLogin)
}
func userCopilot() *github.GQLUser {
	return user(GitHubBotLogin)
}

func TestUTF8CharacterHandling(t *testing.T) {
	// Create test strings with multi-byte UTF-8 characters
	// Each emoji is 4 bytes in UTF-8, but counts as 1 character
	multiByteString := strings.Repeat("🔥", 10000) // This emoji is 4 bytes in UTF-8

	// Verify our test string characteristics
	require.Equal(t, 40000, len(multiByteString), "Test string should be 40000 bytes")
	require.Equal(t, 10000, utf8.RuneCountInString(multiByteString), "Test string should be 10000 UTF-8 characters")

	t.Run("Truncate function fixed behavior with UTF-8", func(t *testing.T) {
		// Fixed Truncate function uses UTF-8 character counting
		result := Truncate(multiByteString, 8000) // Truncate to 8000 characters

		// Should be truncated to exactly 8000 UTF-8 characters
		charCount := utf8.RuneCountInString(result)
		require.Equal(t, 8000, charCount, "Result should be exactly 8000 UTF-8 characters")
		require.Less(t, charCount, utf8.RuneCountInString(multiByteString), "String should be truncated")
		require.Contains(t, result, "...", "Should contain ellipsis")
	})
}

func testIssueComment(a github.GQLActor, minimized bool, index int, body string) *github.GQLIssueComment {
	issueBody := IssueCommentBody
	if body != "" {
		issueBody = body
	}
	id, nodeID := idsFromStrings(NameForIDsIssueComment, strconv.Itoa(index))
	indexTime := baseTime.Add(time.Duration(index) * time.Hour)
	return &github.GQLIssueComment{
		GQLComment: github.GQLComment{
			GqlCommentCore: github.GqlCommentCore{
				ID:          github.FullDatabaseID(id),
				NodeID:      nodeID,
				Author:      a,
				Body:        issueBody,
				CreatedAt:   indexTime,
				UpdatedAt:   indexTime,
				PublishedAt: indexTime,
			},
		},
		GQLMinimizable: github.GQLMinimizable{
			IsMinimized: minimized,
		},
	}
}

func testPullRequestReview(a github.GQLActor, minimized bool, index int, body string, comments []github.GQLPullRequestReviewComment) *github.GQLPullRequestReview {
	reviewBody := PullRequestReviewBody
	if body != "" {
		reviewBody = body
	}
	id, nodeID := idsFromStrings(NameForIDsPullRequestReview, strconv.Itoa(index))
	indexTime := baseTime.Add(time.Duration(index) * time.Hour)
	return &github.GQLPullRequestReview{
		GQLComment: github.GQLComment{
			GqlCommentCore: github.GqlCommentCore{
				ID:          github.FullDatabaseID(id),
				NodeID:      nodeID,
				Author:      a,
				Body:        reviewBody,
				CreatedAt:   indexTime,
				UpdatedAt:   indexTime,
				PublishedAt: indexTime,
			},
		},
		SubmittedAt: indexTime,
		Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
			TotalCount: len(comments),
			Nodes:      comments,
		},
		GQLMinimizable: github.GQLMinimizable{
			IsMinimized: minimized,
		},
	}
}

func testPullRequestReviewComment(a github.GQLActor, minimized bool, index, reviewIndex int, body, path string, subjectType github.GQLPullRequestReviewThreadSubjectType) *github.GQLPullRequestReviewComment {
	reviewBody := PullRequestReviewCommentBody
	if body != "" {
		reviewBody = body
	}
	reviewPath := "path"
	if path != "" {
		reviewPath = path
	}
	id, nodeID := idsFromStrings(NameForIDsPullRequestReviewComment, strconv.Itoa(index))
	rid, rNodeID := idsFromStrings(NameForIDsPullRequestReview, strconv.Itoa(reviewIndex))
	indexTime := baseTime.Add(time.Duration(reviewIndex) * time.Hour)
	return &github.GQLPullRequestReviewComment{
		GQLComment: github.GQLComment{
			GqlCommentCore: github.GqlCommentCore{
				ID:          github.FullDatabaseID(id),
				NodeID:      nodeID,
				Author:      a,
				Body:        reviewBody,
				CreatedAt:   indexTime,
				UpdatedAt:   indexTime,
				PublishedAt: indexTime,
			},
		},
		GQLMinimizable: github.GQLMinimizable{
			IsMinimized: minimized,
		},
		GqlReviewCommentFields: github.GqlReviewCommentFields{
			Path:        reviewPath,
			SubjectType: subjectType,
			PullRequestReview: github.GQLPullRequestReviewIDs{
				ID:     github.FullDatabaseID(rid),
				NodeID: rNodeID,
			},
		},
	}
}

func prReviewCommentLine(a github.GQLActor, minimized bool, index, reviewIndex int, body, path string, start, end int) *github.GQLPullRequestReviewComment {
	startLine := start
	endLine := end
	if start == 0 && end == 0 {
		startLine = mathrand.Intn(100)
		endLine = startLine + 8
	}
	comment := testPullRequestReviewComment(a, minimized, index, reviewIndex, body, path, github.GQLPullRequestReviewThreadSubjectTypeLine)
	comment.Line = endLine
	comment.StartLine = startLine
	comment.OriginalLine = 0
	return comment
}

func prReviewCommentFile(a github.GQLActor, minimized bool, index, reviewIndex int, body, path string) *github.GQLPullRequestReviewComment {
	comment := testPullRequestReviewComment(a, minimized, index, reviewIndex, body, path, github.GQLPullRequestReviewThreadSubjectTypeFile)
	comment.Line = 0
	comment.OriginalLine = 0
	return comment
}

func participants() []github.ContextParticipant {
	return []github.ContextParticipant{
		{
			Actor:       *actorCopilot(),
			Permissions: nil,
		},
		{
			Actor: *actorAdmin(),
			Permissions: &github.RepositoryPermissions{
				Permission: "admin",
				Role:       "admin",
				Pull:       true,
				Triage:     true,
				Push:       true,
				Maintain:   true,
				Admin:      true,
			},
		},
		{
			Actor: *actorWriter(),
			Permissions: &github.RepositoryPermissions{
				Permission: "write",
				Role:       "write",
				Pull:       true,
				Triage:     true,
				Push:       true,
			},
		},
		{
			Actor: *actorReader(),
			Permissions: &github.RepositoryPermissions{
				Permission: "read",
				Role:       "read",
				Pull:       true,
			},
		},
		{
			Actor: *actorNone(),
			Permissions: &github.RepositoryPermissions{
				Permission: "none",
				Role:       "none",
			},
		},
		{
			Actor:       *actorBot(),
			Permissions: nil,
		},
	}
}

func getIssueContext() *github.IssueContext {
	id, nodeID := idsFromString(RepoName)
	oID, oNodeID := idsFromString(RepoOwner)

	return &github.IssueContext{
		Repository: github.GQLRepository{
			ID:               id,
			NodeID:           nodeID,
			Name:             RepoName,
			HasIssuesEnabled: true,
			IsPrivate:        true,
			Owner:            github.NewGQLRepositoryOwner(oID, oNodeID, RepoOwner, github.GQLRepositoryOwnerTypeOrganization, RepoOwner),
			DefaultBranchRef: &github.GQLRef{Name: "main"},
		},
		Issue: github.GQLIssue{
			GQLComment: github.GQLComment{
				GqlCommentCore: github.GqlCommentCore{
					ID:          github.FullDatabaseID(id),
					NodeID:      nodeID,
					Body:        IssueBody,
					CreatedAt:   baseTime,
					UpdatedAt:   baseTime,
					PublishedAt: baseTime,
				},
			},
			Title:  IssueTitle,
			Number: IssueNumber,
			State:  github.GQLIssueStateOpen,
			GQLAssignable: github.GQLAssignable{
				Assignees: github.GQLConnection[github.GQLUser]{
					TotalCount: 1,
					Nodes:      []github.GQLUser{*userCopilot()},
				},
			},
			Comments: github.GQLConnection[github.GQLIssueComment]{
				Nodes: []github.GQLIssueComment{},
			},
			Participants: github.GQLConnection[github.GQLUser]{
				TotalCount: 6,
				Nodes:      []github.GQLUser{*userCopilot(), *userAdmin(), *userWriter(), *userReader(), *userNone(), *userBot()},
			},
		},
		Participants: participants(),
	}
}

func getPullRequestContext() *github.PullRequestContext {
	id, nodeID := idsFromString(RepoName)
	oID, oNodeID := idsFromString(RepoOwner)

	return &github.PullRequestContext{
		Repository: github.GQLRepository{
			ID:               id,
			NodeID:           nodeID,
			Name:             RepoName,
			HasIssuesEnabled: true,
			IsPrivate:        true,
			Owner:            github.NewGQLRepositoryOwner(oID, oNodeID, RepoOwner, github.GQLRepositoryOwnerTypeOrganization, RepoOwner),
			DefaultBranchRef: &github.GQLRef{Name: "main"},
		},
		PullRequest: github.GQLPullRequest{
			GQLComment: github.GQLComment{
				GqlCommentCore: github.GqlCommentCore{
					ID:          github.FullDatabaseID(id),
					NodeID:      nodeID,
					Author:      *actorCopilot(),
					Body:        PullRequestBody,
					CreatedAt:   baseTime.Add(time.Minute),
					UpdatedAt:   baseTime.Add(time.Minute),
					PublishedAt: baseTime.Add(time.Minute),
				},
			},
			Title:  PullRequestTitle,
			Number: PullRequestNumber,
			GQLAssignable: github.GQLAssignable{
				Assignees: github.GQLConnection[github.GQLUser]{
					TotalCount: 1,
					Nodes:      []github.GQLUser{*userCopilot()},
				},
			},
			Commits: struct {
				TotalCount int `json:"total_count"`
			}{
				TotalCount: 5,
			},
			Comments: github.GQLConnection[github.GQLIssueComment]{
				Nodes: []github.GQLIssueComment{},
			},
			Reviews: github.GQLConnection[github.GQLPullRequestReview]{
				Nodes: []github.GQLPullRequestReview{},
			},
			Participants: github.GQLConnection[github.GQLUser]{
				TotalCount: 6,
				Nodes:      []github.GQLUser{*userCopilot(), *userAdmin(), *userWriter(), *userReader(), *userNone(), *userBot()},
			},
		},
		Participants: participants(),
	}
}

func getAssignment() *jobs.Assignment {
	rID, rNID := idsFromString(RepoName)
	oID, oNID := idsFromString(RepoOwner)
	return &jobs.Assignment{
		ID:                "assignment-id",
		RepoID:            rID,
		OwnerID:           oID,
		RepoNodeID:        rNID,
		OwnerNodeID:       oNID,
		PullRequestID:     rID,
		PullRequestNumber: PullRequestNumber,
		CreatedAt:         baseTime.Add(time.Minute).Unix(),
	}
}

func getJob() *jobs.Job {
	rID, rNID := idsFromString(RepoName)
	oID, oNID := idsFromString(RepoOwner)
	actor := *actorWriter()
	return &jobs.Job{
		RepoID:            rID,
		OwnerID:           oID,
		RepoNodeID:        rNID,
		OwnerNodeID:       oNID,
		PullRequestID:     rID,
		PullRequestNumber: PullRequestNumber,
		CreatedAt:         baseTime.Add(time.Minute).Unix(),
		Status:            jobs.JobStatusPending,
		ActorLogin:        actor.GetLogin(),
		ActorID:           actor.GetID(),
	}
}

func getCommentIDs(indexes ...int) []int64 {
	var commentIDs []int64
	for _, index := range indexes {
		id, _ := idsFromStrings(NameForIDsIssueComment, strconv.Itoa(index))
		commentIDs = append(commentIDs, id)
	}
	return commentIDs
}

func getReviewIDs(indexes ...int) []int64 {
	var reviewIDs []int64
	for _, index := range indexes {
		id, _ := idsFromStrings(NameForIDsPullRequestReview, strconv.Itoa(index))
		reviewIDs = append(reviewIDs, id)
	}
	return reviewIDs
}

func getReviewCommentIDs(indexes ...int) []int64 {
	var reviewIDs []int64
	for _, index := range indexes {
		id, _ := idsFromStrings(NameForIDsPullRequestReviewComment, strconv.Itoa(index))
		reviewIDs = append(reviewIDs, id)
	}
	return reviewIDs
}

func TestExtractPRBodySections(t *testing.T) {
	t.Run("new format: core -> original prompt -> user suffix", func(t *testing.T) {
		body := "## Summary\n\nFixed the bug" +
			jobservice.PullRequestBodyOriginalPromptSeparator +
			"<details>Original: Fix bug #123</details>" +
			jobservice.PullRequestBodySuffixSeparator +
			"Fixes #123"

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "## Summary\n\nFixed the bug", coreBody)
		require.Equal(t, jobservice.PullRequestBodyOriginalPromptSeparator+"<details>Original: Fix bug #123</details>", originalPrompt)
		require.Equal(t, jobservice.PullRequestBodySuffixSeparator+"Fixes #123", userSuffix)
	})

	t.Run("new format with custom agent: core -> original prompt (with agent) -> user suffix", func(t *testing.T) {
		body := "## Summary\n\nFixed the bug" +
			jobservice.PullRequestBodyOriginalPromptSeparator +
			"<details>Original prompt</details>\n\n**Custom Agent:** Test Agent" +
			jobservice.PullRequestBodySuffixSeparator +
			"Fixes #123\nCloses #456"

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "## Summary\n\nFixed the bug", coreBody)
		require.Equal(t, jobservice.PullRequestBodyOriginalPromptSeparator+"<details>Original prompt</details>\n\n**Custom Agent:** Test Agent", originalPrompt)
		require.Equal(t, jobservice.PullRequestBodySuffixSeparator+"Fixes #123\nCloses #456", userSuffix)
	})

	t.Run("only original prompt separator found", func(t *testing.T) {
		body := "## Summary\n\nFixed the bug" +
			jobservice.PullRequestBodyOriginalPromptSeparator +
			"<details>Original: Fix the authentication bug</details>"

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "## Summary\n\nFixed the bug", coreBody)
		require.Equal(t, jobservice.PullRequestBodyOriginalPromptSeparator+"<details>Original: Fix the authentication bug</details>", originalPrompt)
		require.Equal(t, "", userSuffix)
	})

	t.Run("only user suffix separator found (old format)", func(t *testing.T) {
		body := "## Summary\n\nFixed the bug" +
			jobservice.PullRequestBodySuffixSeparator +
			"<details>Original prompt was here</details>\nFixes #123"

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "## Summary\n\nFixed the bug", coreBody)
		require.Equal(t, "", originalPrompt)
		require.Equal(t, jobservice.PullRequestBodySuffixSeparator+"<details>Original prompt was here</details>\nFixes #123", userSuffix)
	})

	t.Run("no separators found", func(t *testing.T) {
		body := "## Summary\n\nThis is just a PR body with no separators"

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "## Summary\n\nThis is just a PR body with no separators", coreBody)
		require.Equal(t, "", originalPrompt)
		require.Equal(t, "", userSuffix)
	})

	t.Run("empty body", func(t *testing.T) {
		body := ""

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "", coreBody)
		require.Equal(t, "", originalPrompt)
		require.Equal(t, "", userSuffix)
	})

	t.Run("only separators, no content", func(t *testing.T) {
		body := jobservice.PullRequestBodyOriginalPromptSeparator +
			jobservice.PullRequestBodySuffixSeparator

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "", coreBody)
		require.Equal(t, jobservice.PullRequestBodyOriginalPromptSeparator, originalPrompt)
		require.Equal(t, jobservice.PullRequestBodySuffixSeparator, userSuffix)
	})

	t.Run("multiline content in all sections", func(t *testing.T) {
		body := "# PR Title\n\n" +
			"## Summary\n" +
			"Multiple lines\n" +
			"of content" +
			jobservice.PullRequestBodyOriginalPromptSeparator +
			"<details>\n" +
			"<summary>Original Prompt</summary>\n" +
			"Fix the bug\n" +
			"</details>" +
			jobservice.PullRequestBodySuffixSeparator +
			"Fixes #123\n" +
			"Related to #456"

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "# PR Title\n\n## Summary\nMultiple lines\nof content", coreBody)
		require.Contains(t, originalPrompt, "<details>")
		require.Contains(t, originalPrompt, "Fix the bug")
		require.Contains(t, userSuffix, "Fixes #123")
		require.Contains(t, userSuffix, "Related to #456")
	})

	t.Run("preserves exact spacing and newlines", func(t *testing.T) {
		body := "Core\n\n" +
			jobservice.PullRequestBodyOriginalPromptSeparator +
			"\n\nOriginal\n\n" +
			jobservice.PullRequestBodySuffixSeparator +
			"\n\nSuffix"

		coreBody, originalPrompt, userSuffix := extractPRBodySections(body)

		require.Equal(t, "Core\n\n", coreBody)
		require.Equal(t, jobservice.PullRequestBodyOriginalPromptSeparator+"\n\nOriginal\n\n", originalPrompt)
		require.Equal(t, jobservice.PullRequestBodySuffixSeparator+"\n\nSuffix", userSuffix)
	})
}
