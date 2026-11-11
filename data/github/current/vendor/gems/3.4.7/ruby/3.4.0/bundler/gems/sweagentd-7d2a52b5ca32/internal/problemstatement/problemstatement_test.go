package problemstatement

import (
	"context"
	"encoding/base64"
	"hash/maphash"
	"math"
	mathrand "math/rand"
	"strconv"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/launcher"
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
	name := base
	for _, str := range other {
		name += str
	}
	return name
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

func actor(login string, actorType string) *github.GQLActor {
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

func TestWithAgentInstructions(t *testing.T) {
	t.Run("empty agent instructions do not alter problem statement", func(t *testing.T) {
		ctx := context.Background()
		metadata := customagent.Metadata{}
		attrs := customagent.ConfigAttributes{}
		job := &jobs.Job{
			ProblemStatement: jobs.ProblemStatement{
				Content: "This is a test problem statement.",
			},
			Args: launcher.LaunchAgentOpts{
				CustomAgent: customagent.NewWithConfig(metadata, customagent.NewConfigWithAttributes(attrs)),
			},
		}
		customAgentInstructions := job.Args.CustomAgent.Instructions()

		finalStatement := WithAgentInstructions(ctx, job.ProblemStatement.Content, customAgentInstructions)
		require.Equal(t, "This is a test problem statement.", finalStatement)
		require.NotContains(t, finalStatement, "<agent_instructions>")
	})

	t.Run("non-empty agent instructions prepend to problem statement", func(t *testing.T) {
		ctx := context.Background()
		metadata := customagent.Metadata{}
		attrs := customagent.ConfigAttributes{
			Prompt: "Do this.",
		}
		job := &jobs.Job{
			ProblemStatement: jobs.ProblemStatement{
				Content: "This is a test problem statement.",
			},
			Args: launcher.LaunchAgentOpts{
				CustomAgent: customagent.NewWithConfig(metadata, customagent.NewConfigWithAttributes(attrs)),
			},
		}
		customAgentInstructions := job.Args.CustomAgent.Instructions()

		finalStatement := WithAgentInstructions(ctx, job.ProblemStatement.Content, customAgentInstructions)
		require.Equal(t, "<agent_instructions>Do this.</agent_instructions>\n\nThis is a test problem statement.", finalStatement)
	})

	t.Run("truncates problem statement if it exceeds max length", func(t *testing.T) {
		longContent := strings.Repeat("a", MaxProblemStatementLength+100)
		ctx := context.Background()
		metadata := customagent.Metadata{}
		attrs := customagent.ConfigAttributes{}
		job := &jobs.Job{
			ProblemStatement: jobs.ProblemStatement{
				Content: longContent,
			},
			Args: launcher.LaunchAgentOpts{
				CustomAgent: customagent.NewWithConfig(metadata, customagent.NewConfigWithAttributes(attrs)),
			},
		}

		customAgentInstructions := job.Args.CustomAgent.Instructions()

		finalStatement := WithAgentInstructions(ctx, job.ProblemStatement.Content, customAgentInstructions)
		require.Len(t, finalStatement, MaxProblemStatementLength)
		require.True(t, strings.HasSuffix((finalStatement), "..."))
	})
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
		require.True(t, charCount < utf8.RuneCountInString(multiByteString), "String should be truncated")
		require.Contains(t, result, "...", "Should contain ellipsis")
	})

	t.Run("WithAgentInstructions fixed behavior with UTF-8", func(t *testing.T) {
		ctx := context.Background()

		// Create a long problem statement with UTF-8 characters
		longUTF8Content := strings.Repeat("🔥", MaxProblemStatementLength+1000)

		// Verify it exceeds the limit in characters
		require.Greater(t, utf8.RuneCountInString(longUTF8Content), MaxProblemStatementLength)

		attrs := customagent.ConfigAttributes{}
		job := &jobs.Job{
			ProblemStatement: jobs.ProblemStatement{
				Content: longUTF8Content,
			},
			Args: launcher.LaunchAgentOpts{
				CustomAgent: customagent.NewWithConfig(customagent.Metadata{}, customagent.NewConfigWithAttributes(attrs)),
			},
		}

		customAgentInstructions := job.Args.CustomAgent.Instructions()
		result := WithAgentInstructions(ctx, job.ProblemStatement.Content, customAgentInstructions)

		// Fixed implementation truncates based on UTF-8 characters
		charCount := utf8.RuneCountInString(result)
		require.Equal(t, MaxProblemStatementLength, charCount, "Result should be exactly MaxProblemStatementLength UTF-8 characters")
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
			ID:          github.FullDatabaseID(id),
			NodeID:      nodeID,
			Author:      a,
			Body:        issueBody,
			CreatedAt:   indexTime,
			UpdatedAt:   indexTime,
			PublishedAt: indexTime,
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
			ID:          github.FullDatabaseID(id),
			NodeID:      nodeID,
			Author:      a,
			Body:        reviewBody,
			CreatedAt:   indexTime,
			UpdatedAt:   indexTime,
			PublishedAt: indexTime,
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
			ID:          github.FullDatabaseID(id),
			NodeID:      nodeID,
			Author:      a,
			Body:        reviewBody,
			CreatedAt:   indexTime,
			UpdatedAt:   indexTime,
			PublishedAt: indexTime,
		},
		Path:        reviewPath,
		SubjectType: subjectType,
		GQLMinimizable: github.GQLMinimizable{
			IsMinimized: minimized,
		},
		PullRequestReview: github.GQLPullRequestReviewIDs{
			ID:     github.FullDatabaseID(rid),
			NodeID: rNodeID,
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
				ID:          github.FullDatabaseID(id),
				NodeID:      nodeID,
				Body:        IssueBody,
				CreatedAt:   baseTime,
				UpdatedAt:   baseTime,
				PublishedAt: baseTime,
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
				ID:          github.FullDatabaseID(id),
				NodeID:      nodeID,
				Author:      *actorCopilot(),
				Body:        PullRequestBody,
				CreatedAt:   baseTime.Add(time.Minute),
				UpdatedAt:   baseTime.Add(time.Minute),
				PublishedAt: baseTime.Add(time.Minute),
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
		RepoName:          RepoName,
		RepoOwner:         RepoOwner,
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
		RepoName:          RepoName,
		RepoOwner:         RepoOwner,
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

func TestRemoveFixesInSuffix(t *testing.T) {
	t.Run("no separator returns body unchanged", func(t *testing.T) {
		body := "This is a PR body without a separator"
		result := RemoveFixesInSuffix(body)
		require.Equal(t, body, result)
	})

	t.Run("removes lines starting with * Fixes in suffix", func(t *testing.T) {
		body := `PR description` + jobutils.PullRequestBodySuffixSeparator + `Some content
* Fixes #123
* Fixes #456
More content`
		expected := `PR description` + jobutils.PullRequestBodySuffixSeparator + `Some content
More content`
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("removes lines starting with - Fixes in suffix", func(t *testing.T) {
		body := `PR description` + jobutils.PullRequestBodySuffixSeparator + `Some content
- Fixes #123
- Fixes #456
More content`
		expected := `PR description` + jobutils.PullRequestBodySuffixSeparator + `Some content
More content`
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("removes both * Fixes and - Fixes in suffix", func(t *testing.T) {
		body := `PR description` + jobutils.PullRequestBodySuffixSeparator + `* Fixes #123
- Fixes #456
Keep this line`
		expected := `PR description` + jobutils.PullRequestBodySuffixSeparator + `Keep this line`
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("preserves Fixes in prefix before separator", func(t *testing.T) {
		body := `* Fixes #123 in prefix
- Fixes #456 also in prefix` + jobutils.PullRequestBodySuffixSeparator + `* Fixes #789
Suffix content`
		expected := `* Fixes #123 in prefix
- Fixes #456 also in prefix` + jobutils.PullRequestBodySuffixSeparator + `Suffix content`
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("handles whitespace before Fixes", func(t *testing.T) {
		body := `PR description` + jobutils.PullRequestBodySuffixSeparator + `  * Fixes #123
	- Fixes #456
Keep this`
		expected := `PR description` + jobutils.PullRequestBodySuffixSeparator + `Keep this`
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("preserves lines with Fixes not at start", func(t *testing.T) {
		body := `PR description` + jobutils.PullRequestBodySuffixSeparator + `This line mentions Fixes #123
* Fixes #456
Another Fixes reference`
		expected := `PR description` + jobutils.PullRequestBodySuffixSeparator + `This line mentions Fixes #123
Another Fixes reference`
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("empty suffix", func(t *testing.T) {
		body := "PR description" + jobutils.PullRequestBodySuffixSeparator
		expected := "PR description" + jobutils.PullRequestBodySuffixSeparator + ""
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("suffix with only Fixes lines", func(t *testing.T) {
		body := `PR description` + jobutils.PullRequestBodySuffixSeparator + `* Fixes #123
- Fixes #456`
		expected := `PR description` + jobutils.PullRequestBodySuffixSeparator + ``
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("preserves other bullet points", func(t *testing.T) {
		body := `PR description` + jobutils.PullRequestBodySuffixSeparator + `* Regular bullet
* Fixes #123
- Another bullet
- Fixes #456`
		expected := `PR description` + jobutils.PullRequestBodySuffixSeparator + `* Regular bullet
- Another bullet`
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})

	t.Run("case sensitive - does not remove fixes with lowercase f", func(t *testing.T) {
		body := `PR description` + jobutils.PullRequestBodySuffixSeparator + `* fixes #123
- fixes #456
* Fixes #789`
		expected := `PR description` + jobutils.PullRequestBodySuffixSeparator + `* fixes #123
- fixes #456`
		result := RemoveFixesInSuffix(body)
		require.Equal(t, expected, result)
	})
}
