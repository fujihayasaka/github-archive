package aqueduct

import (
	"context"
	"testing"

	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/stretchr/testify/require"
)

func TestRetryLater(t *testing.T) {
	queue := &MockAqueductQueue{}
	client := &Client{
		Queue: queue,
	}

	_, err := client.RetryLater(context.Background(), TestJob{}, 0)
	require.NoError(t, err)
	require.Len(t, queue.enqueuedJobs, 1)
	require.Equal(t, map[string]string{RetryCountHeader: "0"}, queue.enqueuedJobs[0].Headers)

	_, err = client.RetryLater(context.Background(), TestJob{}, 1)
	require.NoError(t, err)
	require.Len(t, queue.enqueuedJobs, 2)
	require.Equal(t, map[string]string{RetryCountHeader: "1"}, queue.enqueuedJobs[1].Headers)

	_, err = client.RetryLater(context.Background(), TestJob{}, 2)
	require.NoError(t, err)
	require.Len(t, queue.enqueuedJobs, 3)
	require.Equal(t, map[string]string{RetryCountHeader: "2"}, queue.enqueuedJobs[2].Headers)
}

func TestTenant(t *testing.T) {
	queue := &MockAqueductQueue{}
	client := &Client{
		Queue: queue,
	}

	// No Tenant slug
	_, err := client.PerformLater(context.Background(), TestJob{})
	require.NoError(t, err)
	require.Len(t, queue.enqueuedJobs, 1)
	_, found := queue.enqueuedJobs[0].Headers[headers.Tenant]
	require.False(t, found)

	// With Tenant slug
	ctx := tenant.TenantContext(context.Background(), "avocado")
	_, err = client.PerformLater(ctx, TestJob{})

	require.NoError(t, err)
	require.Len(t, queue.enqueuedJobs, 2)
	require.Equal(t, queue.enqueuedJobs[1].Headers[headers.Tenant], "avocado")
	require.Equal(t, queue.enqueuedJobs[1].Headers[headers.TenantID], "")

	// With TenantID && Tenant slug
	ctx = tenant.TenantIDContext(ctx, "12345")
	_, err = client.PerformLater(ctx, TestJob{})

	require.NoError(t, err)
	require.Len(t, queue.enqueuedJobs, 3)
	require.Equal(t, queue.enqueuedJobs[2].Headers[headers.TenantID], "12345")
	require.Equal(t, queue.enqueuedJobs[1].Headers[headers.Tenant], "avocado")
}
