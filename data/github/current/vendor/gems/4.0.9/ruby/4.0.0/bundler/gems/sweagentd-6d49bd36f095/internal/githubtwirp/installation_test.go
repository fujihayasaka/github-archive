package githubtwirp

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetInstallationInfo(t *testing.T) {
	ctx := context.Background()

	t.Run("returns installation info from API", func(t *testing.T) {
		noopClient := NewNoopClient()
		noopClient.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, req *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				InstallationId: 42,
				OwnerId:        200,
				OwnerLogin:     "my-owner",
				OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION,
				ClientId:       "client-123",
				RepoName:       "my-repo",
				IsGlobal:       false,
			}, nil
		}

		info, err := noopClient.GetInstallationInfo(ctx, 1, 100)
		require.NoError(t, err)
		assert.Equal(t, int64(100), info.ID)
		assert.Equal(t, "my-repo", info.Name)
		assert.Equal(t, int64(200), info.OwnerID)
		assert.Equal(t, "my-owner", info.OwnerLogin)
		assert.Equal(t, sweagentd.OwnerTypeOrganization, info.OwnerType)
		assert.Equal(t, "client-123", info.AppClientID)
		assert.Equal(t, int64(42), info.AppInstallationID)
		assert.False(t, info.AppIsGlobal)
	})

	t.Run("user owner type", func(t *testing.T) {
		noopClient := NewNoopClient()
		noopClient.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				InstallationId: 1,
				OwnerId:        400,
				OwnerLogin:     "some-user",
				OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_USER,
				ClientId:       "client-456",
				RepoName:       "user-repo",
			}, nil
		}

		info, err := noopClient.GetInstallationInfo(ctx, 1, 100)
		require.NoError(t, err)
		assert.Equal(t, sweagentd.OwnerTypeUser, info.OwnerType)
	})

	t.Run("API error propagates", func(t *testing.T) {
		noopClient := NewNoopClient()
		noopClient.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			return nil, assert.AnError
		}

		_, err := noopClient.GetInstallationInfo(ctx, 1, 100)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to get repository installation")
	})

	t.Run("caching via real Client", func(t *testing.T) {
		callCount := 0
		cacheStore := cache.NewMemoryCacheStore()
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		noopAPI := &NoopSweagentdAPI{}
		noopAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			callCount++
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				InstallationId: 1,
				OwnerId:        200,
				OwnerLogin:     "cached-owner",
				OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_USER,
				ClientId:       "client-789",
				RepoName:       "cached-repo",
				Permissions:    map[string]string{"contents": "write", "pull_requests": "write"},
			}, nil
		}

		client := &Client{
			obsv:         obsv,
			ffClient:     ffClient,
			cacheStore:   cacheStore,
			sweagentdAPI: noopAPI,
		}

		// First call should hit the API
		info, err := client.GetInstallationInfo(ctx, 1, 100)
		require.NoError(t, err)
		assert.Equal(t, "cached-repo", info.Name)
		assert.Equal(t, "write", info.Permissions["contents"])
		assert.Equal(t, 1, callCount)

		// Second call should use the cache and still have permissions populated.
		info, err = client.GetInstallationInfo(ctx, 1, 100)
		require.NoError(t, err)
		assert.Equal(t, "cached-repo", info.Name)
		assert.Equal(t, "write", info.Permissions["contents"], "permissions must survive the cache round-trip")
		assert.Equal(t, 1, callCount, "API should not be called again due to caching")
	})
}

func TestGetInstallationPermissions(t *testing.T) {
	ctx := context.Background()

	t.Run("returns permissions map from API", func(t *testing.T) {
		noopClient := NewNoopClient()
		noopClient.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, req *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			assert.Equal(t, int64(7), req.AgentId)
			assert.Equal(t, uint64(123), req.RepositoryId)
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				Permissions: map[string]string{"contents": "write", "issues": "read"},
			}, nil
		}

		perms, err := noopClient.GetInstallationPermissions(ctx, 7, 123)
		require.NoError(t, err)
		assert.Equal(t, "write", perms["contents"])
		assert.Equal(t, "read", perms["issues"])
	})

	t.Run("API error is wrapped", func(t *testing.T) {
		noopClient := NewNoopClient()
		noopClient.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			return nil, assert.AnError
		}

		_, err := noopClient.GetInstallationPermissions(ctx, 7, 123)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to get repository installation permissions")
	})

	t.Run("bypasses cache populated by GetInstallationInfo", func(t *testing.T) {
		// GetInstallationPermissions must not serve stale authorization data even when an
		// InstallationInfo entry already exists for the same (appID, repoID) key.
		cacheStore := cache.NewMemoryCacheStore()
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		infoCalls := 0
		permsCalls := 0
		currentPerms := map[string]string{"contents": "write"}

		noopAPI := &NoopSweagentdAPI{}
		noopAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			infoCalls++
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				InstallationId: 1,
				OwnerId:        200,
				OwnerLogin:     "owner",
				OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_USER,
				ClientId:       "client",
				RepoName:       "repo",
				Permissions:    currentPerms,
			}, nil
		}

		client := &Client{
			obsv:         obsv,
			ffClient:     ffClient,
			cacheStore:   cacheStore,
			sweagentdAPI: noopAPI,
		}

		// Seed the InstallationInfo cache.
		_, err := client.GetInstallationInfo(ctx, 1, 100)
		require.NoError(t, err)
		require.Equal(t, 1, infoCalls)

		// Swap the mock so we can verify GetInstallationPermissions ignores the cache.
		currentPerms = map[string]string{"contents": "read"}
		noopAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			permsCalls++
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				Permissions: currentPerms,
			}, nil
		}

		perms, err := client.GetInstallationPermissions(ctx, 1, 100)
		require.NoError(t, err)
		assert.Equal(t, "read", perms["contents"], "must return fresh perms, not cached write")
		assert.Equal(t, 1, permsCalls, "must hit the API rather than the cache")

		// And calling again should still hit the API every time.
		_, err = client.GetInstallationPermissions(ctx, 1, 100)
		require.NoError(t, err)
		assert.Equal(t, 2, permsCalls, "every call must bypass the cache")
	})
}
