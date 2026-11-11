package githubtwirp

import (
	"context"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/stretchr/testify/require"
)

func TestNoopRepositoriesAPI_FindRepositoriesByName(t *testing.T) {
	noop := &NoopRepositoriesAPI{}

	ctx := context.Background()
	req := &repositoriesTwirp.FindRepositoriesByNameRequest{
		Nwos: []string{"test-owner/.github", "test-owner/regular-repo"},
	}

	resp, err := noop.FindRepositoriesByName(ctx, req)
	require.NoError(t, err)
	require.Len(t, resp.Repositories, 2) // Both .github and regular-repo should be returned

	// Check .github repo
	var githubRepo, regularRepo *repositoriesTwirp.RepositoryListItem
	for _, repo := range resp.Repositories {
		if repo.Name == ".github" {
			githubRepo = repo
		} else if repo.Name == "regular-repo" {
			regularRepo = repo
		}
	}

	require.NotNil(t, githubRepo)
	require.Equal(t, int64(2), githubRepo.Id)
	require.Equal(t, ".github", githubRepo.Name)
	require.Equal(t, "test-owner", githubRepo.OwnerLogin)

	require.NotNil(t, regularRepo)
	require.Equal(t, int64(1), regularRepo.Id)
	require.Equal(t, "regular-repo", regularRepo.Name)
	require.Equal(t, "test-owner", regularRepo.OwnerLogin)
}

func TestNewNoopClientWithMultipleRepositories(t *testing.T) {
	client := NewNoopClientWithMultipleRepositories()

	ctx := context.Background()
	req := &repositoriesTwirp.FindRepositoriesByNameRequest{
		Nwos: []string{"test-owner/.github"},
	}

	resp, err := client.RepositoriesAPI().FindRepositoriesByName(ctx, req)
	require.NoError(t, err)
	require.Len(t, resp.Repositories, 2) // Should return multiple repositories

	// Should return first repository with ID 100
	require.Equal(t, int64(100), resp.Repositories[0].Id)
	require.Equal(t, ".github", resp.Repositories[0].Name)

	// Should return second repository with ID 101
	require.Equal(t, int64(101), resp.Repositories[1].Id)
	require.Equal(t, ".github", resp.Repositories[1].Name)
}
