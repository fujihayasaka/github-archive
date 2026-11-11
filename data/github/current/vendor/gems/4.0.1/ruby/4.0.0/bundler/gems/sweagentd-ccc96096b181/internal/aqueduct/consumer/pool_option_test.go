package consumer

import (
	"context"
	"testing"
	"time"

	aq "github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

const (
	TestAppName       string = "test-app"
	TestAqueductURL   string = "aqueduct-lite:18081"
	TestAPIKey        string = "test-api-key"
	TestAPIKeyVersion int    = 123
)

func getTestClient() sweagentd.AqueductClient {
	ac, _ := aqueduct.NewClient(
		context.Background(),
		observability.NewNoopExporters(),
		TestAppName,
		aqueduct.WithAqueductURL(TestAqueductURL),
		aqueduct.WithAPIKey(TestAPIKey),
		aqueduct.WithAPIKeyVersion(TestAPIKeyVersion),
	)
	return ac
}

func mockBeforeReceive() aq.BeforeReceiveHook {
	return func(ctx context.Context) (context.Context, error) {
		return ctx, nil
	}
}

func mockHandler() aq.JobHandler {
	return func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
		return ctx, nil
	}
}

func mockErrorHook() aq.ErrorHook {
	return func(worker *aq.Worker, ctx context.Context, err error) {
		// No-op for testing
	}
}

func TestPoolOptions(t *testing.T) {
	obsv := observability.NewNoopExporters()
	client := getTestClient()
	ctx := context.Background()
	pool, err := NewWorkerPool(
		ctx,
		obsv,
		client,
		WithWorkerCount(2),
		WithHeartbeatInterval(30*time.Second),
		WithHeartbeatTimeout(60*time.Second),
		WithQueues([]string{"test"}),
		WithPoolName("test-pool"),
		WithHandler(mockHandler()),
		WithBeforeReceiveHook(mockBeforeReceive()),
		WithErrorHook(mockErrorHook()),
	)
	require.NoError(t, err)
	require.NotEmpty(t, pool)
}
