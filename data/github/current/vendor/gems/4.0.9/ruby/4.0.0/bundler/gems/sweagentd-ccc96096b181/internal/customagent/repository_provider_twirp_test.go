package customagent

import (
	"context"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestTwirpRepoProvider(t *testing.T) {
	ctx := context.Background()

	t.Run("getRepository success with single repository", func(t *testing.T) {
		// Create a mock client that returns a successful response
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: false,
			},
		}

		provider := newTwirpRepoProvider(mockClient)

		repo, err := provider.getRepository(ctx, "test-owner", ".github")
		require.NoError(t, err)
		require.NotNil(t, repo)

		// Verify the repository ID matches what our noop returns (ID 2 for .github)
		require.Equal(t, int64(2), repo.GetID())
	})

	t.Run("getRepository returns repository for regular repos", func(t *testing.T) {
		// Create a mock client that returns repositories
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: false,
			},
		}

		provider := newTwirpRepoProvider(mockClient)

		// Request a non-org repository - our noop now returns all requested repos
		repo, err := provider.getRepository(ctx, "test-owner", "regular-repo")
		require.NoError(t, err)
		require.NotNil(t, repo)
		require.Equal(t, int64(1), repo.GetID())
	})

	t.Run("getRepository propagates API errors", func(t *testing.T) {
		// Create a mock client that returns an error
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: true,
			},
		}

		provider := newTwirpRepoProvider(mockClient)

		repo, err := provider.getRepository(ctx, "test-owner", ".github")
		require.Error(t, err)
		require.Nil(t, repo)
	})

	t.Run("getRepository handles nil client gracefully", func(t *testing.T) {
		// Test with nil NoopRepositoriesAPI (simulates manual client creation)
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: nil, // This causes our nil receiver handling to kick in
		}

		provider := newTwirpRepoProvider(mockClient)

		repo, err := provider.getRepository(ctx, "test-owner", ".github")
		require.Error(t, err)
		require.ErrorIs(t, err, ErrRepoNotFound) // Empty response = not found
		require.Nil(t, repo)
	})

	t.Run("getRepository extracts correct repository from multiple results", func(t *testing.T) {
		// Create a noop client that returns multiple repositories (first should be used)
		mockClient := githubtwirp.NewNoopClientWithMultipleRepositories()

		provider := newTwirpRepoProvider(mockClient)

		repo, err := provider.getRepository(ctx, "test-owner", ".github")
		require.NoError(t, err)
		require.NotNil(t, repo)

		// Should use the first repository from the response
		require.Equal(t, int64(100), repo.GetID())
	})
}

func TestTwirpRepoProviderIntegration(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"

	t.Run("twirpRepoProvider error handling in service context", func(t *testing.T) {
		// Test that errors from twirpRepoProvider are handled correctly by the service
		spokes := makeSpokesWithAgents(t, map[string]string{
			"repo-agent": `---
name: Repo Agent
---
Content.`,
		})

		// Use error-returning noop client to simulate twirp failures
		ghtwirp := githubtwirp.NewNoopClientWithRepositoryError()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return nil, twirp.InternalError("some unexpected error")
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.Error(t, err)
		require.Nil(t, result)
	})
}
