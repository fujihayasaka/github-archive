package github

import (
	"context"

	"github.com/google/go-github/v65/github"
)

// IssuesService is an interface which describes the methods of the
// github.IssuesService type. These methods are abstracted to an interface
// so that we can implement a mock client and use it for unit testing.
type IssuesService interface {
	Edit(ctx context.Context, owner string, repo string, number int, issue *github.IssueRequest) (*github.Issue, *github.Response, error)
	ListByRepo(ctx context.Context, owner string, repo string, opts *github.IssueListByRepoOptions) ([]*github.Issue, *github.Response, error)
	ListComments(ctx context.Context, owner string, repo string, number int, opts *github.IssueListCommentsOptions) ([]*github.IssueComment, *github.Response, error)
}

// PullRequestsService is an interface which describes the methods of the
// github.PullRequestsService type. These methods are abstracted to an interface
// so that we can implement a mock client and use it for unit testing.
type PullRequestsService interface {
	List(ctx context.Context, owner string, repo string, opts *github.PullRequestListOptions) ([]*github.PullRequest, *github.Response, error)
	ListReviews(ctx context.Context, owner, repo string, number int, opts *github.ListOptions) ([]*github.PullRequestReview, *github.Response, error)
	ListReviewComments(ctx context.Context, owner, repo string, number int, reviewID int64, opts *github.ListOptions) ([]*github.PullRequestComment, *github.Response, error)
	GetComment(ctx context.Context, owner, repo string, commentID int64) (*github.PullRequestComment, *github.Response, error)
}

// RepositoriesService is an interface which describes the methods of the
// github.RepositoriesService type. These methods are abstracted to an interface
// so that we can implement a mock client and use it for unit testing.
type RepositoriesService interface {
	CreateHook(ctx context.Context, owner, repo string, hook *github.Hook) (*github.Hook, *github.Response, error)
	ListHookDeliveries(ctx context.Context, owner, repo string, id int64, opts *github.ListCursorOptions) ([]*github.HookDelivery, *github.Response, error)
	RedeliverHookDelivery(ctx context.Context, owner, repo string, hookID, deliveryID int64) (*github.HookDelivery, *github.Response, error)
	Get(ctx context.Context, owner, repo string) (*github.Repository, *github.Response, error)
}

// ReactionsService is an interface which describes the methods of the
// github.ReactionsService type. These methods are abstracted to an interface
// so that we can implement a mock client and use it for unit testing.
type ReactionsService interface {
	ListIssueReactions(ctx context.Context, owner, repo string, issueNumber int, opts *github.ListOptions) ([]*github.Reaction, *github.Response, error)
	ListIssueCommentReactions(ctx context.Context, owner, repo string, id int64, opts *github.ListOptions) ([]*github.Reaction, *github.Response, error)
}

// CommitCommentsService is an interface which describes the methods of the
// github.CommitCommentsService type. These methods are abstracted to an interface
// so that we can implement a mock client and use it for unit testing.
type CommitCommentsService interface {
	ListComments(ctx context.Context, owner, repo string, opts *github.ListOptions) ([]*github.RepositoryComment, *github.Response, error)
}
