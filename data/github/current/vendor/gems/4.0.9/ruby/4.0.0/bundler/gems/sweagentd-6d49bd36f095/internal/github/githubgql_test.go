package github

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"hash/maphash"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	mark "github.com/github/go-mark"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/require"
	"golang.org/x/oauth2"
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
			GqlCommentCore: GqlCommentCore{
				ID:     FullDatabaseID(id),
				NodeID: nodeID,
				Author: a,
			},
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
			GqlCommentCore: GqlCommentCore{
				ID:     FullDatabaseID(id),
				NodeID: nodeID,
				Author: a,
			},
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
			GqlCommentCore: GqlCommentCore{
				ID:     FullDatabaseID(id),
				NodeID: nodeID,
				Author: a,
				Body:   PullRequestReviewCommentBody,
			},
		},
		GqlReviewCommentFields: GqlReviewCommentFields{
			Path:        "path",
			SubjectType: GQLPullRequestReviewThreadSubjectTypeLine,
		},
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
				GqlCommentCore: GqlCommentCore{
					ID:     FullDatabaseID(id),
					NodeID: nodeID,
				},
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
				GqlCommentCore: GqlCommentCore{
					ID:     FullDatabaseID(id),
					NodeID: nodeID,
					Author: *actorCopilot(),
					Body:   PullRequestBody,
				},
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
		actorCCR := actor(agenticapp.CopilotCodeReviewComputeSlug, GQLActorTypeBot)
		actorCCRWithBotSuffix := actor(agenticapp.CopilotCodeReviewComputeSlug+"[bot]", GQLActorTypeBot)

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
		require.Equal(t, agenticapp.CopilotCodeReviewComputeSlug, i.Issue.Comments.Nodes[1].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewComputeSlug+"[bot]", i.Issue.Comments.Nodes[2].Author.GetLogin())

		// PR comments: should include writer + 2 CCR comments = 3 total
		require.Len(t, pr.PullRequest.Comments.Nodes, 3, "Should include writer and both CCR comments")
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewComputeSlug, pr.PullRequest.Comments.Nodes[1].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewComputeSlug+"[bot]", pr.PullRequest.Comments.Nodes[2].Author.GetLogin())

		// PR reviews: should include 2 CCR reviews + 1 writer review = 3 total (regular bot filtered out)
		require.Len(t, pr.PullRequest.Reviews.Nodes, 3, "Should include CCR reviews and writer review, but not regular bot")
		require.Equal(t, agenticapp.CopilotCodeReviewComputeSlug, pr.PullRequest.Reviews.Nodes[0].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewComputeSlug+"[bot]", pr.PullRequest.Reviews.Nodes[1].Author.GetLogin())
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[2].Author.GetLogin())

		// Check that CCR review comments are included
		require.Len(t, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes, 2, "CCR review should have 2 comments")
		require.Equal(t, ActorLoginWriter, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[0].Author.GetLogin())
		require.Equal(t, agenticapp.CopilotCodeReviewComputeSlug, pr.PullRequest.Reviews.Nodes[0].Comments.Nodes[1].Author.GetLogin())

		// Check that writer review comment from CCR is included, but bot comment is filtered
		require.Len(t, pr.PullRequest.Reviews.Nodes[2].Comments.Nodes, 1, "Writer review should have 1 comment (CCR included, bot filtered)")
		require.Equal(t, agenticapp.CopilotCodeReviewComputeSlug, pr.PullRequest.Reviews.Nodes[2].Comments.Nodes[0].Author.GetLogin())
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

func TestIsResourceLimitError(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want bool
	}{
		{name: "nil error", err: nil, want: false},
		{name: "exact match", err: errors.New("Resource limits for this query exceeded."), want: true},
		{name: "production format with location", err: errors.New("Resource limits for this query exceeded. at Line 1, Column 2352"), want: true},
		{name: "wrapped error", err: errors.New("failed to get pull request context: Resource limits for this query exceeded."), want: true},
		{name: "rate limit is not resource limit", err: errors.New("API rate limit exceeded"), want: false},
		{name: "unrelated error", err: errors.New("some other error"), want: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.want, IsResourceLimitError(tt.err))
		})
	}
}

