package eventstest

import (
	"fmt"
	mathrand "math/rand"
	"time"

	"github.com/github/sweagentd/internal/github"
)

func actor(login string, actorType string) *github.GQLActor {
	id, nodeID := IDsFromString(login)
	actor := github.NewGQLActor(id, nodeID, login, actorType, login)
	return &actor
}

// ActorBot is a convenience function to create a bot actor.
func ActorBot() *github.GQLActor {
	return actor(ActorLoginBot, github.GQLActorTypeBot)
}

// ActorAdmin is a convenience function to create an actor with admin permissions.
func ActorAdmin() *github.GQLActor {
	return actor(ActorLoginAdmin, github.GQLActorTypeUser)
}

// ActorWriter is a convenience function to create an actor with write permissions.
func ActorWriter() *github.GQLActor {
	return actor(ActorLoginWriter, github.GQLActorTypeUser)
}

// ActorReader is a convenience function to create an actor with read permissions.
func ActorReader() *github.GQLActor {
	return actor(ActorLoginReader, github.GQLActorTypeUser)
}

// ActorNone is a convenience function to create an actor with no permissions.
func ActorNone() *github.GQLActor {
	return actor(ActorLoginNone, github.GQLActorTypeUser)
}

// ActorCopilot is a convenience function to create a copilot actor.
func ActorCopilot() *github.GQLActor {
	return actor(GitHubBotLogin, github.GQLActorTypeBot)
}

func user(login string) *github.GQLUser {
	id, nodeID := IDsFromString(login)
	user := github.GQLUser{
		ID:     id,
		NodeID: nodeID,
		Login:  login,
		Name:   login,
	}
	return &user
}

// UserBot is a convenience function to create a bot user.
func UserBot() *github.GQLUser {
	return user(GitHubBotLogin)
}

// UserAdmin is a convenience function to create a user with admin permissions.
func UserAdmin() *github.GQLUser {
	return user(ActorLoginAdmin)
}

// UserWriter is a convenience function to create a user with write permissions.
func UserWriter() *github.GQLUser {
	return user(ActorLoginWriter)
}

// UserReader is a convenience function to create a user with read permissions.
func UserReader() *github.GQLUser {
	return user(ActorLoginReader)
}

// UserNone is a convenience function to create user with no permissions.
func UserNone() *github.GQLUser {
	return user(ActorLoginNone)
}

// UserCopilot is a convenience function to create a copilot user.
func UserCopilot() *github.GQLUser {
	return user(GitHubBotLogin)
}

// Repo returns a repository with the name and owner set to the global variables [RepoName] and [RepoOwner].
func Repo() *github.GQLRepository {
	id, nodeID := IDsFromString(RepoName)
	oID, oNodeID := IDsFromString(RepoOwner)
	repo := github.GQLRepository{
		ID:               id,
		NodeID:           nodeID,
		Name:             RepoName,
		NameWithOwner:    RepoOwner + "/" + RepoName,
		HasIssuesEnabled: true,
		IsPrivate:        true,
		Owner:            github.NewGQLRepositoryOwner(oID, oNodeID, RepoOwner, github.GQLRepositoryOwnerTypeOrganization, RepoOwner),
		DefaultBranchRef: &github.GQLRef{Name: "main"},
	}
	return &repo
}

// Issue returns an issue with the given assignees.
func Issue(assignees ...github.GQLUser) *github.GQLIssue {
	return IssueWithNumber(IssueNumber, assignees...)
}

// IssueWithNumber returns an issue with the given issue number and assignees.
func IssueWithNumber(number int, assignees ...github.GQLUser) *github.GQLIssue {
	id, nodeID := IDsFromStringAndInt(NameForIDsIssue, number)
	issue := github.GQLIssue{
		GQLComment: github.GQLComment{
			GqlCommentCore: github.GqlCommentCore{
				ID:        github.FullDatabaseID(id),
				NodeID:    nodeID,
				Body:      IssueBody,
				CreatedAt: time.Now().Add(-time.Hour),
			},
		},
		Title:  IssueTitle,
		Number: number,
		State:  github.GQLIssueStateOpen,
		GQLAssignable: github.GQLAssignable{
			Assignees: github.GQLConnection[github.GQLUser]{
				TotalCount: len(assignees),
				Nodes:      assignees,
			},
			AssignedActors: github.GQLConnection[github.GQLActor]{
				TotalCount: len(assignees),
				Nodes:      toActors(assignees),
			},
		},
	}
	return &issue
}

// PullRequest returns a pull request with the given assignees.
// The author of the pull request is Copilot.
func PullRequest(assignees ...github.GQLUser) *github.GQLPullRequest {
	return PullRequestWithAuthor(ActorCopilot(), assignees...)
}

