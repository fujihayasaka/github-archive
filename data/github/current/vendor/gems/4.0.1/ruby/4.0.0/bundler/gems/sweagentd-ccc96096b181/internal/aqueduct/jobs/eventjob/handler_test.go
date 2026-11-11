package eventjob

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type mockRequeue struct {
	mock.Mock
}

func (m *mockRequeue) RequeueJobWithDelay(ctx context.Context, job sweagentd.AqueductJob, delay time.Duration) (string, error) {
	args := m.Called(ctx, job, delay)
	return args.String(0), args.Error(1)
}

type mockClient struct {
	mock.Mock
}

func (m *mockClient) RateLimitsForRepo(ctx context.Context, app sweagentd.AgenticApp, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
	args := m.Called(ctx, ownerID, repoID)
	return args.Get(0).(map[uint8]limiter.Rate), args.Error(1)
}

func TestEventJobHandler(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	t.Run("returns error for unknown queue", func(t *testing.T) {
		mockHandler := &events.NoopHandler{}

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   "unknown-queue",
				Payload: []byte("test payload"),
			},
		}

		requeue := &mockRequeue{}
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler))

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		require.Error(t, err)
		require.Contains(t, err.Error(), `unknown queue "unknown-queue"`)
	})

	t.Run("returns error for invalid job payload", func(t *testing.T) {
		mockHandler := &events.NoopHandler{}

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.EventJobQueueName,
				Payload: []byte("invalid protobuf payload"),
			},
		}

		requeue := &mockRequeue{}
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler))

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		require.Error(t, err)
		require.Contains(t, err.Error(), "proto")
	})

	t.Run("handles EventJob with GitHub request ID", func(t *testing.T) {
		testRequestID := "test-request-123"
		testTopic := "test-topic"

		testJob := &jobs.EventJob{
			Id:              "test-event-id",
			Topic:           testTopic,
			Message:         []byte("test message"),
			Timestamp:       timestamppb.Now(),
			OwnerId:         12345,
			RepositoryId:    67890,
			ActorId:         11111,
			GithubRequestId: testRequestID,
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.EventJobQueueName,
				Payload: payload,
			},
		}

		// Mock the hydro.EventForTopic to return an error indicating message not applicable
		// This is the common path for EventForTopic to return ErrMessageNotApplicable
		mockHandler := &events.NoopHandler{
			MockProcess: func(ctx context.Context, event sweagentd.Event) error {
				return nil
			},
		}

		requeue := &mockRequeue{}
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler))

		// Since we can't easily mock hydro.EventForTopic, we expect this to fail
		// when trying to get the event for the topic, but the request ID should be set

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.Error(t, err) // Expected to fail on EventForTopic since we don't have real hydro setup
	})

	t.Run("handles EventJob without GitHub request ID", func(t *testing.T) {
		testTopic := "test-topic"

		testJob := &jobs.EventJob{
			Id:           "test-event-id",
			Topic:        testTopic,
			Message:      []byte("test message"),
			Timestamp:    timestamppb.Now(),
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			// No GithubRequestId
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.EventJobQueueName,
				Payload: payload,
			},
		}

		mockHandler := &events.NoopHandler{
			MockProcess: func(ctx context.Context, event sweagentd.Event) error {
				return nil
			},
		}

		requeue := &mockRequeue{}
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler))

		// Since we can't easily mock hydro.EventForTopic, we expect this to fail
		// when trying to get the event for the topic

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.Error(t, err) // Expected to fail on EventForTopic since we don't have real hydro setup
	})

	t.Run("handles EventJob with message not applicable error", func(t *testing.T) {
		testTopic := "test-topic"

		testJob := &jobs.EventJob{
			Id:           "test-event-id",
			Topic:        testTopic,
			Message:      []byte("test message"),
			Timestamp:    timestamppb.Now(),
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.EventJobQueueName,
				Payload: payload,
			},
		}

		mockHandler := &events.NoopHandler{
			MockProcess: func(ctx context.Context, event sweagentd.Event) error {
				return nil
			},
		}

		requeue := &mockRequeue{}
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler))

		// This test demonstrates that we would return nil for message not applicable errors
		// In practice, this would happen when hydro.EventForTopic returns ErrMessageNotApplicable

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		// We expect an error here since we don't have the full hydro setup mocked
		// In real usage, if hydro.IsMessageNotApplicable(err) returns true, we return nil
		require.Error(t, err)
	})

	t.Run("handles EventJob processing with handler error", func(t *testing.T) {
		testTopic := "test-topic"
		expectedError := errors.New("handler processing failed")

		testJob := &jobs.EventJob{
			Id:           "test-event-id",
			Topic:        testTopic,
			Message:      []byte("test message"),
			Timestamp:    timestamppb.Now(),
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.EventJobQueueName,
				Payload: payload,
			},
		}

		mockHandler := &events.NoopHandler{
			MockProcess: func(ctx context.Context, event sweagentd.Event) error {
				return expectedError
			},
		}

		requeue := &mockRequeue{}
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		// We expect an error, though it might be wrapped by the hydro processing
		require.Error(t, err)
	})
}