func TestFallbackConversions(t *testing.T) {
	ts := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	id, nodeID := idsFromString("fallback-comment")

	t.Run("toGQLComment preserves all fields and leaves reactions empty", func(t *testing.T) {
		fc := fallbackPRComment{
			GqlCommentCore: GqlCommentCore{
				ID:                FullDatabaseID(id),
				NodeID:            nodeID,
				Author:            *actorWriter(),
				AuthorAssociation: GQLCommentAuthorAssociationMember,
				Body:              "test body",
				CreatedAt:         ts,
				PublishedAt:       ts.Add(time.Second),
				UpdatedAt:         ts.Add(time.Minute),
				ViewerDidAuthor:   true,
			},
		}

		got := fc.toGQLComment()

		require.Equal(t, FullDatabaseID(id), got.ID)
		require.Equal(t, nodeID, got.NodeID)
		require.Equal(t, ActorLoginWriter, got.Author.GetLogin())
		require.Equal(t, GQLCommentAuthorAssociationMember, got.AuthorAssociation)
		require.Equal(t, "test body", got.Body)
		require.Equal(t, ts, got.CreatedAt)
		require.Equal(t, ts.Add(time.Second), got.PublishedAt)
		require.Equal(t, ts.Add(time.Minute), got.UpdatedAt)
		require.True(t, got.ViewerDidAuthor)
		require.Empty(t, got.Reactions.Nodes, "fallback path should leave reactions empty")
		require.False(t, got.ViewerCanReact, "fallback path should leave ViewerCanReact as zero value")
	})

	t.Run("toGQLIssueComment preserves URL and minimizable", func(t *testing.T) {
		fc := fallbackPRIssueComment{
			fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
				ID:     FullDatabaseID(id),
				NodeID: nodeID,
				Author: *actorWriter(),
				Body:   "issue comment body",
			}},
			GQLMinimizable: GQLMinimizable{IsMinimized: true, MinimizedReason: "off-topic"},
			URL:            "https://github.com/owner/repo/issues/1#issuecomment-123",
		}

		got := fc.toGQLIssueComment()

		require.Equal(t, "issue comment body", got.Body)
		require.Equal(t, "https://github.com/owner/repo/issues/1#issuecomment-123", got.URL)
		require.True(t, got.IsMinimized)
		require.Equal(t, "off-topic", got.MinimizedReason)
		require.Empty(t, got.Reactions.Nodes)
	})

	t.Run("toGQLPullRequestReviewComment preserves all review comment fields", func(t *testing.T) {
		replyToID, replyToNodeID := idsFromString("reply-to")
		reviewID, reviewNodeID := idsFromString("review")

		fc := fallbackPRReviewComment{
			fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
				ID:     FullDatabaseID(id),
				NodeID: nodeID,
				Author: *actorAdmin(),
				Body:   "review comment",
			}},
			GQLMinimizable: GQLMinimizable{IsMinimized: false},
			GqlReviewCommentFields: GqlReviewCommentFields{
				Commit:            GQLGitObject{AbbreviatedOID: "abc1234", OID: "abc1234567890"},
				Path:              "src/main.go",
				Line:              42,
				StartLine:         40,
				OriginalLine:      38,
				OriginalStartLine: 36,
				OriginalCommit:    GQLGitObject{AbbreviatedOID: "def5678", OID: "def5678901234"},
				State:             GQLPullRequestReviewCommentStateSubmitted,
				SubjectType:       GQLPullRequestReviewThreadSubjectTypeLine,
				PullRequestReview: GQLPullRequestReviewIDs{
					ID:     FullDatabaseID(reviewID),
					NodeID: reviewNodeID,
				},
				ReplyTo: &GQLReplyTo{
					ID:     FullDatabaseID(replyToID),
					NodeID: replyToNodeID,
				},
				URL: "https://github.com/owner/repo/pull/1#discussion_r123",
			},
		}

		got := fc.toGQLPullRequestReviewComment()

		require.Equal(t, "review comment", got.Body)
		require.Equal(t, "src/main.go", got.Path)
		require.Equal(t, 42, got.Line)
		require.Equal(t, 40, got.StartLine)
		require.Equal(t, 38, got.OriginalLine)
		require.Equal(t, 36, got.OriginalStartLine)
		require.Equal(t, "abc1234", got.Commit.AbbreviatedOID)
		require.Equal(t, "def5678", got.OriginalCommit.AbbreviatedOID)
		require.Equal(t, GQLPullRequestReviewCommentStateSubmitted, got.State)
		require.Equal(t, GQLPullRequestReviewThreadSubjectTypeLine, got.SubjectType)
		require.Equal(t, reviewNodeID, got.PullRequestReview.NodeID)
		require.NotNil(t, got.ReplyTo)
		require.Equal(t, replyToNodeID, got.ReplyTo.NodeID)
		require.Equal(t, "https://github.com/owner/repo/pull/1#discussion_r123", got.URL)
		require.Empty(t, got.Reactions.Nodes)
	})

	t.Run("toGQLPullRequestReview converts all comments", func(t *testing.T) {
		c1ID, c1NodeID := idsFromString("review-comment-1")
		c2ID, c2NodeID := idsFromString("review-comment-2")

		fr := fallbackPRReview{
			fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
				ID:     FullDatabaseID(id),
				NodeID: nodeID,
				Author: *actorWriter(),
				Body:   "review body",
			}},
			GQLMinimizable:            GQLMinimizable{IsMinimized: false},
			AuthorCanPushToRepository: true,
			State:                     GQLPullRequestReviewStateApproved,
			SubmittedAt:               ts,
			URL:                       "https://github.com/owner/repo/pull/1#pullrequestreview-1",
			Comments: GQLConnection[fallbackPRReviewComment]{
				TotalCount: 2,
				Nodes: []fallbackPRReviewComment{
					{
						fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
							ID: FullDatabaseID(c1ID), NodeID: c1NodeID,
							Author: *actorWriter(), Body: "first comment",
						}},
						GqlReviewCommentFields: GqlReviewCommentFields{Path: "file1.go", Line: 10},
					},
					{
						fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
							ID: FullDatabaseID(c2ID), NodeID: c2NodeID,
							Author: *actorAdmin(), Body: "second comment",
						}},
						GqlReviewCommentFields: GqlReviewCommentFields{Path: "file2.go", Line: 20},
					},
				},
			},
		}

		got := fr.toGQLPullRequestReview()

		require.Equal(t, "review body", got.Body)
		require.True(t, got.AuthorCanPushToRepository)
		require.Equal(t, GQLPullRequestReviewStateApproved, got.State)
		require.Equal(t, ts, got.SubmittedAt)
		require.Equal(t, 2, got.Comments.TotalCount)
		require.Len(t, got.Comments.Nodes, 2)
		require.Equal(t, "first comment", got.Comments.Nodes[0].Body)
		require.Equal(t, "file1.go", got.Comments.Nodes[0].Path)
		require.Equal(t, "second comment", got.Comments.Nodes[1].Body)
		require.Equal(t, "file2.go", got.Comments.Nodes[1].Path)
		require.Empty(t, got.Reactions.Nodes, "review reactions should be empty")
		require.Empty(t, got.Comments.Nodes[0].Reactions.Nodes, "comment reactions should be empty")
		require.Empty(t, got.Comments.Nodes[1].Reactions.Nodes, "comment reactions should be empty")
	})

	t.Run("toGQLPullRequestReviewThread converts comments and preserves IsResolved", func(t *testing.T) {
		cID, cNodeID := idsFromString("thread-comment")

		ft := fallbackPRReviewThread{
			IsResolved: true,
			Comments: GQLConnection[fallbackPRReviewComment]{
				TotalCount: 1,
				Nodes: []fallbackPRReviewComment{
					{
						fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
							ID: FullDatabaseID(cID), NodeID: cNodeID,
							Author: *actorWriter(), Body: "thread comment",
						}},
						GqlReviewCommentFields: GqlReviewCommentFields{Path: "main.go", Line: 5},
					},
				},
			},
		}

		got := ft.toGQLPullRequestReviewThread()

		require.True(t, got.IsResolved)
		require.Equal(t, 1, got.Comments.TotalCount)
		require.Len(t, got.Comments.Nodes, 1)
		require.Equal(t, "thread comment", got.Comments.Nodes[0].Body)
		require.Empty(t, got.Comments.Nodes[0].Reactions.Nodes)
	})

	t.Run("toGQLPullRequest converts nested reviews and comments", func(t *testing.T) {
		prID, prNodeID := idsFromString("fallback-pr")
		icID, icNodeID := idsFromString("issue-comment")
		rID, rNodeID := idsFromString("review")
		rcID, rcNodeID := idsFromString("review-comment")

		fpr := fallbackPullRequest{
			fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
				ID: FullDatabaseID(prID), NodeID: prNodeID,
				Author: *actorWriter(), Body: "pr body",
				CreatedAt: ts, UpdatedAt: ts,
			}},
			Title:              "Test PR",
			Number:             42,
			IsDraft:            true,
			TotalCommentsCount: 5,
			IsCrossRepository:  false,
			Comments: GQLConnection[fallbackPRIssueComment]{
				TotalCount: 1,
				Nodes: []fallbackPRIssueComment{
					{
						fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
							ID: FullDatabaseID(icID), NodeID: icNodeID,
							Author: *actorReader(), Body: "an issue comment",
						}},
						URL: "https://github.com/owner/repo/pull/42#issuecomment-1",
					},
				},
			},
			Reviews: GQLConnection[fallbackPRReview]{
				TotalCount: 1,
				Nodes: []fallbackPRReview{
					{
						fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
							ID: FullDatabaseID(rID), NodeID: rNodeID,
							Author: *actorAdmin(), Body: "lgtm",
						}},
						State:       GQLPullRequestReviewStateApproved,
						SubmittedAt: ts,
						Comments: GQLConnection[fallbackPRReviewComment]{
							TotalCount: 1,
							Nodes: []fallbackPRReviewComment{
								{
									fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
										ID: FullDatabaseID(rcID), NodeID: rcNodeID,
										Author: *actorAdmin(), Body: "nit",
									}},
									GqlReviewCommentFields: GqlReviewCommentFields{Path: "file.go", Line: 10},
								},
							},
						},
					},
				},
			},
			ReviewThreads: GQLConnection[fallbackPRReviewThread]{
				TotalCount: 1,
				Nodes: []fallbackPRReviewThread{
					{
						IsResolved: false,
						Comments: GQLConnection[fallbackPRReviewComment]{
							TotalCount: 1,
							Nodes: []fallbackPRReviewComment{
								{
									fallbackPRComment: fallbackPRComment{GqlCommentCore: GqlCommentCore{
										ID: FullDatabaseID(rcID), NodeID: rcNodeID,
										Author: *actorAdmin(), Body: "nit",
									}},
									GqlReviewCommentFields: GqlReviewCommentFields{Path: "file.go", Line: 10},
								},
							},
						},
					},
				},
			},
		}

		got := fpr.toGQLPullRequest()

		// Top-level PR fields
		require.Equal(t, "Test PR", got.Title)
		require.Equal(t, 42, got.Number)
		require.True(t, got.IsDraft)
		require.Equal(t, 5, got.TotalCommentsCount)
		require.Equal(t, "pr body", got.Body)
		require.Empty(t, got.Reactions.Nodes, "PR reactions should be empty")

		// Issue comments
		require.Equal(t, 1, got.Comments.TotalCount)
		require.Len(t, got.Comments.Nodes, 1)
		require.Equal(t, "an issue comment", got.Comments.Nodes[0].Body)
		require.Empty(t, got.Comments.Nodes[0].Reactions.Nodes)

		// Reviews
		require.Equal(t, 1, got.Reviews.TotalCount)
		require.Len(t, got.Reviews.Nodes, 1)
		require.Equal(t, GQLPullRequestReviewStateApproved, got.Reviews.Nodes[0].State)
		require.Len(t, got.Reviews.Nodes[0].Comments.Nodes, 1)
		require.Equal(t, "nit", got.Reviews.Nodes[0].Comments.Nodes[0].Body)
		require.Empty(t, got.Reviews.Nodes[0].Reactions.Nodes)
		require.Empty(t, got.Reviews.Nodes[0].Comments.Nodes[0].Reactions.Nodes)

		// Review threads
		require.Equal(t, 1, got.ReviewThreads.TotalCount)
		require.Len(t, got.ReviewThreads.Nodes, 1)
		require.False(t, got.ReviewThreads.Nodes[0].IsResolved)
		require.Len(t, got.ReviewThreads.Nodes[0].Comments.Nodes, 1)
		require.Empty(t, got.ReviewThreads.Nodes[0].Comments.Nodes[0].Reactions.Nodes)
	})
}

