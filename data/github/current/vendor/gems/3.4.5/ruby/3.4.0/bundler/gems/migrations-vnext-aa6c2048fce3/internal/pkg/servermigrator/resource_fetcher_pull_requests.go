package servermigrator

import (
	"context"
	"fmt"
	"iter"
	"strconv"
	"strings"

	"github.com/github/migrations-vnext/internal/pkg/adapters/googlegithub"
	"github.com/github/migrations-vnext/internal/pkg/github"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	ogithub "github.com/google/go-github/v65/github"
	"github.com/shurcooL/githubv4"
)

// pullRequests returns a sequence of resources that represent the pull requests in the repository along with their authors.
func (r *ResourceFetcher) pullRequests() iter.Seq[*v1.Resource] {
	return func(yield func(*v1.Resource) bool) {
		// fetchErr is used to propagate errors from the fetch functions that use iterators
		fetchErr := &FetchErr{}
		defer func() { r.err = fetchErr.Err() }()

		for pullRequest := range r.fetchPullRequests(fetchErr) {
			pr := googlegithub.PullRequest{PullRequest: *pullRequest}
			user := googlegithub.User{User: *pr.GetUser()}
			convU, err := user.ToV1Mannequin(r.org)
			if err != nil {
				r.err = fmt.Errorf("error converting pull_request author to User: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_Mannequin{Mannequin: convU}}) {
				return
			}

			convPr, err := pr.ToV1PullRequest()
			if err != nil {
				r.err = fmt.Errorf("error converting to v1.pull_request: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_PullRequest{PullRequest: convPr}}) {
				return
			}

			// pull request reactions (thumbs up, etc.) are just the same as issue reactions
			for reaction := range r.issueReactions(convPr.ResourceId, pr.GetNumber(), fetchErr) {
				if !yield(reaction) {
					return
				}
			}
			if fetchErr.Err() != nil {
				return
			}

			// pull request comments are just the same as issue comments
			for resource := range r.issueComments(pr.GetNumber(), fetchErr) {
				if !yield(resource) {
					return
				}
			}
			if fetchErr.Err() != nil {
				return
			}

			// pull request reviews
			for resource := range r.pullRequestReviews(pr.GetNumber(), fetchErr) {
				if !yield(resource) {
					return
				}
			}
			if fetchErr.Err() != nil {
				return
			}
		}
	}
}

// pullRequestReviews returns a sequence of resources that represent the reviews in the pull request.
func (r *ResourceFetcher) pullRequestReviews(number int, fetchErr *FetchErr) iter.Seq[*v1.Resource] {
	return func(yield func(*v1.Resource) bool) {
		// First fetch augmented reviews from the GraphQL API to get the review creation time
		createdByReview, err := r.fetchAugmentedPullRequestReviews(number)
		if err != nil {
			fetchErr.setErr(fmt.Errorf("error fetching augmented pull request reviews: %w", err))
			return
		}

		// Then fetch the reviews from the REST API
		for review := range r.fetchPullRequestReviews(number, fetchErr) {
			// Neither the import API nor Octoshift support pending pull request reviews
			if strings.ToLower(review.GetState()) == "pending" {
				continue
			}

			i := googlegithub.PullRequestReview{
				Review:             *review,
				AugmentedCreatedAt: createdByReview[strconv.FormatInt(review.GetID(), 10)],
			}

			user := googlegithub.User{User: *i.Review.GetUser()}
			convU, err := user.ToV1Mannequin(r.org)
			if err != nil {
				r.err = fmt.Errorf("error converting pull_request_review author to User: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_Mannequin{Mannequin: convU}}) {
				return
			}

			for comment := range r.fetchReviewComments(number, review.GetID(), fetchErr) {
				i.Comments = append(i.Comments, comment)
			}
			if fetchErr.Err() != nil {
				return
			}

			threads, err := r.fetchAugmentedPullRequestThreads(number)
			if err != nil {
				fetchErr.setErr(fmt.Errorf("error fetching review threads: %w", err))
				return
			}
			i.AugmentedThreads = threads

			conv, err := i.ToV1PullRequestReview()
			if err != nil {
				r.err = fmt.Errorf("error converting to v1.pull_request_review: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_PullRequestReview{PullRequestReview: conv}}) {
				return
			}
		}
	}
}

// pullRequestsIterBuilder returns a function that builds an iterator for fetching all pullRequests in a repository using the given GitHub client.
func pullRequestsIterBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchPullRequests {
	return func(fetchErr *FetchErr) iter.Seq[*ogithub.PullRequest] {
		scanner := NewScanner[*ogithub.PullRequest](c, defaultPerPage)
		defer func() { fetchErr.setErr(scanner.Err()) }()
		return scanner.All(func(c *github.Client, listOptions ogithub.ListOptions) ([]*ogithub.PullRequest, *ogithub.Response, error) {
			opts := &ogithub.PullRequestListOptions{
				Direction:   "asc",
				ListOptions: listOptions,
				Sort:        "created",
				State:       "all",
			}
			rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
			return c.PullRequests.List(rlCtx, owner, repo, opts)
		})
	}
}

// pullRequestReviewsIterBuilder returns a function that builds an iterator for fetching all pull request reviews in a pull request using the given GitHub client.
func pullRequestReviewsIterBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchPullRequestReviews {
	return func(number int, fetchErr *FetchErr) iter.Seq[*ogithub.PullRequestReview] {
		scanner := NewScanner[*ogithub.PullRequestReview](c, defaultPerPage)
		defer func() { fetchErr.setErr(scanner.Err()) }()
		return scanner.All(func(c *github.Client, listOptions ogithub.ListOptions) ([]*ogithub.PullRequestReview, *ogithub.Response, error) {
			rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
			return c.PullRequests.ListReviews(rlCtx, owner, repo, number, &listOptions)
		})
	}
}

// pullRequestReviewCommentsIterBuilder returns a function that builds an iterator for fetching all pull request review comments in a pull request using the given GitHub client.
func pullRequestReviewCommentsIterBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchReviewComments {
	return func(number int, id int64, fetchErr *FetchErr) iter.Seq[*ogithub.PullRequestComment] {
		scanner := NewScanner[*ogithub.PullRequestComment](c, defaultPerPage)
		defer func() { fetchErr.setErr(scanner.Err()) }()

		rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)

		commentList := scanner.All(func(c *github.Client, listOptions ogithub.ListOptions) ([]*ogithub.PullRequestComment, *ogithub.Response, error) {
			return c.PullRequests.ListReviewComments(rlCtx, owner, repo, number, id, &listOptions)
		})

		return func(yield func(*ogithub.PullRequestComment) bool) {
			for comment := range commentList {
				fullComment, _, err := c.PullRequests.GetComment(rlCtx, owner, repo, comment.GetID())
				if err != nil {
					fetchErr.setErr(fmt.Errorf("error fetching pull request comment: %w", err))
					return
				}
				if !yield(fullComment) {
					return
				}
			}
		}
	}
}

// pullRequestReviewThreadsBuilder returns a function that builds a function to fetch
// all review threads in a pull request using the given GitHub client.
func pullRequestReviewThreadsBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchAugmentedPullRequestThreads {
	return func(number int) ([]*github.PullRequestReviewThread, error) {
		rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
		threads, err := c.PullRequestReviewThread.GetAugmentedPullRequestThreads(rlCtx, owner, repo, number)
		if err != nil {
			return nil, err
		}
		return threads, nil
	}
}

// pullRequestReviewsBuilder returns a function that builds a function to fetch
// all augmented reviews in a pull request using the given GitHub client.
func pullRequestReviewsBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchAugmentedPullRequestReviews {
	return func(number int) (map[string]githubv4.DateTime, error) {
		rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
		reviews, err := c.PullRequestReviewThread.GetAugmentedPullRequestReviews(rlCtx, owner, repo, number)
		if err != nil {
			return nil, err
		}
		m := make(map[string]githubv4.DateTime, len(reviews))
		for _, review := range reviews {
			m[string(review.FullDatabaseID)] = review.CreatedAt
		}
		return m, nil
	}
}
