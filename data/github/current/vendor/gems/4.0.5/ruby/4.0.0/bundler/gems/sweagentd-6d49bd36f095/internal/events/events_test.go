package events

import (
	"fmt"
	"time"

	et "github.com/github/sweagentd/internal/events/eventstest"
	gh "github.com/github/sweagentd/internal/github"
)

// EventActor returns a new [Actor] with the from a given [GQLActorOrUser].
func EventActor(a gh.GQLActorOrUser) *Actor {
	return &Actor{
		ID:     a.GetID(),
		NodeID: a.GetNodeID(),
		Login:  a.GetLogin(),
		Type:   a.GetType(),
	}
}

func eventActor(login string) *Actor {
	id, nodeID := et.IDsFromString(login)
	actor := &Actor{
		ID:     id,
		NodeID: nodeID,
		Login:  login,
	}

	if login == et.GitHubBotLogin || login == et.ActorLoginBot {
		actor.Type = "Bot"
	} else {
		actor.Type = "User"
	}

	return actor
}

// EventActorCopilot is a convenience function to return an [Actor] for Copilot.
func EventActorCopilot() *Actor {
	return eventActor(et.GitHubBotLogin)
}

// EventActorBot is a convenience function to return an [Actor] for a bot.
func EventActorBot() *Actor {
	return eventActor(et.GitHubBotLogin)
}

// EventActorAdmin is a convenience function to return an [Actor] with admin permissions.
func EventActorAdmin() *Actor {
	return eventActor(et.ActorLoginAdmin)
}

// EventActorWriter is a convenience function to return an [Actor] with write permissions.
func EventActorWriter() *Actor {
	return eventActor(et.ActorLoginWriter)
}

// EventActorReader is a convenience function to return an [Actor] with read permissions.
func EventActorReader() *Actor {
	return eventActor(et.ActorLoginReader)
}

// EventActorNone is a convenience function to return an [Actor] with no permissions.
func EventActorNone() *Actor {
	return eventActor(et.ActorLoginNone)
}

// EventRepository returns a new [Repository] that can be used across tests.
// The IDs are derived from the repo name and owner, and will be consistent across
// calls and other types representing the same repo.
func EventRepository() *Repository {
	id, nodeID := et.IDsFromString(et.RepoName)
	ownerID, _ := et.IDsFromString(et.RepoOwner)
	return &Repository{
		ID:        id,
		NodeID:    nodeID,
		Name:      et.RepoName,
		OwnerID:   ownerID,
		IsPrivate: true,
	}
}

// EventIssue returns a new [Issue] using the default issue number.
func EventIssue() *Issue {
	return EventIssueWithNumber(et.IssueNumber)
}

// EventIssueWithNumber returns a new [Issue] using the given issue number.
func EventIssueWithNumber(number int) *Issue {
	id, nodeID := et.IDsFromStringAndInt(et.NameForIDsIssue, number)
	return &Issue{
		ID:     id,
		NodeID: nodeID,
		Number: number,
		IsOpen: true,
	}
}

// EventPullRequestIssue returns a new [PullRequestIssue] using the default pull request number.
func EventPullRequestIssue() *PullRequestIssue {
	return EventPullRequestIssueWithNumber(et.PullRequestNumber)
}

// EventPullRequestIssueWithNumber returns a new [PullRequestIssue] using the given pull request number.
func EventPullRequestIssueWithNumber(number int) *PullRequestIssue {
	_, nodeID := et.IDsFromStringAndInt(et.NameForIDsPullRequest, number)
	return &PullRequestIssue{
		NodeID: nodeID,
		Number: number,
		IsOpen: true,
	}
}

// EventPullRequest returns a new [PullRequest] using the default pull request number.
func EventPullRequest() *PullRequest {
	return EventPullRequestWithNumber(et.PullRequestNumber)
}

// EventPullRequestWithNumber returns a new [PullRequest] using the given pull request number.
func EventPullRequestWithNumber(number int) *PullRequest {
	id, nodeID := et.IDsFromStringAndInt(et.NameForIDsPullRequest, number)
	draft := false

	return &PullRequest{
		ID:         id,
		NodeID:     nodeID,
		Number:     number,
		IsOpen:     true,
		IsDraft:    &draft,
		AuthorID:   EventActorCopilot().ID,
		HeadBranch: fmt.Sprintf("copilot/fix-%d", number),
		BaseBranch: "main",
	}
}