func TestRemoveReactionNoopsWithEmptyReactions(t *testing.T) {
	// A GQLComment from the fallback path has zero-value GQLReactable (no reactions).
	// RemoveReaction should return nil without attempting a mutation.
	comment := GQLComment{
		GQLReactable: GQLReactable{}, // empty — simulates fallback path
		GqlCommentCore: GqlCommentCore{
			ID:     FullDatabaseID(1),
			NodeID: "MDEyOklzc3VlQ29tbWVudDE=",
			Body:   "test",
		},
	}

	appProvider := agenticapptest.NewTestProvider(t)

	// RemoveReaction iterates Reactions.Nodes; with zero nodes it returns nil
	// without calling gh.RemoveReaction, so we can pass nil for the client.
	err := comment.RemoveReaction(context.Background(), nil, GQLReactionContentThumbsUp, appProvider.IsAgenticActor)
	require.NoError(t, err)
}

func TestGetPullRequestContextFallbackBranching(t *testing.T) {
	// Test that the fallback branching logic works correctly:
	// - Resource limit error + flag enabled → should take fallback path
	// - Resource limit error + flag disabled → should return error
	// - Non-resource-limit error + flag enabled → should return error

	t.Run("resource limit error triggers fallback when flag enabled", func(t *testing.T) {
		err := errors.New("Resource limits for this query exceeded. at Line 1, Column 2352")
		flagEnabled := true
		shouldFallback := IsResourceLimitError(err) && flagEnabled
		require.True(t, shouldFallback)
	})

	t.Run("resource limit error does not trigger fallback when flag disabled", func(t *testing.T) {
		err := errors.New("Resource limits for this query exceeded. at Line 1, Column 2352")
		flagEnabled := false
		shouldFallback := IsResourceLimitError(err) && flagEnabled
		require.False(t, shouldFallback)
	})

	t.Run("non-resource-limit error does not trigger fallback even with flag enabled", func(t *testing.T) {
		err := errors.New("API rate limit exceeded")
		flagEnabled := true
		shouldFallback := IsResourceLimitError(err) && flagEnabled
		require.False(t, shouldFallback)
	})

	t.Run("wrapped resource limit error triggers fallback", func(t *testing.T) {
		err := fmt.Errorf("failed to get pull request context: %w", errors.New("Resource limits for this query exceeded."))
		flagEnabled := true
		shouldFallback := IsResourceLimitError(err) && flagEnabled
		require.True(t, shouldFallback)
	})
}

