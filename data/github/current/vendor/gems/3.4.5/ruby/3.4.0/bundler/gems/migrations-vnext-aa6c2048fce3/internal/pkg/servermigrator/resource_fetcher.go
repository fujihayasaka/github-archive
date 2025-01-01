package servermigrator

import (
	"context"
	"fmt"
	"iter"
	"sync"

	"github.com/github/migrations-vnext/internal/pkg/adapters/googlegithub"
	"github.com/github/migrations-vnext/internal/pkg/github"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	ogithub "github.com/google/go-github/v65/github"
	"github.com/shurcooL/githubv4"
)

type (
	// ResourceFetcher is a type that fetches resources from the GitHub API and transform them into
	// v1.Resource messages.
	ResourceFetcher struct {
		c                                *github.Client
		owner                            string
		repo                             string
		org                              string
		err                              error
		fetchIssues                      fetchIssues
		fetchIssueComments               fetchIssueComments
		fetchIssueReactions              fetchIssueReactions
		fetchIssueCommentReactions       fetchIssueCommentReactions
		fetchPullRequests                fetchPullRequests
		fetchPullRequestReviews          fetchPullRequestReviews
		fetchReviewComments              fetchReviewComments
		fetchAugmentedPullRequestThreads fetchAugmentedPullRequestThreads
		fetchAugmentedPullRequestReviews fetchAugmentedPullRequestReviews
		fetchAllCommitComments           fetchAllCommitComments
	}

	// fetchIssues is a function that returns a sequence of all issues in a repository.
	fetchIssues func(err *FetchErr) iter.Seq[*ogithub.Issue]

	// fetchIssueComments is a function that returns a sequence of all issue comments in an issue.
	fetchIssueComments func(number int, err *FetchErr) iter.Seq[*ogithub.IssueComment]

	// fetchIssueReactions is a function that returns a sequence of all reactions on an issue.
	fetchIssueReactions func(number int, err *FetchErr) iter.Seq[*ogithub.Reaction]

	// fetchPullRequests is a function that returns a sequence of all pull requests in a repository.
	fetchPullRequests func(err *FetchErr) iter.Seq[*ogithub.PullRequest]

	// fetchIssueCommentReactions is a function that returns a sequence of all reactions on an issue comment.
	fetchIssueCommentReactions func(id int64, err *FetchErr) iter.Seq[*ogithub.Reaction]

	// fetchPullRequestReviews is a function that returns a sequence of all pull request reviews in a pull request.
	fetchPullRequestReviews func(number int, err *FetchErr) iter.Seq[*ogithub.PullRequestReview]

	// fetchReviewComments is a function that returns a sequence of all pull request review comments in a pull request review.
	fetchReviewComments func(number int, id int64, err *FetchErr) iter.Seq[*ogithub.PullRequestComment]

	// fetchAllCommitComments is a function that returns a sequence of all commit comments for a repo.
	fetchAllCommitComments func(err *FetchErr) iter.Seq[*ogithub.RepositoryComment]

	// fetchAugmentedPullRequestThreads is a function that returns a sequence of all review threads in a pull request review.
	// Please, note that unlike other fetch functions, this one doesn't return an iterator, but a slice of review threads
	// as we only retry a small subset of the review thread data using the GraphQL API.
	fetchAugmentedPullRequestThreads func(number int) ([]*github.PullRequestReviewThread, error)

	// fetchAugmentedPullRequestReviews is a function that returns a sequence of all reviews in a pull request.
	// Please, note that unlike other fetch functions, this one doesn't return an iterator, but a slice of reviews
	// as we only retry a small subset of the review data using the GraphQL API.
	fetchAugmentedPullRequestReviews func(number int) (map[string]githubv4.DateTime, error)

	// FetchErr is a type that holds an error that occurred while fetching resources.
	FetchErr struct {
		mutex sync.Mutex
		err   error
	}
)

const defaultPerPage = 100

// NewResourceFetcher creates and returns an instance of ResourceFetcher.
func NewResourceFetcher(ctx context.Context, c *github.Client, owner, repo string) *ResourceFetcher {
	return &ResourceFetcher{
		c:                                c,
		owner:                            owner,
		repo:                             repo,
		fetchIssues:                      issuesIterBuilder(ctx, c, owner, repo),
		fetchIssueComments:               issueCommentsIterBuilder(ctx, c, owner, repo),
		fetchIssueReactions:              issueReactionsIterBuilder(ctx, c, owner, repo),
		fetchIssueCommentReactions:       issueCommentReactionsIterBuilder(ctx, c, owner, repo),
		fetchPullRequests:                pullRequestsIterBuilder(ctx, c, owner, repo),
		fetchPullRequestReviews:          pullRequestReviewsIterBuilder(ctx, c, owner, repo),
		fetchReviewComments:              pullRequestReviewCommentsIterBuilder(ctx, c, owner, repo),
		fetchAugmentedPullRequestThreads: pullRequestReviewThreadsBuilder(ctx, c, owner, repo),
		fetchAugmentedPullRequestReviews: pullRequestReviewsBuilder(ctx, c, owner, repo),
		fetchAllCommitComments:           commitCommentsIterBuilder(ctx, c, owner, repo),
	}
}