// PullRequestWithAuthor returns a pull request with the given author and assignees.
func PullRequestWithAuthor(author *github.GQLActor, assignees ...github.GQLUser) *github.GQLPullRequest {
	return PullRequestWithNumberAndAuthor(PullRequestNumber, author, assignees...)
}

// PullRequestWithNumberAndAuthor returns a pull request with the given number, author, and assignees.
func PullRequestWithNumberAndAuthor(number int, author *github.GQLActor, assignees ...github.GQLUser) *github.GQLPullRequest {
	id, nodeID := IDsFromStringAndInt(NameForIDsPullRequest, number)
	pr := github.GQLPullRequest{
		GQLComment: github.GQLComment{
			GqlCommentCore: github.GqlCommentCore{
				ID:        github.FullDatabaseID(id),
				NodeID:    nodeID,
				Author:    *author,
				Body:      PullRequestBody,
				CreatedAt: time.Now().Add(-time.Hour),
			},
		},
		Title:  PullRequestTitle,
		Number: number,
		GQLAssignable: github.GQLAssignable{
			Assignees: github.GQLConnection[github.GQLUser]{
				TotalCount: len(assignees),
				Nodes:      assignees,
			},
			AssignedActors: github.GQLConnection[github.GQLActor]{
				TotalCount: len(assignees),
				Nodes:      toActors(assignees),
			},
		},
		BaseRef: github.GQLRef{Name: "base-ref"},
		HeadRef: github.GQLRef{Name: "head-ref"},
	}
	return &pr
}

// AddAssigneesToIssue adds the given assignees to the issue and returns the issue.
func AddAssigneesToIssue(i *github.GQLIssue, assignees ...github.GQLUser) *github.GQLIssue {
	i.Assignees = github.GQLConnection[github.GQLUser]{
		TotalCount: len(assignees),
		Nodes:      assignees,
	}
	i.AssignedActors = github.GQLConnection[github.GQLActor]{
		TotalCount: len(assignees),
		Nodes:      toActors(assignees),
	}
	return i
}

// AddAssigneesToPullRequest adds the given assignees to the pull request and returns the pull request.
func AddAssigneesToPullRequest(pr *github.GQLPullRequest, assignees ...github.GQLUser) *github.GQLPullRequest {
	pr.Assignees = github.GQLConnection[github.GQLUser]{
		TotalCount: len(assignees),
		Nodes:      assignees,
	}
	pr.AssignedActors = github.GQLConnection[github.GQLActor]{
		TotalCount: len(assignees),
		Nodes:      toActors(assignees),
	}
	return pr
}

// toActors converts a slice of GQLUsers to a slice of GQLActors
func toActors(users []github.GQLUser) []github.GQLActor {
	actors := make([]github.GQLActor, len(users))
	for i, user := range users {
		actors[i] = user.ToActor()
	}
	return actors
}

func IssueComment(author github.GQLActor, withAtCopilot bool) *github.GQLIssueComment {
	return issueCommentWithBody(author, withAtCopilot, IssueCommentBody)
}

func issueCommentWithBody(author github.GQLActor, withAtCopilot bool, body string) *github.GQLIssueComment {
	if withAtCopilot {
		body = fmt.Sprintf("@copilot %s", body)
	}
	id, nodeID := IDsFromStrings(NameForIDsIssueComment, author.GetLogin())
	return &github.GQLIssueComment{
		GQLComment: github.GQLComment{
			GqlCommentCore: github.GqlCommentCore{
				ID:        github.FullDatabaseID(id),
				NodeID:    nodeID,
				Author:    author,
				Body:      body,
				CreatedAt: time.Now().Add(-time.Hour),
			},
		},
		GQLMinimizable: github.GQLMinimizable{
			IsMinimized: false,
		},
	}
}

// AddCommentToIssue adds a comment attributed to the actor to the issue and returns the issue.
func AddCommentToIssue(i *github.GQLIssue, withAtCopilot bool, actor github.GQLActor) *github.GQLIssue {
	comment := IssueComment(actor, withAtCopilot)
	i.Comments = github.GQLConnection[github.GQLIssueComment]{
		TotalCount: 1,
		Nodes:      []github.GQLIssueComment{*comment},
	}
	return i
}