// newTestGQLClient creates a Client wired to the given httptest.Server with the specified feature flags.
func newTestGQLClient(t *testing.T, serverURL string, flags map[string]bool) *Client {
	t.Helper()
	httpClient := oauth2.NewClient(context.Background(), oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: "test-token"},
	))
	gqlClient := githubv4.NewEnterpriseClient(serverURL+"/graphql", httpClient)

	return &Client{
		gqlclient: gqlClient,
		ffClient:  featureflags.NewNoopClient(flags),
		obsv:      observability.NewNoopExporters(),
	}
}

func TestGetPullRequestContextFallbackIntegration(t *testing.T) {
	appProvider := agenticapptest.NewTestProvider(t)

	resourceLimitErrorResp := `{"errors":[{"message":"Resource limits for this query exceeded. at Line 1, Column 2352"}]}`
	successResp := `{"data":{}}`
	otherErrorResp := `{"errors":[{"message":"some other GraphQL error"}]}`

	t.Run("resource limit error with flag enabled triggers fallback query", func(t *testing.T) {
		var requestCount atomic.Int32
		var secondRequestBody string

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			n := requestCount.Add(1)
			w.Header().Set("Content-Type", "application/json")

			if n == 1 {
				// First request: return resource limit error
				w.WriteHeader(http.StatusOK)
				w.Write([]byte(resourceLimitErrorResp))
				return
			}

			// Second request: capture body and return success
			body, _ := io.ReadAll(r.Body)
			secondRequestBody = string(body)
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(successResp))
		}))
		defer server.Close()

		client := newTestGQLClient(t, server.URL, map[string]bool{
			featureflags.CopilotSWEAgentPRContextQueryFallback: true,
		})

		result, err := client.GetPullRequestContext(context.Background(), "repo-node-id", 1, appProvider.IsAgenticActor)
		require.NoError(t, err)
		require.NotNil(t, result, "fallback path should return a non-nil context")

		require.Equal(t, int32(2), requestCount.Load(), "should have made exactly 2 requests (original + fallback)")

		// The fallback query should NOT include maxReactions in its variables.
		var gqlReq map[string]json.RawMessage
		require.NoError(t, json.Unmarshal([]byte(secondRequestBody), &gqlReq))
		var variables map[string]any
		require.NoError(t, json.Unmarshal(gqlReq["variables"], &variables))
		require.NotContains(t, variables, "maxReactions", "fallback query must not include maxReactions variable")
	})

	t.Run("resource limit error with flag disabled returns error", func(t *testing.T) {
		var requestCount atomic.Int32

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestCount.Add(1)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(resourceLimitErrorResp))
		}))
		defer server.Close()

		client := newTestGQLClient(t, server.URL, map[string]bool{
			featureflags.CopilotSWEAgentPRContextQueryFallback: false,
		})

		result, err := client.GetPullRequestContext(context.Background(), "repo-node-id", 1, appProvider.IsAgenticActor)
		require.Error(t, err)
		require.Nil(t, result)
		require.Contains(t, err.Error(), "Resource limits for this query exceeded")

		require.Equal(t, int32(1), requestCount.Load(), "should have made exactly 1 request (no fallback)")
	})

	t.Run("non-resource-limit error with flag enabled returns error without fallback", func(t *testing.T) {
		var requestCount atomic.Int32

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestCount.Add(1)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(otherErrorResp))
		}))
		defer server.Close()

		client := newTestGQLClient(t, server.URL, map[string]bool{
			featureflags.CopilotSWEAgentPRContextQueryFallback: true,
		})

		result, err := client.GetPullRequestContext(context.Background(), "repo-node-id", 1, appProvider.IsAgenticActor)
		require.Error(t, err)
		require.Nil(t, result)

		require.Equal(t, int32(1), requestCount.Load(), "should have made exactly 1 request (no fallback for non-resource-limit errors)")
	})
}

