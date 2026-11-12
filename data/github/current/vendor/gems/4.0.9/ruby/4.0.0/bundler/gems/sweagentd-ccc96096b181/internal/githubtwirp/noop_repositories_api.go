package githubtwirp

import (
	"context"
	"fmt"
	"strings"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
)

type NoopRepositoriesAPI struct {
	repositoriesTwirp.RepositoriesAPI
	// ShouldReturnError controls whether FindRepositoriesByName returns an error
	ShouldReturnError bool
	// ShouldReturnMultiple controls whether to return multiple repositories for testing
	ShouldReturnMultiple bool
	// MockRepositoryResult outputs a specific response when FindRepositoriesByName is called
	MockRepositoryResult *repositoriesTwirp.FindRepositoriesByNameResponse
	// MockFindRepositoriesByName outputs a specific response when FindRepositoriesByName is called
	MockFindRepositoriesByName func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error)
	// MockFindRepositories outputs a specific response when FindRepositories is called
	MockFindRepositories func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error)
}

// Ensure NoopRepositoriesAPI implements RepositoriesAPI
var _ repositoriesTwirp.RepositoriesAPI = &NoopRepositoriesAPI{}

func (n *NoopRepositoriesAPI) FindRepositoriesByName(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
	// Handle nil receiver (when NoopClient is created manually without NoopRepositoriesAPI)
	if n == nil {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{},
		}, nil
	}

	if n.MockFindRepositoriesByName != nil {
		return n.MockFindRepositoriesByName(ctx, req)
	}

	if n.MockRepositoryResult != nil {
		return n.MockRepositoryResult, nil
	}

	// If configured to return error, return error for org repositories
	if n.ShouldReturnError {
		return nil, fmt.Errorf("simulated repository access error")
	}

	// If configured to return multiple repositories for testing
	if n.ShouldReturnMultiple {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{
					Id:         100,
					OwnerId:    200,
					Name:       ".github",
					OwnerLogin: "test-owner",
				},
				{
					Id:         101, // This should be ignored
					OwnerId:    200,
					Name:       ".github",
					OwnerLogin: "test-owner",
				},
			},
		}, nil
	}

	// Return repositories for requested repos to match test expectations
	var repositories []*repositoriesTwirp.RepositoryListItem

	for _, nwo := range req.Nwos {
		var repoID int64
		repoName := extractRepoName(nwo)
		ownerName := extractOwnerName(nwo)

		// Assign specific IDs that match test expectations
		if repoName == ".github" {
			repoID = 2 // This matches orgRepoID in most tests
		} else if repoName == ".github-private" {
			repoID = 3 // Use different ID for private org repo
		} else {
			// For non-org repositories, use a consistent ID based on repo name hash
			repoID = 1
		}

		repositories = append(repositories, &repositoriesTwirp.RepositoryListItem{
			Id:         repoID,
			OwnerId:    int64(456),
			Name:       repoName,
			OwnerLogin: ownerName,
			Status:     0, // STATUS_INVALID - first value in enum
			Visibility: 0, // VISIBILITY_INVALID - first value in enum
		})
	}

	return &repositoriesTwirp.FindRepositoriesByNameResponse{
		Repositories: repositories,
	}, nil
}

func (n *NoopRepositoriesAPI) FindRepositories(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
	// Handle nil receiver
	if n == nil {
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{},
		}, nil
	}

	// Use mock if provided
	if n.MockFindRepositories != nil {
		return n.MockFindRepositories(ctx, req)
	}

	var repositories []*repositoriesTwirp.RepositoryListItem

	for _, id := range req.Ids {
		// Create a simple repository item based on ID
		repositories = append(repositories, &repositoriesTwirp.RepositoryListItem{
			Id:         id,
			OwnerId:    int64(456),
			Name:       "test-repo",
			OwnerLogin: "test-owner",
			Status:     0,
			Visibility: 0,
		})
	}

	return &repositoriesTwirp.FindRepositoriesResponse{
		Repositories: repositories,
	}, nil
}

// Helper functions to extract owner and repo from "owner/repo" format
func extractOwnerName(nwo string) string {
	parts := strings.Split(nwo, "/")
	if len(parts) >= 1 {
		return parts[0]
	}
	return "unknown-owner"
}

func extractRepoName(nwo string) string {
	parts := strings.Split(nwo, "/")
	if len(parts) >= 2 {
		return parts[1]
	}
	return "unknown-repo"
}
