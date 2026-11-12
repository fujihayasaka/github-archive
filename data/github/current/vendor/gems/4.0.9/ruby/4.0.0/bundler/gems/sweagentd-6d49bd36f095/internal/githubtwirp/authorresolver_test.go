package githubtwirp

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func TestAuthorResolver_Resolve_CacheHit(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ghTwirp := NewNoopClient()
	ffClient := featureflags.NewNoopClient(make(map[string]bool))

	resolver := NewAuthorResolver(obsv, ghTwirp, ffClient)

	// Pre-populate cache
	resolver.cache[12345] = "Cached Display Name"

	// Should return cached value without calling the API
	result, err := resolver.Resolve(ctx, 12345, "testuser")

	require.NoError(t, err)
	require.Equal(t, "Cached Display Name", result)
}

func TestAuthorResolver_Resolve_CacheMiss_Success(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()
	ghTwirp := NewNoopClient()

	// Mock the ResolveUserIDToDisplayLogin call to return a specific display login
	ghTwirp.NoopSweagentdAPI.MockResolveUserIDToDisplayLogin = func(ctx context.Context, req *sweagentdTwirp.ResolveUserIDToDisplayLoginRequest) (*sweagentdTwirp.ResolveUserIDToDisplayLoginResponse, error) {
		require.Equal(t, uint64(12345), req.UserId)
		return &sweagentdTwirp.ResolveUserIDToDisplayLoginResponse{
			DisplayLogin: "Resolved Display Name",
		}, nil
	}

	resolver := NewAuthorResolver(obsv, ghTwirp, featureflags.NewNoopClient(make(map[string]bool)))

	result, err := resolver.Resolve(ctx, 12345, "testuser")

	require.NoError(t, err)
	require.Equal(t, "Resolved Display Name", result)

	// Verify the result is cached
	require.Equal(t, "Resolved Display Name", resolver.cache[12345])
}

func TestAuthorResolver_Resolve_CacheMiss_Error(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()
	ghTwirp := NewNoopClient()

	// Mock the ResolveUserIDToDisplayLogin call to return an error
	expectedError := errors.New("API error")
	ghTwirp.NoopSweagentdAPI.MockResolveUserIDToDisplayLogin = func(ctx context.Context, req *sweagentdTwirp.ResolveUserIDToDisplayLoginRequest) (*sweagentdTwirp.ResolveUserIDToDisplayLoginResponse, error) {
		return nil, expectedError
	}

	resolver := NewAuthorResolver(obsv, ghTwirp, featureflags.NewNoopClient(make(map[string]bool)))

	result, err := resolver.Resolve(ctx, 12345, "testuser")

	require.Error(t, err)
	require.Equal(t, "", result)
	require.Contains(t, err.Error(), "failed to resolve user ID to display login")

	// Verify nothing is cached on error
	_, exists := resolver.cache[12345]
	require.False(t, exists)
}

func TestAuthorResolver_Resolve_MultipleCalls_CacheEffectiveness(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()
	ghTwirp := NewNoopClient()

	callCount := 0
	ghTwirp.NoopSweagentdAPI.MockResolveUserIDToDisplayLogin = func(ctx context.Context, req *sweagentdTwirp.ResolveUserIDToDisplayLoginRequest) (*sweagentdTwirp.ResolveUserIDToDisplayLoginResponse, error) {
		callCount++
		return &sweagentdTwirp.ResolveUserIDToDisplayLoginResponse{
			DisplayLogin: "Resolved Display Name",
		}, nil
	}

	resolver := NewAuthorResolver(obsv, ghTwirp, featureflags.NewNoopClient(make(map[string]bool)))

	// First call should hit the API
	result1, err := resolver.Resolve(ctx, 12345, "testuser")
	require.NoError(t, err)
	require.Equal(t, "Resolved Display Name", result1)
	require.Equal(t, 1, callCount)

	// Second call should use cache
	result2, err := resolver.Resolve(ctx, 12345, "testuser")
	require.NoError(t, err)
	require.Equal(t, "Resolved Display Name", result2)
	require.Equal(t, 1, callCount) // Should still be 1, not 2

	// Different user should hit the API again
	result3, err := resolver.Resolve(ctx, 67890, "anotheruser")
	require.NoError(t, err)
	require.Equal(t, "Resolved Display Name", result3)
	require.Equal(t, 2, callCount) // Should now be 2
}

func TestAuthorResolver_Resolve_DifferentUsersWithSameLogin(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()
	ghTwirp := NewNoopClient()

	callCount := 0
	ghTwirp.NoopSweagentdAPI.MockResolveUserIDToDisplayLogin = func(ctx context.Context, req *sweagentdTwirp.ResolveUserIDToDisplayLoginRequest) (*sweagentdTwirp.ResolveUserIDToDisplayLoginResponse, error) {
		callCount++
		return &sweagentdTwirp.ResolveUserIDToDisplayLoginResponse{
			DisplayLogin: "Display Name " + string(rune(req.UserId)),
		}, nil
	}

	resolver := NewAuthorResolver(obsv, ghTwirp, featureflags.NewNoopClient(make(map[string]bool)))

	// First call with user ID 12345
	result1, err := resolver.Resolve(ctx, 12345, "sharedlogin")
	require.NoError(t, err)
	require.Equal(t, 1, callCount)

	// Second call with different user ID but same login should NOT use cache
	// Note: The cache is keyed by user ID, not login, so this demonstrates
	// the current cache behavior. In a real system, you might want to
	// consider if this is the desired behavior.
	result2, err := resolver.Resolve(ctx, 67890, "sharedlogin")
	require.NoError(t, err)
	require.NotEqual(t, result1, result2)
	require.Equal(t, "Display Name "+string(rune(12345)), result1)
	require.Equal(t, "Display Name "+string(rune(67890)), result2)
	require.Equal(t, 2, callCount)
}