func TestPullRequestContextGetReviewThreadResolvedMap(t *testing.T) {
	t.Run("returns separately-fetched map when available", func(t *testing.T) {
		separateMap := map[int64]bool{1: true, 2: false}
		ctx := &PullRequestContext{
			ReviewThreadResolvedMap: separateMap,
			PullRequest: GQLPullRequest{
				ReviewThreads: GQLConnection[GQLPullRequestReviewThread]{
					Nodes: []GQLPullRequestReviewThread{
						{
							IsResolved: false,
							Comments: GQLConnection[GQLPullRequestReviewComment]{
								Nodes: []GQLPullRequestReviewComment{
									{GQLComment: GQLComment{GqlCommentCore: GqlCommentCore{ID: 99}}},
								},
							},
						},
					},
				},
			},
		}
		result := ctx.GetReviewThreadResolvedMap()
		require.Equal(t, separateMap, result)
		// Should NOT include comment 99 from embedded ReviewThreads
		_, exists := result[99]
		require.False(t, exists)
	})

	t.Run("falls back to PullRequest.ReviewThreads when map is nil", func(t *testing.T) {
		ctx := &PullRequestContext{
			ReviewThreadResolvedMap: nil,
			PullRequest: GQLPullRequest{
				ReviewThreads: GQLConnection[GQLPullRequestReviewThread]{
					Nodes: []GQLPullRequestReviewThread{
						{
							IsResolved: true,
							Comments: GQLConnection[GQLPullRequestReviewComment]{
								Nodes: []GQLPullRequestReviewComment{
									{GQLComment: GQLComment{GqlCommentCore: GqlCommentCore{ID: 42}}},
									{GQLComment: GQLComment{GqlCommentCore: GqlCommentCore{ID: 43}}},
								},
							},
						},
					},
				},
			},
		}
		result := ctx.GetReviewThreadResolvedMap()
		require.Equal(t, map[int64]bool{42: true, 43: true}, result)
	})

	t.Run("returns empty non-nil map when separate map is empty", func(t *testing.T) {
		ctx := &PullRequestContext{
			ReviewThreadResolvedMap: make(map[int64]bool),
		}
		result := ctx.GetReviewThreadResolvedMap()
		require.NotNil(t, result)
		require.Empty(t, result)
	})
}