// EventPullRequestReview returns a new [PullRequestReview] attributed to the given author.
func EventPullRequestReview(author gh.GQLActorOrUser) *PullRequestReview {
	id, _ := et.IDsFromStrings(et.NameForIDsPullRequestReview, author.GetLogin())
	return &PullRequestReview{
		ID:   id,
		Body: "review body without mention",
	}
}

// EventPullRequestReviewWithCopilotMention returns a new [PullRequestReview] attributed to the given author that mentions @copilot.
func EventPullRequestReviewWithCopilotMention(author gh.GQLActorOrUser) *PullRequestReview {
	id, _ := et.IDsFromStrings(et.NameForIDsPullRequestReview, author.GetLogin())
	return &PullRequestReview{
		ID:   id,
		Body: "@copilot please review this",
	}
}

// EventPullRequestComment returns a new [PullRequestComment] attributed to the given author.
func EventPullRequestComment(author gh.GQLActorOrUser) *PullRequestComment {
	id, nodeID := et.IDsFromStrings(et.NameForIDsIssueComment, author.GetLogin())
	return &PullRequestComment{
		ID:     id,
		NodeID: nodeID,
	}
}

// EventPullRequestReviewComment returns a new [PullRequestComment] attributed to the given author.
func EventPullRequestReviewComment(author gh.GQLActorOrUser) *PullRequestComment {
	id, nodeID := et.IDsFromStrings(et.NameForIDsPullRequestReviewComment, author.GetLogin())
	return &PullRequestComment{
		ID:     id,
		NodeID: nodeID,
	}
}

// EventWorkflowRepository returns a new [WorkflowRepository] using the default repo name and owner.
func EventWorkflowRepository() *WorkflowRepository {
	id, _ := et.IDsFromString(et.RepoName)
	ownerID, _ := et.IDsFromString(et.RepoOwner)
	return &WorkflowRepository{
		ID:      id,
		OwnerID: ownerID,
	}
}

// EventWorkflowRun returns a new [WorkflowRun] using the default workflow run number.
func EventWorkflowRun() *WorkflowRun {
	return EventWorkflowRunWithNumber(et.PullRequestNumber)
}

// EventWorkflowRunWithNumber returns a new [WorkflowRun] using the given workflow run number.
func EventWorkflowRunWithNumber(number int) *WorkflowRun {
	return EventWorkflowRunWithNumberAndConclusion(number, "success")
}

// EventWorkflowJobWithConclusion returns a new [WorkflowJob] using the given conclusion.
func EventWorkflowRunWithConclusion(conclusion string) *WorkflowRun {
	return EventWorkflowRunWithNumberAndConclusion(et.PullRequestNumber, conclusion)
}

// EventWorkflowRunWithNumber returns a new [WorkflowRun] using the given workflow run number.
func EventWorkflowRunWithNumberAndConclusion(number int, conclusion string) *WorkflowRun {
	id, _ := et.IDsFromStringAndInt(et.NameForIDsWorkflowRun, number)
	cID, _ := et.IDsFromString(et.GitHubBotLogin)
	startedAt := time.Now().Add(-time.Minute * 30)
	completedAt := time.Now()

	return &WorkflowRun{
		ID:           id,
		UserID:       cID,
		Path:         fmt.Sprintf("dynamic/%s/copilot", et.GitHubAppLogin),
		Status:       WorkflowCompletedEventStatusCompleted,
		Conclusion:   conclusion,
		CheckSuiteID: 0,
		Attempt:      1,
		StartedAt:    startedAt.Unix(),
		CompletedAt:  completedAt.Unix(),
		UsageMs:      completedAt.Sub(startedAt).Milliseconds(),
	}
}

func EventCodeScanningAlert() *CodeScanningAlert {
	sf_file := &SuggestedFixFile{
		FilePath:    "test.txt",
		DiffContent: []byte("diff content"),
	}
	sf := &SuggestedFix{
		Files: []*SuggestedFixFile{
			sf_file,
		},
	}
	alert := &CodeScanningAlert{
		Number:       123,
		SuggestedFix: sf,
	}
	return alert
}