// All returns a sequence of all resources that are associated with the repository.
// This includes the repository, organization, mannequin, and issues.
//
// The sequence is lazily evaluated, so the caller must consume the entire sequence.
//
// If an error occurs while fetching resources, the error can be retrieved by calling the error() method.
func (r *ResourceFetcher) All() iter.Seq[*v1.Resource] {
	return func(yield func(*v1.Resource) bool) {
		// repo resources
		resources, err := r.repository()
		if err != nil {
			r.err = err
			return
		}
		for _, resource := range resources {
			if !yield(resource) {
				return
			}
		}

		// issue resources
		for resource := range r.issues() {
			if !yield(resource) {
				return
			}
		}
		if r.Error() != nil {
			return
		}

		// pull requests
		for resource := range r.pullRequests() {
			if !yield(resource) {
				return
			}
		}
		if r.Error() != nil {
			return
		}

		// commit comments
		for resource := range r.commitComments() {
			if !yield(resource) {
				return
			}
		}
	}
}

// InitOrg initializes the fetcher by fetching the repository and its owner and setting the org URL.
// Having this method is a bit hacky, let's revisit this post-alpha.
func (r *ResourceFetcher) InitOrg(ctx context.Context) (string, error) {
	// Fetch the repository
	repo, _, err := r.c.Repositories.Get(ctx, r.owner, r.repo)
	if err != nil {
		return "", fmt.Errorf("error fetching repository: %w", err)
	}

	// For now, only repositories that are owned by an organization are supported.
	if repo.GetOrganization() == nil {
		return "", fmt.Errorf("repository %s/%s has no organization", r.owner, r.repo)
	}

	// Set the organization URL
	r.org = repo.GetOrganization().GetHTMLURL()

	return r.org, nil
}

// Error returns the error that occurred while fetching resources, if any.
func (r *ResourceFetcher) Error() error {
	return r.err
}

// Repository returns a sequence of resources that represent the repository and its owner.
func (r *ResourceFetcher) repository() ([]*v1.Resource, error) {
	var resources []*v1.Resource

	// Fetch the repository
	repo, _, err := r.c.Repositories.Get(context.Background(), r.owner, r.repo)
	if err != nil {
		return resources, fmt.Errorf("error fetching repository: %w", err)
	}

	// For now, only repositories that are owned by an organization are supported.
	if repo.GetOrganization() == nil {
		return nil, fmt.Errorf("repository %s/%s has no organization", r.owner, r.repo)
	}

	// Set the organization URL
	r.org = repo.GetOrganization().GetHTMLURL()

	// Convert the repository and organization to v1.Resources
	o := googlegithub.Organization{Organization: *repo.GetOrganization()}
	convO, err := o.ToV1Organization()
	if err != nil {
		return nil, fmt.Errorf("error converting to v1.Organization: %w", err)
	}
	resources = append(resources, &v1.Resource{Resource: &v1.Resource_Organization{Organization: convO}})

	gr := googlegithub.Repository{Repository: *repo}
	convR, err := gr.ToV1Repository()
	if err != nil {
		return nil, fmt.Errorf("error converting to v1.RepositoryForThreadsQuery: %w", err)
	}
	resources = append(resources, &v1.Resource{Resource: &v1.Resource_Repository{Repository: convR}})

	return resources, nil
}

// batchIter returns a function that yields a batch of up to batchSize elements for each invocation of the iterator.
func batchIter[T any](i iter.Seq[T], batchSize int) iter.Seq[[]T] {
	return func(yield func([]T) bool) {
		var batch []T
		for r := range i {
			batch = append(batch, r)
			if len(batch) < batchSize {
				continue
			}
			if !yield(batch) {
				return
			}
			batch = nil
		}
		if len(batch) > 0 {
			yield(batch)
		}
	}
}

// Err returns the error that occurred while fetching resources, if any.
func (f *FetchErr) Err() error {
	f.mutex.Lock()
	defer f.mutex.Unlock()
	return f.err
}

// setErr sets the error that occurred while fetching resources.
func (f *FetchErr) setErr(err error) {
	f.mutex.Lock()
	defer f.mutex.Unlock()
	f.err = err
}
