package github

import (
	"encoding/base64"
	"errors"
	"hash/maphash"
	"math"
	"strconv"
	"strings"
	"testing"

	mark "github.com/github/go-mark"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/stretchr/testify/require"
)

var seed = maphash.MakeSeed()

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
	sb.WriteString(base)
	for _, str := range other {
		sb.WriteString(str)
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

func actor(login, actorType string) *GQLActor {
	id, nodeID := idsFromString(login)
	actor := NewGQLActor(id, nodeID, login, actorType, login)
	return &actor
}
func actorBot() *GQLActor {
	return actor(ActorLoginBot, GQLActorTypeBot)
}
func actorAdmin() *GQLActor {
	return actor(ActorLoginAdmin, GQLActorTypeUser)
}
func actorWriter() *GQLActor {
	return actor(ActorLoginWriter, GQLActorTypeUser)
}
func actorReader() *GQLActor {
	return actor(ActorLoginReader, GQLActorTypeUser)
}
func actorNone() *GQLActor {
	return actor(ActorLoginNone, GQLActorTypeUser)
}
func actorCopilot() *GQLActor {
	return actor(GitHubBotLogin, GQLActorTypeBot)
}

func user(login string) *GQLUser {
	id, nodeID := idsFromString(login)
	user := GQLUser{
		ID:     id,
		NodeID: nodeID,
		Login:  login,
		Name:   login,
	}
	return &user
}
func userAdmin() *GQLUser {
	return user(ActorLoginAdmin)
}
func userWriter() *GQLUser {
	return user(ActorLoginWriter)
}
func userReader() *GQLUser {
	return user(ActorLoginReader)
}
func userNone() *GQLUser {
	return user(ActorLoginNone)
}
func userBot() *GQLUser {
	return user(GitHubBotLogin)
}
func userCopilot() *GQLUser {
	return user(GitHubBotLogin)
}

func issueComment(a GQLActor, minimized bool, index int) *GQLIssueComment {
	id, nodeID := idsFromStrings(NameForIDsIssueComment, strconv.Itoa(index))
	return &GQLIssueComment{
		GQLComment: GQLComment{
			ID:     FullDatabaseID(id),
			NodeID: nodeID,
			Author: a,
		},
		GQLMinimizable: GQLMinimizable{
			IsMinimized: minimized,
		},
	}
}

func prReview(a GQLActor, minimized bool, index int, comments []GQLPullRequestReviewComment) *GQLPullRequestReview {
	id, nodeID := idsFromStrings(NameForIDsPullRequestReview, strconv.Itoa(index))
	return &GQLPullRequestReview{
		GQLComment: GQLComment{
			ID:     FullDatabaseID(id),
			NodeID: nodeID,
			Author: a,
		},
		Comments: GQLConnection[GQLPullRequestReviewComment]{
			TotalCount: len(comments),
			Nodes:      comments,
		},
		GQLMinimizable: GQLMinimizable{
			IsMinimized: minimized,
		},
	}
}

func prReviewComment(a GQLActor, minimized bool, index int) *GQLPullRequestReviewComment {
	id, nodeID := idsFromStrings(NameForIDsPullRequestReviewComment, strconv.Itoa(index))
	return &GQLPullRequestReviewComment{
		GQLComment: GQLComment{
			ID:     FullDatabaseID(id),
			NodeID: nodeID,
			Author: a,
			Body:   PullRequestReviewCommentBody,
		},
		Path:        "path",
		SubjectType: GQLPullRequestReviewThreadSubjectTypeLine,
		GQLMinimizable: GQLMinimizable{
			IsMinimized: minimized,
		},
	}
}

func participants() []ContextParticipant {
	return []ContextParticipant{
		{
			Actor:       *actorCopilot(),
			Permissions: nil,
		},
		{
			Actor: *actorAdmin(),
			Permissions: &RepositoryPermissions{
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
			Permissions: &RepositoryPermissions{
				Permission: "write",
				Role:       "write",
				Pull:       true,
				Triage:     true,
				Push:       true,
			},
		},
		{
			Actor: *actorReader(),
			Permissions: &RepositoryPermissions{
				Permission: "read",
				Role:       "read",
				Pull:       true,
			},
		},
		{
			Actor: *actorNone(),
			Permissions: &RepositoryPermissions{
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

func getIssueContext() *IssueContext {
	id, nodeID := idsFromString(RepoName)
	oID, oNodeID := idsFromString(RepoOwner)

	return &IssueContext{
		Repository: GQLRepository{
			ID:               id,
			NodeID:           nodeID,
			Name:             RepoName,
			HasIssuesEnabled: true,
			IsPrivate:        true,
			Owner:            NewGQLRepositoryOwner(oID, oNodeID, RepoOwner, GQLRepositoryOwnerTypeOrganization, RepoOwner),
			DefaultBranchRef: &GQLRef{Name: "main"},
		},
		Issue: GQLIssue{
			GQLComment: GQLComment{
				ID:     FullDatabaseID(id),
				NodeID: nodeID,
			},
			Title:  IssueTitle,
			Number: IssueNumber,
			State:  GQLIssueStateOpen,
			GQLAssignable: GQLAssignable{
				Assignees: GQLConnection[GQLUser]{
					TotalCount: 1,
					Nodes:      []GQLUser{*userCopilot()},
				},
				AssignedActors: GQLConnection[GQLActor]{
					TotalCount: 1,
					Nodes:      []GQLActor{userCopilot().ToActor()},
				},
			},
			Comments: GQLConnection[GQLIssueComment]{
				Nodes: []GQLIssueComment{},
			},
			Participants: GQLConnection[GQLUser]{
				TotalCount: 6,
				Nodes:      []GQLUser{*userCopilot(), *userAdmin(), *userWriter(), *userReader(), *userNone(), *userBot()},
			},
		},
		Participants: participants(),
	}
}

func getPullRequestContext() *PullRequestContext {
	id, nodeID := idsFromString(RepoName)
	oID, oNodeID := idsFromString(RepoOwner)

	return &PullRequestContext{
		Repository: GQLRepository{
			ID:               id,
			NodeID:           nodeID,
			Name:             RepoName,
			HasIssuesEnabled: true,
			IsPrivate:        true,
			Owner:            NewGQLRepositoryOwner(oID, oNodeID, RepoOwner, GQLRepositoryOwnerTypeOrganization, RepoOwner),
			DefaultBranchRef: &GQLRef{Name: "main"},
		},
		PullRequest: GQLPullRequest{
			GQLComment: GQLComment{
				ID:     FullDatabaseID(id),
				NodeID: nodeID,
				Author: *actorCopilot(),
				Body:   PullRequestBody,
			},
			Title:  PullRequestTitle,
			Number: PullRequestNumber,
			GQLAssignable: GQLAssignable{
				Assignees: GQLConnection[GQLUser]{
					TotalCount: 1,
					Nodes:      []GQLUser{*userCopilot()},
				},
				AssignedActors: GQLConnection[GQLActor]{
					TotalCount: 1,
					Nodes:      []GQLActor{userCopilot().ToActor()},
				},
			},
			Comments: GQLConnection[GQLIssueComment]{
				Nodes: []GQLIssueComment{},
			},
			Reviews: GQLConnection[GQLPullRequestReview]{
				Nodes: []GQLPullRequestReview{},
			},
			Participants: GQLConnection[GQLUser]{
				TotalCount: 6,
				Nodes:      []GQLUser{*userCopilot(), *userAdmin(), *userWriter(), *userReader(), *userNone(), *userBot()},
			},
		},
		Participants: participants(),
	}
}

func TestCommentFiltering(t *testing.T) {
	appProvider := agenticapptest.NewTestProvider(t)

	t.Run("filters minimized comments", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()
		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorWriter(), true, 131), // minimized
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorWriter(), true, 2131), // minimized
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorWriter(), true, 3333, []GQLPullRequestReviewComment{ // minimized
				*prReviewComment(*actorWriter(), false, 332),
				*prReviewComment(*actorWriter(), true, 333), // minimized
			}),
			*prReview(*actorWriter(), false, 4444, []GQLPullRequestReviewComment{
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorWriter(), true, 423), // minimized
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   false,
			IncludeOtherBots:                   false,
			IncludeUsersWithoutPushPermissions: false,
			IncludeCopilotReviews:              false,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		require.Len(t, i.Issue.Comments.Nodes, 1)
		require.False(t, i.Issue.Comments.Nodes[0].IsMinimized)

		require.Len(t, pr.PullRequest.Comments.Nodes, 1)
		require.False(t, pr.PullRequest.Comments.Nodes[0].IsMinimized)

		require.Len(t, pr.PullRequest.Reviews.Nodes, 1)
		require.False(t, pr.PullRequest.Reviews.Nodes[0].IsMinimized)

		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 1)
		require.False(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].IsMinimized)
	})

	t.Run("skips filtering minimized comments", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()

		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorWriter(), true, 131), // minimized
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorWriter(), true, 2131), // minimized
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorWriter(), true, 3333, []GQLPullRequestReviewComment{ // minimized
				*prReviewComment(*actorWriter(), false, 332),
				*prReviewComment(*actorWriter(), true, 333), // minimized
			}),
			*prReview(*actorWriter(), false, 4444, []GQLPullRequestReviewComment{
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorWriter(), true, 423), // minimized
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   true,
			IncludeOtherBots:                   false,
			IncludeUsersWithoutPushPermissions: false,
			IncludeCopilotReviews:              false,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)
	})

	t.Run("filters comments from other bots", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()

		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorBot(), false, 16), // bot
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorBot(), false, 216), // bot
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorBot(), true, 3333, []GQLPullRequestReviewComment{ // bot
				*prReviewComment(*actorWriter(), false, 313),
				*prReviewComment(*actorBot(), false, 316), // bot
			}),
			*prReview(*actorWriter(), false, 4444, []GQLPullRequestReviewComment{
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorBot(), false, 416), // bot
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   false,
			IncludeOtherBots:                   false,
			IncludeUsersWithoutPushPermissions: false,
			IncludeCopilotReviews:              false,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		require.Len(t, i.Issue.Comments.Nodes, 1)
		require.Len(t, pr.PullRequest.Comments.Nodes, 1)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 1)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 1)

		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].Author.GetLogin())
	})

	t.Run("skips filtering comments from other bots", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()

		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorBot(), false, 16), // bot
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorBot(), false, 216), // bot
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorBot(), false, 3333, []GQLPullRequestReviewComment{ // bot
				*prReviewComment(*actorWriter(), false, 313),
				*prReviewComment(*actorBot(), false, 316), // bot
			}),
			*prReview(*actorWriter(), false, 4444, []GQLPullRequestReviewComment{
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorBot(), false, 416), // bot
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   false,
			IncludeOtherBots:                   true,
			IncludeUsersWithoutPushPermissions: false,
			IncludeCopilotReviews:              false,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		require.Equal(t, ActorLoginBot, pr.PullRequest.Reviews.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginBot, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[1].Author.GetLogin())

		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[1].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginBot, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes[1].Author.GetLogin())
	})

	t.Run("filters comments from users without push", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()

		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorReader(), false, 16), // reader
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorReader(), false, 216), // reader
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorReader(), true, 3333, []GQLPullRequestReviewComment{ // reader
				*prReviewComment(*actorWriter(), false, 313),
				*prReviewComment(*actorReader(), false, 316), // reader
			}),
			*prReview(*actorWriter(), false, 4444, []GQLPullRequestReviewComment{
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorReader(), false, 416), // reader
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   false,
			IncludeOtherBots:                   false,
			IncludeUsersWithoutPushPermissions: false,
			IncludeCopilotReviews:              false,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		require.Len(t, i.Issue.Comments.Nodes, 1)
		require.Len(t, pr.PullRequest.Comments.Nodes, 1)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 1)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 1)

		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].Author.GetLogin())
	})

	t.Run("skips filtering comments from users without push", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()

		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorReader(), false, 16), // reader
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorReader(), false, 216), // reader
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorReader(), false, 3333, []GQLPullRequestReviewComment{ // reader
				*prReviewComment(*actorWriter(), false, 313),
				*prReviewComment(*actorReader(), false, 316), // reader
			}),
			*prReview(*actorWriter(), false, 4444, []GQLPullRequestReviewComment{
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorReader(), false, 416), // reader
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   false,
			IncludeOtherBots:                   false,
			IncludeUsersWithoutPushPermissions: true,
			IncludeCopilotReviews:              false,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		require.Equal(t, ActorLoginReader, pr.PullRequest.Reviews.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginReader, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[1].Author.GetLogin())

		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[1].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginReader, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes[1].Author.GetLogin())
	})

	t.Run("filters reviews from copilot", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()

		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorCopilot(), false, 16), // copilot
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorCopilot(), false, 216), // copilot
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorCopilot(), true, 3333, []GQLPullRequestReviewComment{ // bot
				*prReviewComment(*actorWriter(), false, 313),
				*prReviewComment(*actorCopilot(), false, 316), // copilot
			}),
			*prReview(*actorWriter(), false, 4444, []GQLPullRequestReviewComment{
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorCopilot(), false, 416), // copilot
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   false,
			IncludeOtherBots:                   false,
			IncludeUsersWithoutPushPermissions: false,
			IncludeCopilotReviews:              false,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 1)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 1)

		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].Author.GetLogin())
	})

	t.Run("skips filtering reviews from copilot", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()

		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorCopilot(), false, 16), // bot
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorCopilot(), false, 216), // bot
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorCopilot(), false, 3333, []GQLPullRequestReviewComment{ // bot
				*prReviewComment(*actorWriter(), false, 313),
				*prReviewComment(*actorCopilot(), false, 316), // bot
			}),
			*prReview(*actorWriter(), false, 4444, []GQLPullRequestReviewComment{
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorCopilot(), false, 416), // bot
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   false,
			IncludeOtherBots:                   true,
			IncludeUsersWithoutPushPermissions: false,
			IncludeCopilotReviews:              true,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		require.Len(t, i.Issue.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2)
		require.Len(t, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes, 2)

		require.Equal(t, GitHubBotLogin, pr.PullRequest.Reviews.Nodes[0].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, GitHubBotLogin, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[1].Author.GetLogin())

		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[1].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, GitHubBotLogin, pr.PullRequest.Reviews.Nodes[1].Comments.Nodes[1].Author.GetLogin())
	})

	t.Run("includes comments from allowlisted bots even when filtering other bots", func(t *testing.T) {
		i := getIssueContext()
		pr := getPullRequestContext()

		// Create actors for CCR (allowlisted bot) and regular bot
		actorCCR := actor(agenticapp.CopilotCodeReviewAppSlug, GQLActorTypeBot)
		actorCCRWithBotSuffix := actor(agenticapp.CopilotCodeReviewAppSlug+"[bot]", GQLActorTypeBot)

		// Add CCR actors to participants so they have context for filtering
		i.Participants = append(i.Participants,
			ContextParticipant{
				Actor:       *actorCCR,
				Permissions: nil, // Bots typically don't have explicit permissions
			},
			ContextParticipant{
				Actor:       *actorCCRWithBotSuffix,
				Permissions: nil,
			},
		)
		pr.Participants = append(pr.Participants,
			ContextParticipant{
				Actor:       *actorCCR,
				Permissions: nil,
			},
			ContextParticipant{
				Actor:       *actorCCRWithBotSuffix,
				Permissions: nil,
			},
		)

		i.Issue.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 13),
			*issueComment(*actorBot(), false, 16),            // regular bot - should be filtered
			*issueComment(*actorCCR, false, 17),              // CCR - should be included
			*issueComment(*actorCCRWithBotSuffix, false, 18), // CCR with [bot] - should be included
		}

		pr.PullRequest.Comments.Nodes = []GQLIssueComment{
			*issueComment(*actorWriter(), false, 213),
			*issueComment(*actorBot(), false, 216),            // regular bot - should be filtered
			*issueComment(*actorCCR, false, 217),              // CCR - should be included
			*issueComment(*actorCCRWithBotSuffix, false, 218), // CCR with [bot] - should be included
		}

		pr.PullRequest.Reviews.Nodes = []GQLPullRequestReview{
			*prReview(*actorBot(), false, 3333, []GQLPullRequestReviewComment{ // regular bot - should be filtered
				*prReviewComment(*actorWriter(), false, 313),
			}),
			*prReview(*actorCCR, false, 4444, []GQLPullRequestReviewComment{ // CCR - should be included
				*prReviewComment(*actorWriter(), false, 422),
				*prReviewComment(*actorCCR, false, 423), // CCR comment - should be included
			}),
			*prReview(*actorCCRWithBotSuffix, false, 5555, []GQLPullRequestReviewComment{ // CCR with [bot] - should be included
				*prReviewComment(*actorWriter(), false, 522),
			}),
			*prReview(*actorWriter(), false, 6666, []GQLPullRequestReviewComment{
				*prReviewComment(*actorBot(), false, 616), // regular bot comment - should be filtered
				*prReviewComment(*actorCCR, false, 617),   // CCR comment - should be included
			}),
		}

		require.Len(t, i.Issue.Comments.Nodes, 4)
		require.Len(t, pr.PullRequest.Comments.Nodes, 4)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 4)

		filterOpts := FilterCommentOpts{
			IncludeMinimized:                   false,
			IncludeOtherBots:                   false, // Filter regular bots, but not allowlisted bots
			IncludeUsersWithoutPushPermissions: false,
			IncludeCopilotReviews:              false,
		}

		// apply filters
		i.Issue.Comments.Nodes = i.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Comments.Nodes = pr.FilteredComments(filterOpts, appProvider.IsAgenticActor)
		pr.PullRequest.Reviews.Nodes = pr.FilteredReviews(filterOpts, appProvider.IsAgenticActor)

		// Issue comments: should include writer + 2 CCR comments = 3 total
		require.Len(t, i.Issue.Comments.Nodes, 3, "Should include writer and both CCR comments")
		require.Equal(t, ActorLoginWriter, i.Issue.Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewAppSlug, i.Issue.Comments.Nodes[1].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewAppSlug+"[bot]", i.Issue.Comments.Nodes[2].Author.GetLogin())

		// PR comments: should include writer + 2 CCR comments = 3 total
		require.Len(t, pr.PullRequest.Comments.Nodes, 3, "Should include writer and both CCR comments")
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewAppSlug, pr.PullRequest.Comments.Nodes[1].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewAppSlug+"[bot]", pr.PullRequest.Comments.Nodes[2].Author.GetLogin())

		// PR reviews: should include 2 CCR reviews + 1 writer review = 3 total (regular bot filtered out)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 3, "Should include CCR reviews and writer review, but not regular bot")
		require.Equal(t, agenticapp.CopilotCodeReviewAppSlug, pr.PullRequest.Reviews.Nodes[0].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewAppSlug+"[bot]", pr.PullRequest.Reviews.Nodes[1].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[2].Author.GetLogin())

		// Check that CCR review comments are included
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2, "CCR review should have 2 comments")
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewAppSlug, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[1].Author.GetLogin())

		// Check that writer review comment from CCR is included, but bot comment is filtered
		require.Len(t, pr.PullRequest.Reviews.Nodes[2].Comments.Nodes, 1, "Writer review should have 1 comment (CCR included, bot filtered)")
		require.Equal(t, agenticapp.CopilotCodeReviewAppSlug, pr.PullRequest.Reviews.Nodes[2].Comments.Nodes[0].Author.GetLogin())
	})
}

func TestGraphQL429ErrorWrapping(t *testing.T) {
	t.Run("wraps 429 error with mark.ErrTooManyRequests", func(t *testing.T) {
		originalErr := errors.New("non-200 OK status code: 429 Too Many Requests")
		wrappedErr := mark.With(mark.ErrTooManyRequests, originalErr)

		// Verify that the wrapped error contains the original error
		require.Contains(t, wrappedErr.Error(), "429 Too Many Requests")

		// Verify that the error can be identified as a TooManyRequests error
		require.True(t, errors.Is(wrappedErr, mark.ErrTooManyRequests))
	})

	t.Run("does not wrap non-429 errors", func(t *testing.T) {
		originalErr := errors.New("non-200 OK status code: 404 Not Found")

		// A non-429 error should not be identified as TooManyRequests
		require.False(t, errors.Is(originalErr, mark.ErrTooManyRequests))
	})
}
