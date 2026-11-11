package gitrepo

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/stretchr/testify/require"
)

func TestTwirpRepoProvider(t *testing.T) {
	ctx := context.Background()

	t.Run("GetRepository success with single repository", func(t *testing.T) {
		// Create a mock client that returns a successful response
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: false,
			},
		}

		provider := NewTwirpRepoProvider(mockClient)

		repo, err := provider.GetRepository(ctx, "test-owner", ".github")
		require.NoError(t, err)
		require.NotNil(t, repo)

		// Verify the repository ID matches what our noop returns (ID 2 for .github)
		require.Equal(t, int64(2), repo.GetID())
	})

	t.Run("GetRepository returns repository for regular repos", func(t *testing.T) {
		// Create a mock client that returns repositories
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: false,
			},
		}

		provider := NewTwirpRepoProvider(mockClient)

		// Request a non-org repository - our noop now returns all requested repos
		repo, err := provider.GetRepository(ctx, "test-owner", "regular-repo")
		require.NoError(t, err)
		require.NotNil(t, repo)
		require.Equal(t, int64(1), repo.GetID())
	})

	t.Run("GetRepository propagates API errors", func(t *testing.T) {
		// Create a mock client that returns an error
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: true,
			},
		}

		provider := NewTwirpRepoProvider(mockClient)

		repo, err := provider.GetRepository(ctx, "test-owner", ".github")
		require.Error(t, err)
		require.Nil(t, repo)
	})

	t.Run("GetRepository handles nil client gracefully", func(t *testing.T) {
		// Test with nil NoopRepositoriesAPI (simulates manual client creation)
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: nil, // This causes our nil receiver handling to kick in
		}

		provider := NewTwirpRepoProvider(mockClient)

		repo, err := provider.GetRepository(ctx, "test-owner", ".github")
		require.Error(t, err)
		require.ErrorIs(t, err, ErrRepoNotFound) // Empty response = not found
		require.Nil(t, repo)
	})

	t.Run("GetRepository extracts correct repository from multiple results", func(t *testing.T) {
		// Create a noop client that returns multiple repositories (first should be used)
		mockClient := githubtwirp.NewNoopClientWithMultipleRepositories()

		provider := NewTwirpRepoProvider(mockClient)

		repo, err := provider.GetRepository(ctx, "test-owner", ".github")
		require.NoError(t, err)
		require.NotNil(t, repo)

		// Should use the first repository from the response
		require.Equal(t, int64(100), repo.GetID())
	})
}
