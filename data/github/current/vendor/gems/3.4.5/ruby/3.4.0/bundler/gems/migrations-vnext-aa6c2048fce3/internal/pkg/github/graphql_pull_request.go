package github

import (
	"context"
	"errors"
	"fmt"
	"math"

	"github.com/shurcooL/githubv4"
)

type (
	// PullRequestGraphQLAugmentService is an interface which describes the methods of the
	// PullRequestGraphQLAugmentService type. These methods are abstracted to an interface
	// so that we can implement a mock client and use it for unit testing.
	PullRequestGraphQLAugmentService interface {
		GetAugmentedPullRequestThreads(ctx context.Context, owner, repo string, number int) ([]*PullRequestReviewThread, error)
		GetAugmentedPullRequestReviews(ctx context.Context, owner, repo string, number int) ([]*PullRequestReview, error)
	}

	// PullRequestReviewThread represents a pull request review thread that is populated by the
	// GitHub GraphQL API to augment the data returned by the REST API.
	PullRequestReviewThread struct {
		ID         githubv4.ID
		ResolvedBy *struct {
			URL githubv4.URI
		}
		IsResolved bool
		IsOutdated bool
		Comments   struct {
			Nodes []struct {
				FullDatabaseID githubv4.String
			}
		} `graphql:"comments(first: 1)"`
	}

	// PullRequestReview represents a pull request review that is populated by the GitHub GraphQL API
	//  to augment the data returned by the REST API.
	PullRequestReview struct {
		FullDatabaseID githubv4.String
		CreatedAt      githubv4.DateTime
	}

	// PullRequestForThreadsQuery represents a GraphQL query to fetch data to augment the data
	// for pull requests threads.
	PullRequestForThreadsQuery struct {
		ReviewThreads struct {
			Nodes    []PullRequestReviewThread
			PageInfo struct {
				EndCursor   githubv4.String
				HasNextPage bool
			}
		} `graphql:"reviewThreads(first: 100, after: $reviewThreadsCursor)"`
	}

	// PullRequestForReviewsQuery represents a GraphQL query to fetch data to augment the data
	// for pull requests reviews.
	PullRequestForReviewsQuery struct {
		Reviews struct {
			Nodes    []PullRequestReview
			PageInfo struct {
				EndCursor   githubv4.String
				HasNextPage bool
			}
		} `graphql:"reviews(first: 100, after: $reviewsCursor)"`
	}

	// RepositoryForThreadsQuery represents a repository that is populated by the GitHub GraphQL API
	RepositoryForThreadsQuery struct {
		PullRequest PullRequestForThreadsQuery `graphql:"pullRequest(number: $pullNumber)"`
	}

	// ThreadQuery represents a GraphQL query for review threads
	ThreadQuery struct {
		Repository RepositoryForThreadsQuery `graphql:"repository(owner: $owner, name: $repo)"`
	}

	// RepositoryForReviewsQuery represents a repository that is populated by the GitHub GraphQL API
	RepositoryForReviewsQuery struct {
		PullRequest PullRequestForReviewsQuery `graphql:"pullRequest(number: $pullNumber)"`
	}

	// ReviewQuery represents a GraphQL query to augment the data for pull requests reviews.
	ReviewQuery struct {
		Repository RepositoryForReviewsQuery `graphql:"repository(owner: $owner, name: $repo)"`
	}

	// PullRequestThreadServiceImpl implements the PullRequestGraphQLAugmentService interface.
	PullRequestThreadServiceImpl struct {
		client *githubv4.Client
	}
)

// GetAugmentedPullRequestThreads returns all review threads for a given pull request to complement the data returned by the REST API.
func (p *PullRequestThreadServiceImpl) GetAugmentedPullRequestThreads(ctx context.Context, owner, repo string, number int) ([]*PullRequestReviewThread, error) {
	prNumber, err := safeCastToInt32(number)
	if err != nil {
		return nil, fmt.Errorf("failed to safely cast pull request number to int32: %w", err)
	}

	var q ThreadQuery
	variables := map[string]interface{}{
		"owner":               githubv4.String(owner),
		"repo":                githubv4.String(repo),
		"pullNumber":          githubv4.Int(prNumber),
		"reviewThreadsCursor": (*githubv4.String)(nil), // nil for the first page
	}

	var threads []*PullRequestReviewThread
	for {
		if err := p.client.Query(ctx, &q, variables); err != nil {
			return nil, fmt.Errorf("failed to query the GraphQL review thread objects: %w", err)
		}

		for _, thread := range q.Repository.PullRequest.ReviewThreads.Nodes {
			threads = append(threads, &thread)
		}

		if !q.Repository.PullRequest.ReviewThreads.PageInfo.HasNextPage {
			break
		}

		variables["reviewThreadsCursor"] = q.Repository.PullRequest.ReviewThreads.PageInfo.EndCursor
	}

	return threads, nil
}

// GetAugmentedPullRequestReviews returns all reviews for a given pull request to complement the data returned by the REST API.
func (p *PullRequestThreadServiceImpl) GetAugmentedPullRequestReviews(ctx context.Context, owner, repo string, number int) ([]*PullRequestReview, error) {
	prNumber, err := safeCastToInt32(number)
	if err != nil {
		return nil, fmt.Errorf("failed to safely cast pull request number to int32: %w", err)
	}

	var q ReviewQuery
	variables := map[string]interface{}{
		"owner":         githubv4.String(owner),
		"repo":          githubv4.String(repo),
		"pullNumber":    githubv4.Int(prNumber),
		"reviewsCursor": (*githubv4.String)(nil), // nil for the first page
	}

	var reviews []*PullRequestReview
	for {
		if err := p.client.Query(ctx, &q, variables); err != nil {
			return nil, fmt.Errorf("failed to query the GraphQL review objects: %w", err)
		}

		for _, review := range q.Repository.PullRequest.Reviews.Nodes {
			reviews = append(reviews, &review)
		}

		if !q.Repository.PullRequest.Reviews.PageInfo.HasNextPage {
			break
		}

		variables["reviewsCursor"] = q.Repository.PullRequest.Reviews.PageInfo.EndCursor
	}

	return reviews, nil
}

func safeCastToInt32(value int) (int32, error) {
	if value < math.MinInt32 || value > math.MaxInt32 {
		return 0, errors.New("value out of range for int32")
	}
	return int32(value), nil
}
