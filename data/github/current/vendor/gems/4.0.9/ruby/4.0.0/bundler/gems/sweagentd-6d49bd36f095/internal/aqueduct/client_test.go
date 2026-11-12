package aqueduct

import (
	"context"
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	TestAppName       string = "test-app"
	TestAqueductURL   string = "aqueduct-lite:18081"
	TestAPIKey        string = "test-api-key"
	TestAPIKeyVersion int    = 123
)

func TestClientConfiguration(t *testing.T) {
	ctx := context.Background()
	ac, err := NewClient(
		ctx,
		observability.NewNoopExporters(),
		TestAppName,
		WithAqueductURL(TestAqueductURL),
		WithAPIKey(TestAPIKey),
		WithAPIKeyVersion(TestAPIKeyVersion),
	)
	require.NoError(t, err)
	require.NotEmpty(t, ac)
	assert.Equal(t, TestAppName, ac.AppName())
	assert.Equal(t, TestAqueductURL, ac.AqueductURL())

	assert.Equal(t, TestAPIKey, ac.getAPIKey())
	assert.Equal(t, TestAPIKeyVersion, ac.getAPIKeyVersion())
}

func TestQueueDepth_ReportsCurrentDepth(t *testing.T) {
	ctx := context.Background()
	mc := NewMemoryClient(observability.NewNoopExporters())

	depth, err := mc.QueueDepth(ctx, "agent-job-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(0), depth, "empty queue must report depth 0")

	for range 3 {
		_, err := mc.InternalClient().Send(ctx, aqueduct.Job{
			App:       mc.AppName(),
			Queue:     "agent-job-queue",
			DeliverAt: time.Now(),
		})
		require.NoError(t, err)
	}

	depth, err = mc.QueueDepth(ctx, "agent-job-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(3), depth, "depth tracks number of pending jobs in the queue")

	otherDepth, err := mc.QueueDepth(ctx, "other-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(0), otherDepth, "depth is scoped per queue name")
}

func TestQueueDepth_UsesCacheWhenConfigured(t *testing.T) {
	ctx := context.Background()
	store := cache.NewMemoryCacheStore()
	mc := NewMemoryClient(observability.NewNoopExporters())
	WithQueueDepthCache(store, time.Minute)(&mc.Client)

	// Seed three jobs and prime the cache.
	for range 3 {
		_, err := mc.InternalClient().Send(ctx, aqueduct.Job{
			App:       mc.AppName(),
			Queue:     "agent-job-queue",
			DeliverAt: time.Now(),
		})
		require.NoError(t, err)
	}
	depth, err := mc.QueueDepth(ctx, "agent-job-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(3), depth)

	// Enqueue more jobs — the cached value must persist within the TTL.
	for range 5 {
		_, err := mc.InternalClient().Send(ctx, aqueduct.Job{
			App:       mc.AppName(),
			Queue:     "agent-job-queue",
			DeliverAt: time.Now(),
		})
		require.NoError(t, err)
	}
	depthAgain, err := mc.QueueDepth(ctx, "agent-job-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(3), depthAgain, "cached read must return the prior value within TTL, not the fresh upstream count")
}

func TestQueueDepth_BypassesCacheWhenTTLIsZero(t *testing.T) {
	ctx := context.Background()
	store := cache.NewMemoryCacheStore()
	mc := NewMemoryClient(observability.NewNoopExporters())
	WithQueueDepthCache(store, 0)(&mc.Client) // zero TTL == disabled

	for range 2 {
		_, err := mc.InternalClient().Send(ctx, aqueduct.Job{
			App:       mc.AppName(),
			Queue:     "agent-job-queue",
			DeliverAt: time.Now(),
		})
		require.NoError(t, err)
	}
	depth, err := mc.QueueDepth(ctx, "agent-job-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(2), depth)

	// Add one more — uncached reads should reflect the live count immediately.
	_, err = mc.InternalClient().Send(ctx, aqueduct.Job{
		App:       mc.AppName(),
		Queue:     "agent-job-queue",
		DeliverAt: time.Now(),
	})
	require.NoError(t, err)

	depth, err = mc.QueueDepth(ctx, "agent-job-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(3), depth, "TTL <= 0 should leave caching disabled")
}

// queueDepthInterfaceHolder lets us call QueueDepth via the sweagentd.AqueductClient
// interface so the test asserts that interface dispatch still hits the cached path.
type queueDepthInterfaceHolder struct {
	c sweagentd.AqueductClient
}

func TestQueueDepth_CachingWorksThroughAqueductClientInterface(t *testing.T) {
	ctx := context.Background()
	store := cache.NewMemoryCacheStore()
	mc := NewMemoryClient(observability.NewNoopExporters())
	WithQueueDepthCache(store, time.Minute)(&mc.Client)

	// Hold the client behind the interface — exactly how a consumer like the
	// upcoming QueueDepthHook would depend on it.
	holder := queueDepthInterfaceHolder{c: mc}

	for range 4 {
		_, err := mc.InternalClient().Send(ctx, aqueduct.Job{
			App:       mc.AppName(),
			Queue:     "agent-job-queue",
			DeliverAt: time.Now(),
		})
		require.NoError(t, err)
	}

	depth, err := holder.c.QueueDepth(ctx, "agent-job-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(4), depth)

	// Enqueue more — the interface-dispatched call must hit the same cached
	// state on the underlying *Client and keep returning the original value.
	for range 6 {
		_, err := mc.InternalClient().Send(ctx, aqueduct.Job{
			App:       mc.AppName(),
			Queue:     "agent-job-queue",
			DeliverAt: time.Now(),
		})
		require.NoError(t, err)
	}
	depthAgain, err := holder.c.QueueDepth(ctx, "agent-job-queue")
	require.NoError(t, err)
	assert.Equal(t, int64(4), depthAgain,
		"cache must apply equally when called through the sweagentd.AqueductClient interface")
}
