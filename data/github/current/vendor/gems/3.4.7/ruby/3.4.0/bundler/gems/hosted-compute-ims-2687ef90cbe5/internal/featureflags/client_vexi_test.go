package featureflags

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestNewVexiClient_FFLite_ShouldImmediatelyHydrated(t *testing.T) {
	ctx := context.Background()
	cfg := &Config{VexiFFLiteUrl: "http://localhost:8090"} // must define a way to indicate dev mode
	client, err := newVexiClient(ctx, cfg, "dotcom")
	require.NoError(t, err, "expected dev-mode client creation to succeed")

	// Since dev mode uses a direct adapter, the wait group should be done
	require.True(t, client.featuresHydrated, "dev mode should skip asynchronous loading")
}

func TestVexiClient_ReturnsFalseToNilActor(t *testing.T) {
	ctx := context.Background()
	cfg := &Config{VexiFFLiteUrl: "http://localhost:8090"} // must define a way to indicate dev mode
	client, err := newVexiClient(ctx, cfg, "dotcom")
	require.NoError(t, err, "expected production client creation to succeed")

	// Since dev mode uses a direct adapter, the wait group should be done
	require.False(t, client.IsFeatureFlagEnabledForActor(ctx, "test", nil), "should return false for nil actor")
}

func TestNewVexiClient_Hydro_ShouldContinueIfHydrationExceedsTimeout(t *testing.T) {
	ctx := context.Background()
	cfg := &Config{
		VexiHydroBrokers:        "dummy.localhost",
		VexiHydroInitTimeoutSec: 0.1,
	}
	client, err := newVexiClient(ctx, cfg, "dotcom")
	require.NoError(t, err, "expected production client creation to succeed")

	waitForHydrate := make(chan struct{})
	go func() {
		waitForFlagHydrationIfNeeded(ctx, client)
		waitForHydrate <- struct{}{}
	}()

	select {
	case <-waitForHydrate:
		require.True(t, client.initializeSuccess, "should not have succeeded")
		require.True(t, client.waitExpired, "should expire if not hydrated")
		require.False(t, client.featuresHydrated, "should be hydrated")
	case <-time.After(5 * time.Second):
		t.Error("should hydration timeout to be honoured")
	}
}

func TestNewVexiClient_Hydro_FFCheckShouldWaitForHydrationOrTimeout(t *testing.T) {
	ctx := context.Background()
	cfg := &Config{
		VexiHydroBrokers:        "dummy.localhost",
		VexiHydroInitTimeoutSec: 0.1,
	}
	client, err := newVexiClient(ctx, cfg, "dotcom")
	require.NoError(t, err, "expected production client creation to succeed")

	checkResult := make(chan bool)
	go func() {
		checkResult <- client.IsFeatureFlagEnabledGlobally(ctx, "test")
	}()

	select {
	case result := <-checkResult:
		require.False(t, result, "should return default value if not hydrated")
	case <-time.After(5 * time.Second):
		t.Error("hydro setup should have timeout and flag returned default value")
	}
}

func TestWaitForFlagHydrationIfNeeded_AlreadyHydrated(t *testing.T) {
	ctx := context.Background()
	client := &vexiClient{featuresHydrated: true}
	waitForFlagHydrationIfNeeded(ctx, client)
	// If features are already hydrated, we don't block
	require.False(t, client.waitExpired, "should not expire if already hydrated")
}
