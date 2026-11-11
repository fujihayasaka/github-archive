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

	t.Run("handles unknown queue gracefully", func(t *testing.T) {
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
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		// Outer handler swallows the error to prevent Aqueduct NACK
		require.NoError(t, err)
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
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		// The outer handler swallows the error to prevent Aqueduct NACK
		require.NoError(t, err)
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
		requeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, jobs.TransientErrorRequeueDelay).Return("new-job-id", nil)
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler), nil)

		// Since we can't easily mock hydro.EventForTopic, it fails,
		// but the outer handler catches the error and requeues instead of NACKing

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err) // Error swallowed by outer handler
		requeue.AssertExpectations(t)
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
		requeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, jobs.TransientErrorRequeueDelay).Return("new-job-id", nil)
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err) // Error swallowed by outer handler
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
		requeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, jobs.TransientErrorRequeueDelay).Return("new-job-id", nil)
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		// Outer handler swallows errors — EventForTopic failure is handled as transient
		require.NoError(t, err)
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
		requeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, jobs.TransientErrorRequeueDelay).Return("new-job-id", nil)
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, ffClient, requeue, limiter, agenticapptest.NewTestProvider(t), mockHandler), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		// Outer handler catches the error and requeues
		require.NoError(t, err)
	})

	t.Run("resolves and sets agent slug when app provider is configured", func(t *testing.T) {
		const testAgentID = int64(12345)
		testJob := &jobs.EventJob{
			Id:           "test-event-id",
			Topic:        "test-topic",
			Message:      []byte("test message"),
			Timestamp:    timestamppb.Now(),
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			AgentId:      testAgentID,
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

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentEmitAgentSlugTelemetry: true,
		})
		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		requeue := &mockRequeue{}
		limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), appProvider)
		handler := Handler(obsv, ffClient, requeue, limiter, appProvider, &events.NoopHandler{})

		ctx := requestctx.NewContext(context.Background())
		ctx, err = handler(ctx, receiveResult)
		require.Error(t, err)

		agent, ok := requestctx.Agent(ctx)
		require.True(t, ok)
		require.Equal(t, testAgentID, agent.ID)
		require.Equal(t, "copilot", agent.Slug)
	})
}