// AddCommentsToIssue adds a comment for each actor to the issue and returns the issue.
func AddCommentsToIssue(i *github.GQLIssue, withAtCopilot bool, actors ...github.GQLActor) *github.GQLIssue {
	comments := make([]github.GQLIssueComment, 0, len(actors))
	for _, actor := range actors {
		comments = append(comments, *IssueComment(actor, withAtCopilot))
	}
	i.Comments = github.GQLConnection[github.GQLIssueComment]{
		TotalCount: len(actors),
		Nodes:      comments,
	}
	return i
}

// AddCommentToPullRequest adds a comment attributed to the actor to the pull request and returns the pull request.
func AddCommentToPullRequest(pr *github.GQLPullRequest, withAtCopilot bool, actor github.GQLActor) *github.GQLPullRequest {
	comment := IssueComment(actor, withAtCopilot)
	pr.Comments = github.GQLConnection[github.GQLIssueComment]{
		TotalCount: 1,
		Nodes:      []github.GQLIssueComment{*comment},
	}
	return pr
}

// AddCommentToPullRequestWithBody adds a comment with the body attributed to the actor to the pull request and returns the pull request.
func AddCommentToPullRequestWithBody(pr *github.GQLPullRequest, withAtCopilot bool, actor github.GQLActor, body string) *github.GQLPullRequest {
	comment := issueCommentWithBody(actor, withAtCopilot, body)
	pr.Comments = github.GQLConnection[github.GQLIssueComment]{
		TotalCount: 1,
		Nodes:      []github.GQLIssueComment{*comment},
	}
	return pr
}

// AddCommentsToPullRequest adds a comment for each commenter to the pull request and returns the pull request.
func AddCommentsToPullRequest(pr *github.GQLPullRequest, withAtCopilot bool, commenters ...github.GQLActor) *github.GQLPullRequest {
	comments := make([]github.GQLIssueComment, 0, len(commenters))
	for _, actor := range commenters {
		comments = append(comments, *IssueComment(actor, withAtCopilot))
	}
	pr.Comments = github.GQLConnection[github.GQLIssueComment]{
		TotalCount: len(commenters),
		Nodes:      comments,
	}
	return pr
}

func pullRequestReviewComment(actor github.GQLActor, withAtCopilot bool) *github.GQLPullRequestReviewComment {
	body := PullRequestReviewCommentBody
	if withAtCopilot {
		body = fmt.Sprintf("@copilot %s", body)
	}
	id, nodeID := IDsFromStrings(NameForIDsPullRequestReviewComment, actor.GetLogin())
	return &github.GQLPullRequestReviewComment{
		GQLComment: github.GQLComment{
			GqlCommentCore: github.GqlCommentCore{
				ID:        github.FullDatabaseID(id),
				NodeID:    nodeID,
				Author:    actor,
				Body:      body,
				CreatedAt: time.Now().Add(-time.Hour),
			},
		},
		GqlReviewCommentFields: github.GqlReviewCommentFields{
			SubjectType:  github.GQLPullRequestReviewThreadSubjectTypeLine,
			Path:         "path",
			Line:         mathrand.Intn(100),
			OriginalLine: mathrand.Intn(100),
		},
		GQLMinimizable: github.GQLMinimizable{
			IsMinimized: false,
		},
	}
}

// AddReviewToPullRequest adds a pull request review attributed to the author to the pull request
// and a comment for each commenter to the review and returns the pull request.
func AddReviewToPullRequest(pr *github.GQLPullRequest, withAtCopilot bool, author github.GQLActor, commenters ...github.GQLActor) *github.GQLPullRequest {
	body := PullRequestReviewBody
	if withAtCopilot {
		body = fmt.Sprintf("@copilot %s", body)
	}
	id, nodeID := IDsFromStrings(NameForIDsPullRequestReview, author.GetLogin())
	review := github.GQLPullRequestReview{
		GQLComment: github.GQLComment{
			GqlCommentCore: github.GqlCommentCore{
				ID:        github.FullDatabaseID(id),
				NodeID:    nodeID,
				Author:    author,
				Body:      body,
				CreatedAt: time.Now().Add(-time.Hour),
			},
		},
		GQLMinimizable: github.GQLMinimizable{
			IsMinimized: false,
		},
	}

	if len(commenters) > 0 {
		prComments := make([]github.GQLPullRequestReviewComment, 0, len(commenters))
		for _, actor := range commenters {
			prComments = append(prComments, *pullRequestReviewComment(actor, withAtCopilot))
		}

		review.Comments = github.GQLConnection[github.GQLPullRequestReviewComment]{
			TotalCount: len(prComments),
			Nodes:      prComments,
		}
	} else {
		review.State = github.GQLPullRequestReviewStateApproved
	}

	pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
		TotalCount: 1,
		Nodes:      []github.GQLPullRequestReview{review},
	}

	return pr
}
