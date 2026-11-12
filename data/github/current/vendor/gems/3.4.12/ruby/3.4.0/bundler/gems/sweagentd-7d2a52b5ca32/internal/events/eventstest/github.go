package eventstest

import (
	gg "github.com/google/go-github/v75/github"
)

// GGInstallation returns a [gg.Installation] that can be used across tests.
func GGInstallation() *gg.Installation {
	return &gg.Installation{
		ID: gg.Ptr(InstallationID),
	}
}

// GGUser returns a [gg.User] that can be used across tests.
// The IDs are derived from the login and will be consistent across calls
// and other types representing the same user.
func GGUser(login string) *gg.User {
	id, nodeID := IDsFromString(login)
	user := &gg.User{
		ID:     gg.Ptr(id),
		NodeID: gg.Ptr(nodeID),
		Login:  gg.Ptr(login),
		Name:   gg.Ptr(login),
	}

	if login == GitHubBotLogin || login == ActorLoginBot {
		user.Type = gg.Ptr("Bot")
	} else {
		user.Type = gg.Ptr("User")
	}

	return user
}

// GGUserCopilot is a convenience function that returns a [gg.User] for Copilot.
func GGUserCopilot() *gg.User {
	return GGUser(GitHubBotLogin)
}

// GGUserAdmin is a convenience function that returns a [gg.User] with admin permissions.
func GGUserAdmin() *gg.User {
	return GGUser(ActorLoginAdmin)
}

// GGUserWriter is a convenience function that returns a [gg.User] with write permissions.
func GGUserWriter() *gg.User {
	return GGUser(ActorLoginWriter)
}

// GGUserReader is a convenience function that returns a [gg.User] with read permissions.
func GGUserReader() *gg.User {
	return GGUser(ActorLoginReader)
}

// GGUserNone is a convenience function that returns a [gg.User] with no permissions.
func GGUserNone() *gg.User {
	return GGUser(ActorLoginNone)
}

// GGOwner is a convenience function that returns a [gg.User] for the repository owner.
func GGOwner() *gg.User {
	id, nodeID := IDsFromString(RepoOwner)
	return &gg.User{
		ID:     gg.Ptr(id),
		NodeID: gg.Ptr(nodeID),
		Login:  gg.Ptr(RepoOwner),
		Name:   gg.Ptr(RepoOwner),
		Type:   gg.Ptr("Organization"),
	}
}

// GGRepository returns a [gg.Repository] that can be used across tests.
// The IDs are derived from the repo name and owner, and will be consistent across
// calls and other types representing the same repo.
func GGRepository() *gg.Repository {
	id, nodeID := IDsFromString(RepoName)
	return &gg.Repository{
		ID:      gg.Ptr(id),
		NodeID:  gg.Ptr(nodeID),
		Name:    gg.Ptr(RepoName),
		Owner:   GGOwner(),
		Private: gg.Ptr(true),
	}
}

// GGIssue returns a [gg.Issue] using [IssueNumber] for the number and the optional assignees.
func GGIssue(assignees ...*gg.User) *gg.Issue {
	return GGIssueWithNumber(IssueNumber, assignees...)
}

// GGIssueWithNumber returns a [gg.Issue] using the provided number and the optional assignees.
func GGIssueWithNumber(number int, assignees ...*gg.User) *gg.Issue {
	id, nodeID := IDsFromStringAndInt(NameForIDsIssue, number)
	return &gg.Issue{
		ID:        gg.Ptr(id),
		NodeID:    gg.Ptr(nodeID),
		Number:    gg.Ptr(number),
		Title:     gg.Ptr(IssueTitle),
		Body:      gg.Ptr(IssueBody),
		State:     gg.Ptr("OPEN"),
		Draft:     gg.Ptr(false),
		Assignees: assignees,
	}
}

// GGPullRequestIssue returns a [gg.Issue] that is a pull request using
// [PullRequestNumber] for the number and the optional assignees.
func GGPullRequestIssue(assignees ...*gg.User) *gg.Issue {
	return GGPullRequestIssueWithNumber(PullRequestNumber, assignees...)
}

// GGPullRequestIssueWithNumber returns a [gg.Issue] that is a pull request using
// the provided number and the optional assignees.
func GGPullRequestIssueWithNumber(number int, assignees ...*gg.User) *gg.Issue {
	issue := GGIssueWithNumber(number, assignees...)
	issue.PullRequestLinks = &gg.PullRequestLinks{
		URL: gg.Ptr("foo"),
	}
	return issue
}

// GGPullRequest returns a [gg.PullRequest] using [PullRequestNumber] for the
// number and the optional assignees.
func GGPullRequest(assignees ...*gg.User) *gg.PullRequest {
	return GGPullRequestWithNumber(PullRequestNumber, assignees...)
}

// GGPullRequestWithNumber returns a [gg.PullRequest] using the provided number
// and the optional assignees.
func GGPullRequestWithNumber(number int, assignees ...*gg.User) *gg.PullRequest {
	id, nodeID := IDsFromStringAndInt(NameForIDsPullRequest, number)
	return &gg.PullRequest{
		ID:        gg.Ptr(id),
		NodeID:    gg.Ptr(nodeID),
		Number:    gg.Ptr(number),
		Title:     gg.Ptr(PullRequestTitle),
		Body:      gg.Ptr(PullRequestBody),
		State:     gg.Ptr("OPEN"),
		Draft:     gg.Ptr(true),
		Assignees: assignees,
	}
}

// GGIssueComment returns a [gg.IssueComment] using the provided author.
func GGIssueComment(author *gg.User) *gg.IssueComment {
	id, nodeID := IDsFromStrings(NameForIDsIssueComment, author.GetLogin())
	return &gg.IssueComment{
		ID:     gg.Ptr(id),
		NodeID: gg.Ptr(nodeID),
		Body:   gg.Ptr(IssueCommentBody),
		User:   author,
	}
}

// GGPullRequestReview returns a [gg.PullRequestReview] using the provided author.
func GGPullRequestReview(author *gg.User) *gg.PullRequestReview {
	id, nodeID := IDsFromStrings(NameForIDsPullRequestReview, author.GetLogin())
	return &gg.PullRequestReview{
		ID:     gg.Ptr(id),
		NodeID: gg.Ptr(nodeID),
		Body:   gg.Ptr(PullRequestReviewBody),
		User:   author,
	}
}
