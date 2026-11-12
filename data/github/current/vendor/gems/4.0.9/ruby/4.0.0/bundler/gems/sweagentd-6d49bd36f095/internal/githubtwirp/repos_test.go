package githubtwirp

import (
	"context"
	"testing"
	"time"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockRepositoriesAPI is a mock implementation of repositoriesTwirp.RepositoriesAPI
type mockRepositoriesAPI struct {
	callCount          int
	findByNameResponse *repositoriesTwirp.FindRepositoriesByNameResponse
	findByNameError    error
}

func (m *mockRepositoriesAPI) FindRepositoriesByName(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
	m.callCount++
	if m.findByNameError != nil {
		return nil, m.findByNameError
	}
	return m.findByNameResponse, nil
}

func (m *mockRepositoriesAPI) FindRepositories(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
	return nil, nil
}

func (m *mockRepositoriesAPI) FindRepositoryPermissions(ctx context.Context, req *repositoriesTwirp.FindRepositoryPermissionsRequest) (*repositoriesTwirp.FindRepositoryPermissionsResponse, error) {
	return nil, nil
}

func TestGetRepoByNameCaching(t *testing.T) {
	t.Run("caches GetRepoByName results", func(t *testing.T) {
		mockAPI := &mockRepositoriesAPI{
			findByNameResponse: &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         123,
						OwnerId:    456,
						OwnerLogin: "test-owner",
						Name:       "test-repo",
					},
				},
			},
		}

		cacheStore := cache.NewMemoryCacheStore()
		obsv := observability.NewNoopExporters()

		client := &Client{
			obsv:       obsv,
			cacheStore: cacheStore,
			reposAPI:   mockAPI,
		}

		ctx := context.Background()

		// First call should hit the mock
		repo1, err := client.GetRepoByName(ctx, "test-owner", "test-repo")
		require.NoError(t, err)
		assert.Equal(t, int64(123), repo1.GetId())
		assert.Equal(t, int64(456), repo1.GetOwnerId())
		assert.Equal(t, "test-owner", repo1.GetOwnerLogin())
		assert.Equal(t, "test-repo", repo1.GetName())
		assert.Equal(t, 1, mockAPI.callCount)

		// Second call should hit the cache
		repo2, err := client.GetRepoByName(ctx, "test-owner", "test-repo")
		require.NoError(t, err)
		assert.Equal(t, int64(123), repo2.GetId())
		assert.Equal(t, int64(456), repo2.GetOwnerId())
		assert.Equal(t, "test-owner", repo2.GetOwnerLogin())
		assert.Equal(t, "test-repo", repo2.GetName())
		assert.Equal(t, 1, mockAPI.callCount) // Still 1, cache hit
	})

	t.Run("cache key is case insensitive", func(t *testing.T) {
		mockAPI := &mockRepositoriesAPI{
			findByNameResponse: &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         123,
						OwnerId:    456,
						OwnerLogin: "Test-Owner",
						Name:       "Test-Repo",
					},
				},
			},
		}

		cacheStore := cache.NewMemoryCacheStore()
		obsv := observability.NewNoopExporters()

		client := &Client{
			obsv:       obsv,
			cacheStore: cacheStore,
			reposAPI:   mockAPI,
		}

		ctx := context.Background()

		// First call with specific casing
		repo1, err := client.GetRepoByName(ctx, "Test-Owner", "Test-Repo")
		require.NoError(t, err)
		assert.Equal(t, "Test-Owner", repo1.GetOwnerLogin())
		assert.Equal(t, "Test-Repo", repo1.GetName())
		assert.Equal(t, 1, mockAPI.callCount)

		// Second call with different casing should hit cache and return original casing
		repo2, err := client.GetRepoByName(ctx, "test-owner", "test-repo")
		require.NoError(t, err)
		assert.Equal(t, "Test-Owner", repo2.GetOwnerLogin()) // Should preserve original casing
		assert.Equal(t, "Test-Repo", repo2.GetName())        // Should preserve original casing
		assert.Equal(t, 1, mockAPI.callCount)                // Still 1, cache hit
	})

	t.Run("does not cache errors", func(t *testing.T) {
		mockAPI := &mockRepositoriesAPI{
			findByNameError: ErrRepoNotFound,
		}

		cacheStore := cache.NewMemoryCacheStore()
		obsv := observability.NewNoopExporters()

		client := &Client{
			obsv:       obsv,
			cacheStore: cacheStore,
			reposAPI:   mockAPI,
		}

		ctx := context.Background()

		// First call returns error
		_, err := client.GetRepoByName(ctx, "missing-owner", "missing-repo")
		require.Error(t, err)
		assert.Equal(t, 1, mockAPI.callCount)

		// Second call should also hit mock (error not cached)
		_, err = client.GetRepoByName(ctx, "missing-owner", "missing-repo")
		require.Error(t, err)
		assert.Equal(t, 2, mockAPI.callCount)
	})

	t.Run("does not cache when cache store is nil", func(t *testing.T) {
		mockAPI := &mockRepositoriesAPI{
			findByNameResponse: &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         123,
						OwnerId:    456,
						OwnerLogin: "test-owner",
						Name:       "test-repo",
					},
				},
			},
		}

		obsv := observability.NewNoopExporters()

		client := &Client{
			obsv:       obsv,
			cacheStore: nil, // No cache store
			reposAPI:   mockAPI,
		}

		ctx := context.Background()

		// First call
		_, err := client.GetRepoByName(ctx, "test-owner", "test-repo")
		require.NoError(t, err)
		assert.Equal(t, 1, mockAPI.callCount)

		// Second call should also hit mock (no cache store)
		_, err = client.GetRepoByName(ctx, "test-owner", "test-repo")
		require.NoError(t, err)
		assert.Equal(t, 2, mockAPI.callCount)
	})
}

func TestRepoCacheKey(t *testing.T) {
	t.Run("generates key with no-tenant when tenant ID is empty", func(t *testing.T) {
		ctx := context.Background()
		assert.Equal(t, "githubtwirp:repo:no-tenant:owner/repo", repoCacheKey(ctx, "owner", "repo"))
		assert.Equal(t, "githubtwirp:repo:no-tenant:owner/repo", repoCacheKey(ctx, "OWNER", "REPO"))
		assert.Equal(t, "githubtwirp:repo:no-tenant:my-org/my-repo", repoCacheKey(ctx, "My-Org", "My-Repo"))
	})

	t.Run("generates key with tenant ID when present", func(t *testing.T) {
		ctx := requestctx.NewContext(context.Background())
		err := requestctx.AddTenantID(ctx, "tenant-123")
		require.NoError(t, err)

		assert.Equal(t, "githubtwirp:repo:tenant-123:owner/repo", repoCacheKey(ctx, "owner", "repo"))
		assert.Equal(t, "githubtwirp:repo:tenant-123:owner/repo", repoCacheKey(ctx, "OWNER", "REPO"))
	})
}

func TestRepoCacheTTL(t *testing.T) {
	// Verify the TTL is set to a reasonable value (1 hour)
	assert.Equal(t, 60*time.Minute, repoCacheTTL)
}
