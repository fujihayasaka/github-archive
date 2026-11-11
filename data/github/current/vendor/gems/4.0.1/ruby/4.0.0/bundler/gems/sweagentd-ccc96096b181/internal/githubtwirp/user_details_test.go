package githubtwirp

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestGetCopilotUserDetails_CacheBehavior(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("returns cached value on cache hit", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		cacheStore := cache.NewMemoryCacheStore()

		// Pre-populate the cache with user details
		userID := int64(12345)
		expectedDetails := &copilotUsersTwirp.CopilotUserDetails{
			Id:                  uint64(userID),
			AnalyticsTrackingId: "test-tracking-id",
		}
		marshaled, err := proto.Marshal(expectedDetails)
		require.NoError(t, err)
		cacheStore.Set(copilotUserDetailsCacheKey(userID), string(marshaled), copilotUserDetailsCacheTTL)

		// Create a client with the pre-populated cache
		validHMACKey := "test-hmac-key-16bytes"
		client, err := NewClient("https://unused.com", validHMACKey, "https://unused.com", validHMACKey, 1, "https://unused.com", validHMACKey, obsv, ffClient, cacheStore)
		require.NoError(t, err)

		// Create a context with requestctx data
		ctx := requestctx.NewContext(context.Background())

		// Call GetCopilotUserDetails - should return cached value without calling the API
		result, err := client.GetCopilotUserDetails(ctx, userID)
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, uint64(userID), result.Id)
		require.Equal(t, "test-tracking-id", result.AnalyticsTrackingId)
	})

	t.Run("memoizes cached value in context", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		cacheStore := cache.NewMemoryCacheStore()

		// Pre-populate the cache with user details
		userID := int64(12345)
		expectedDetails := &copilotUsersTwirp.CopilotUserDetails{
			Id:                  uint64(userID),
			AnalyticsTrackingId: "test-tracking-id",
		}
		marshaled, err := proto.Marshal(expectedDetails)
		require.NoError(t, err)
		cacheStore.Set(copilotUserDetailsCacheKey(userID), string(marshaled), copilotUserDetailsCacheTTL)

		// Create a client with the pre-populated cache
		validHMACKey := "test-hmac-key-16bytes"
		client, err := NewClient("https://unused.com", validHMACKey, "https://unused.com", validHMACKey, 1, "https://unused.com", validHMACKey, obsv, ffClient, cacheStore)
		require.NoError(t, err)

		// Create a context with requestctx data
		ctx := requestctx.NewContext(context.Background())

		// Verify context doesn't have user details yet
		_, ok := requestctx.CopilotUserDetails(ctx, userID)
		require.False(t, ok, "context should not have user details before call")

		// Call GetCopilotUserDetails
		_, err = client.GetCopilotUserDetails(ctx, userID)
		require.NoError(t, err)

		// Verify context now has user details memoized
		memoized, ok := requestctx.CopilotUserDetails(ctx, userID)
		require.True(t, ok, "context should have user details after call")
		require.Equal(t, uint64(userID), memoized.Id)
	})

	t.Run("returns context-memoized value without checking cache", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		cacheStore := cache.NewMemoryCacheStore()

		// Create a client with empty cache
		validHMACKey := "test-hmac-key-16bytes"
		client, err := NewClient("https://unused.com", validHMACKey, "https://unused.com", validHMACKey, 1, "https://unused.com", validHMACKey, obsv, ffClient, cacheStore)
		require.NoError(t, err)

		// Create a context with requestctx data and pre-populate it with user details
		ctx := requestctx.NewContext(context.Background())
		userID := int64(12345)
		expectedDetails := &copilotUsersTwirp.CopilotUserDetails{
			Id:                  uint64(userID),
			AnalyticsTrackingId: "context-memoized-id",
		}
		err = requestctx.AddCopilotUserDetails(ctx, userID, expectedDetails)
		require.NoError(t, err)

		// Call GetCopilotUserDetails - should return context-memoized value
		result, err := client.GetCopilotUserDetails(ctx, userID)
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, "context-memoized-id", result.AnalyticsTrackingId)
	})

	t.Run("skips invalid cached data and continues gracefully", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		cacheStore := cache.NewMemoryCacheStore()

		// Pre-populate the cache with invalid data
		userID := int64(12345)
		cacheStore.Set(copilotUserDetailsCacheKey(userID), "invalid-proto-data", copilotUserDetailsCacheTTL)

		// Create a client with the cache containing invalid data
		validHMACKey := "test-hmac-key-16bytes"
		client, err := NewClient("https://unused.com", validHMACKey, "https://unused.com", validHMACKey, 1, "https://unused.com", validHMACKey, obsv, ffClient, cacheStore)
		require.NoError(t, err)

		// Create a context with requestctx data
		ctx := requestctx.NewContext(context.Background())

		// Call GetCopilotUserDetails - should fail gracefully (attempt API call which will fail in test)
		// The important thing is it doesn't panic on invalid cache data
		_, err = client.GetCopilotUserDetails(ctx, userID)
		// We expect an error because the API call will fail (no real server), but not a panic
		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to get user details")
	})

	t.Run("cache key format is correct", func(t *testing.T) {
		userID := int64(12345)
		key := copilotUserDetailsCacheKey(userID)
		require.Equal(t, "copilot_user_details:12345", key)
	})
}