func TestGetPullRequestContextSeparateReviewThreads(t *testing.T) {
	appProvider := agenticapptest.NewTestProvider(t)
	successResp := `{"data":{}}`

	t.Run("separate review threads flag routes to optimized path", func(t *testing.T) {
		var requestCount atomic.Int32
		var mu sync.Mutex
		var requestBodies []string

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestCount.Add(1)
			body, _ := io.ReadAll(r.Body)
			mu.Lock()
			requestBodies = append(requestBodies, string(body))
			mu.Unlock()
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(successResp))
		}))
		defer server.Close()

		client := newTestGQLClient(t, server.URL, map[string]bool{
			featureflags.CopilotSWEAgentPRContextSeparateReviewThreads: true,
		})

		result, err := client.GetPullRequestContext(context.Background(), "repo-node-id", 1, appProvider.IsAgenticActor)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should make 2 requests: optimized PR context + separate review threads query
		require.Equal(t, int32(2), requestCount.Load(), "should make 2 requests (optimized context + review threads)")

		// One request should NOT contain reviewThreads (the main query), the other SHOULD
		hasReviewThreads := 0
		withoutReviewThreads := 0
		for _, body := range requestBodies {
			if strings.Contains(body, "reviewThreads") {
				hasReviewThreads++
			} else {
				withoutReviewThreads++
			}
		}
		require.Equal(t, 1, hasReviewThreads, "exactly one request should contain reviewThreads")
		require.Equal(t, 1, withoutReviewThreads, "exactly one request should not contain reviewThreads")
	})

	t.Run("separate review threads flag disabled uses original path", func(t *testing.T) {
		var requestCount atomic.Int32
		var mu sync.Mutex
		var requestBodies []string

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestCount.Add(1)
			body, _ := io.ReadAll(r.Body)
			mu.Lock()
			requestBodies = append(requestBodies, string(body))
			mu.Unlock()
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(successResp))
		}))
		defer server.Close()

		client := newTestGQLClient(t, server.URL, map[string]bool{
			featureflags.CopilotSWEAgentPRContextSeparateReviewThreads: false,
		})

		result, err := client.GetPullRequestContext(context.Background(), "repo-node-id", 1, appProvider.IsAgenticActor)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should make only 1 request (original full query)
		require.Equal(t, int32(1), requestCount.Load(), "should make 1 request (original path)")

		// The query should contain reviewThreads
		require.Contains(t, requestBodies[0], "reviewThreads")
	})

	t.Run("optimized path with resource limit falls back to optimized fallback", func(t *testing.T) {
		resourceLimitErrorResp := `{"errors":[{"message":"Resource limits for this query exceeded. at Line 1, Column 2352"}]}`
		var requestCount atomic.Int32

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			n := requestCount.Add(1)
			w.Header().Set("Content-Type", "application/json")
			if n == 1 {
				w.WriteHeader(http.StatusOK)
				w.Write([]byte(resourceLimitErrorResp))
				return
			}
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(successResp))
		}))
		defer server.Close()

		client := newTestGQLClient(t, server.URL, map[string]bool{
			featureflags.CopilotSWEAgentPRContextSeparateReviewThreads: true,
			featureflags.CopilotSWEAgentPRContextQueryFallback:         true,
		})

		result, err := client.GetPullRequestContext(context.Background(), "repo-node-id", 1, appProvider.IsAgenticActor)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should make 3 requests: optimized (fails) + optimized fallback + review threads
		require.Equal(t, int32(3), requestCount.Load())
	})

	t.Run("populates ReviewThreadResolvedMap from separate query response", func(t *testing.T) {
		// First request: optimized PR context (no reviewThreads)
		prContextResp := `{"data":{"node":{"pullRequest":{"number":42}}}}`
		// Second request: separate review threads query with resolved data
		reviewThreadsResp := `{"data":{"node":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":true,"comments":{"nodes":[{"fullDatabaseId":"100"},{"fullDatabaseId":"101"}]}},{"isResolved":false,"comments":{"nodes":[{"fullDatabaseId":"200"}]}}]}}}}}`

		var requestCount atomic.Int32
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			n := requestCount.Add(1)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			if n == 1 {
				w.Write([]byte(prContextResp))
			} else {
				w.Write([]byte(reviewThreadsResp))
			}
		}))
		defer server.Close()

		client := newTestGQLClient(t, server.URL, map[string]bool{
			featureflags.CopilotSWEAgentPRContextSeparateReviewThreads: true,
		})

		result, err := client.GetPullRequestContext(context.Background(), "repo-node-id", 42, appProvider.IsAgenticActor)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Verify the resolved map is correctly populated
		expected := map[int64]bool{100: true, 101: true, 200: false}
		require.Equal(t, expected, result.ReviewThreadResolvedMap)
		require.Equal(t, expected, result.GetReviewThreadResolvedMap())
	})

	t.Run("returns error when separate review threads query fails", func(t *testing.T) {
		prContextResp := `{"data":{"node":{"pullRequest":{"number":1}}}}`
		reviewThreadsErrorResp := `{"errors":[{"message":"Something went wrong"}]}`

		var requestCount atomic.Int32
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			n := requestCount.Add(1)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			if n == 1 {
				w.Write([]byte(prContextResp))
			} else {
				w.Write([]byte(reviewThreadsErrorResp))
			}
		}))
		defer server.Close()

		client := newTestGQLClient(t, server.URL, map[string]bool{
			featureflags.CopilotSWEAgentPRContextSeparateReviewThreads: true,
		})

		result, err := client.GetPullRequestContext(context.Background(), "repo-node-id", 1, appProvider.IsAgenticActor)
		require.Error(t, err)
		require.Nil(t, result)
		require.Contains(t, err.Error(), "Something went wrong")
	})
}
