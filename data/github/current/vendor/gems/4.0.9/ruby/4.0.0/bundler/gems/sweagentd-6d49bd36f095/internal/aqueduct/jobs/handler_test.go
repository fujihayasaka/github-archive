package jobs

import (
	"context"
	"errors"
	"testing"
	"time"

	aq "github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

var noopFFClient = featureflags.NewNoopClient(nil)

// mockClient is a mock implementation of limiter.client for testing
type mockClient struct {
	rates map[uint8]limiter.Rate
	err   error
}

func (m *mockClient) RateLimitsForRepo(ctx context.Context, app sweagentd.AgenticApp, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.rates, nil
}

var mockHandler = func(ctx context.Context, _ aq.ReceiveResult) (context.Context, error) {
	return ctx, nil
}

type mockRequeue struct {
	mock.Mock
}

func (m *mockRequeue) RequeueJobWithDelay(ctx context.Context, job sweagentd.AqueductJob, delay time.Duration) (string, error) {
	args := m.Called(ctx, job, delay)
	return args.String(0), args.Error(1)
}

func TestBeforeReceive(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("waits when limiter indicates to wait", func(t *testing.T) {
		// Create a limiter with a short TTL for testing
		mockClient := &mockClient{}
		limiter := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

		// Set a secondary rate limit reset time in the future to trigger waiting
		limiter.SetSecondaryRateLimitReset(context.Background(), 0, time.Now().Add(200*time.Millisecond))

		hookCalled := false
		testHook := func(ctx context.Context) (context.Context, error) {
			hookCalled = true
			return ctx, nil
		}

		beforeReceiveHook := BeforeReceive(obsv, noopFFClient, limiter, testHook)

		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()

		start := time.Now()
		_, err := beforeReceiveHook(ctx)
		duration := time.Since(start)

		// Should timeout because we're waiting longer than the context timeout
		require.Error(t, err)
		// Golang's timer implementation and goroutine scheduling can introduce minor variations
		// in timing, so let's check that the duration is within a reasonable range.
		// It's far enough away from the 200ms rate limiting wait that this still verifies that
		// we respect the context timeout (100ms).
		require.GreaterOrEqual(t, duration, 95*time.Millisecond)
		require.LessOrEqual(t, duration, 105*time.Millisecond)
		// Hook should NOT be called because BeforeReceive returns early when context is done
		require.False(t, hookCalled)
	})

	t.Run("calls provided hook when not waiting", func(t *testing.T) {
		mockClient := &mockClient{}
		limiter := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

		hookCalled := false
		testHook := func(ctx context.Context) (context.Context, error) {
			hookCalled = true
			return ctx, nil
		}

		beforeReceiveHook := BeforeReceive(obsv, noopFFClient, limiter, testHook)

		_, err := beforeReceiveHook(context.Background())
		require.NoError(t, err)
		require.True(t, hookCalled)
	})

	t.Run("bypasses waiting when secondary rate limit cache is skipped by flag", func(t *testing.T) {
		mockClient := &mockClient{}
		limiter := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSkipSecondaryRateLimitCache: true,
		})

		limiter.SetSecondaryRateLimitReset(context.Background(), 0, time.Now().Add(200*time.Millisecond))

		hookCalled := false
		testHook := func(ctx context.Context) (context.Context, error) {
			hookCalled = true
			return ctx, nil
		}

		beforeReceiveHook := BeforeReceive(obsv, ffClient, limiter, testHook)
		_, err := beforeReceiveHook(context.Background())

		require.NoError(t, err)
		require.True(t, hookCalled)
	})

	t.Run("returns error when provided hook fails", func(t *testing.T) {
		mockClient := &mockClient{}
		limiter := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

		expectedError := errors.New("hook failed")
		testHook := func(ctx context.Context) (context.Context, error) {
			return ctx, expectedError
		}

		beforeReceiveHook := BeforeReceive(obsv, noopFFClient, limiter, testHook)

		_, err := beforeReceiveHook(context.Background())
		require.Error(t, err)
		require.Equal(t, expectedError, err)
	})

	t.Run("handles default hook", func(t *testing.T) {
		mockClient := &mockClient{}
		limiter := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

		beforeReceiveHook := BeforeReceive(obsv, noopFFClient, limiter, DefaultReceiveHook)

		_, err := beforeReceiveHook(context.Background())
		require.NoError(t, err)
	})

	t.Run("respects context cancellation while waiting", func(t *testing.T) {
		mockClient := &mockClient{}
		limiter := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

		// Set a secondary rate limit reset time in the future
		limiter.SetSecondaryRateLimitReset(context.Background(), 0, time.Now().Add(500*time.Millisecond))

		beforeReceiveHook := BeforeReceive(obsv, noopFFClient, limiter, DefaultReceiveHook)

		ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
		defer cancel()

		start := time.Now()
		_, err := beforeReceiveHook(ctx)
		duration := time.Since(start)

		// Should return within timeout period
		require.Less(t, duration, 100*time.Millisecond)
		require.Error(t, err) // Should return context.DeadlineExceeded
	})
}

func TestHandler(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("creates new request ID when none exists", func(t *testing.T) {
		wrappedHandler := Handler(obsv, &mockRequeue{}, noopFFClient, nil, mockHandler, nil)

		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "test-job-id",
				Queue:   "test-queue",
				Payload: []byte("test payload"),
			},
		}

		ctx := requestctx.NewContext(context.Background())
		newCtx, err := wrappedHandler(ctx, receiveResult)
		require.NoError(t, err)

		// Verify that a request ID was created
		requestID := requestid.GetGitHubRequestID(newCtx)
		require.NotEmpty(t, requestID)
	})

	t.Run("preserves existing request ID", func(t *testing.T) {
		wrappedHandler := Handler(obsv, &mockRequeue{}, noopFFClient, nil, mockHandler, nil)

		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "test-job-id",
				Queue:   "test-queue",
				Payload: []byte("test payload"),
			},
		}

		existingRequestID := "existing-request-123"

		ctx := requestctx.NewContext(context.Background())
		ctx = requestid.WithGitHubRequestID(ctx, existingRequestID)

		newCtx, err := wrappedHandler(ctx, receiveResult)
		require.NoError(t, err)

		// Verify that the existing request ID was preserved
		requestID := requestid.GetGitHubRequestID(newCtx)
		require.Equal(t, existingRequestID, requestID)
	})

	t.Run("adds received job to request context", func(t *testing.T) {
		wrappedHandler := Handler(obsv, &mockRequeue{}, noopFFClient, nil, mockHandler, nil)

		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "test-job-id",
				Queue:   "test-queue",
				Payload: []byte("test payload"),
				Headers: map[string]string{
					"test-header": "test-value",
				},
			},
		}

		ctx := requestctx.NewContext(context.Background())
		newCtx, err := wrappedHandler(ctx, receiveResult)
		require.NoError(t, err)

		// Verify that the job was added to the request context
		aqueductJob, exists := requestctx.AqueductJob(newCtx)
		require.True(t, exists)
		require.Equal(t, "test-job-id", aqueductJob.ID)
		require.Equal(t, "test-queue", aqueductJob.Queue)
	})

	t.Run("logs errors and handles them gracefully", func(t *testing.T) {
		expectedError := errors.New("handler failed")
		errorHandler := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedError
		}

		wrappedHandler := Handler(obsv, &mockRequeue{}, noopFFClient, nil, errorHandler, nil)

		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "test-job-id",
				Queue:   "test-queue",
				Payload: []byte("test payload"),
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err := wrappedHandler(ctx, receiveResult)
		// Error is swallowed to prevent Aqueduct NackJobErr from dropping the job
		require.NoError(t, err)
	})

	t.Run("succeeds with valid job", func(t *testing.T) {
		successHandler := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, nil
		}

		wrappedHandler := Handler(obsv, &mockRequeue{}, noopFFClient, nil, successHandler, nil)

		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "test-job-id",
				Queue:   "test-queue",
				Payload: []byte("test payload"),
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err := wrappedHandler(ctx, receiveResult)
		require.NoError(t, err)
	})

	t.Run("handles job with tenant headers", func(t *testing.T) {
		testTenantSlug := "test-org"
		testTenantID := "test-tenant-123"

		wrappedHandler := Handler(obsv, &mockRequeue{}, noopFFClient, nil, mockHandler, nil)

		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "test-job-id",
				Queue:   "test-queue",
				Payload: []byte("test payload"),
				Headers: map[string]string{
					requestctx.GitHubTenantHeader:   testTenantSlug,
					requestctx.GitHubTenantIDHeader: testTenantID,
				},
			},
		}

		ctx := requestctx.NewContext(context.Background())
		newCtx, err := wrappedHandler(ctx, receiveResult)
		require.NoError(t, err)

		// Verify that the job was added to the request context
		aqueductJob, exists := requestctx.AqueductJob(newCtx)
		require.True(t, exists)
		require.Equal(t, "test-job-id", aqueductJob.ID)
		require.Equal(t, "test-queue", aqueductJob.Queue)

		// Verify that tenant information is available in context
		// The tenant information would be extracted by AddReceivedJobToRequestContext
		// from the headers and set in the context data
		require.Equal(t, testTenantSlug, requestctx.TenantSlug(newCtx))
		require.Equal(t, testTenantID, requestctx.TenantID(newCtx))
	})

	t.Run("swallows ErrExceededMaxRequeues from inner handler", func(t *testing.T) {
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, ErrExceededMaxRequeues
		}
		wrapped := Handler(obsv, &mockRequeue{}, noopFFClient, nil, inner, nil)
		receiveResult := aq.ReceiveResult{Job: aq.Job{ID: "id", Queue: "queue", Payload: []byte("p")}}
		ctx := requestctx.NewContext(context.Background())
		_, err := wrapped(ctx, receiveResult)
		require.NoError(t, err)
	})

	t.Run("handles primary rate limit error by requeuing", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Create an EventJob that can be unmarshaled
		eventJob := &EventJob{
			Id:           "test-event-123",
			Topic:        "test-topic",
			OwnerId:      123,
			RepositoryId: 456,
		}
		payload, err := eventJob.Marshal()
		require.NoError(t, err)

		// Handler that returns a primary rate limit error
		rateLimitErr := limiter.NewRateLimitError(
			sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
			"rate limit exceeded",
			limiter.Rate{
				Limit:     5000,
				Remaining: 0,
				Reset:     time.Now().Add(10 * time.Minute),
			},
		)

		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, rateLimitErr
		}

		// Expect requeue to be called
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, mock.Anything).
			Return("new-job-id", nil)

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		// Should not return an error because we handled the rate limit by requeuing
		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
	})

	t.Run("handles secondary rate limit error by requeuing", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Create an EventJob that can be unmarshaled
		eventJob := &EventJob{
			Id:           "test-event-123",
			Topic:        "test-topic",
			OwnerId:      123,
			RepositoryId: 456,
		}
		payload, err := eventJob.Marshal()
		require.NoError(t, err)

		// Handler that returns a secondary rate limit error
		abuseErr := limiter.NewAbuseRateLimitError(
			sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
			"secondary rate limit exceeded",
			5*time.Minute,
		)

		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, abuseErr
		}

		// Expect requeue to be called
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, mock.Anything).
			Return("new-job-id", nil)

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		// Should not return an error because we handled the rate limit by requeuing
		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
	})

	t.Run("fails job via failJob when rate limit requeue fails", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Create an EventJob that can be unmarshaled
		eventJob := &EventJob{
			Id:           "test-event-123",
			Topic:        "test-topic",
			OwnerId:      123,
			RepositoryId: 456,
		}
		payload, err := eventJob.Marshal()
		require.NoError(t, err)

		// Handler that returns a primary rate limit error
		rateLimitErr := limiter.NewRateLimitError(
			sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
			"rate limit exceeded",
			limiter.Rate{
				Limit:     5000,
				Remaining: 0,
				Reset:     time.Now().Add(10 * time.Minute),
			},
		)

		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, rateLimitErr
		}

		// Requeue fails in handleRateLimitErrors
		requeueErr := errors.New("requeue failed")
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, mock.Anything).
			Return("", requeueErr)

		// Verify failJob is called with rate_limit_requeue_failure code
		// instead of attempting a second requeue with the transient delay
		failJobCalled := false
		failJobFunc := func(ctx context.Context, rr aq.ReceiveResult, errorCode string, errorMessage string) {
			failJobCalled = true
			require.Equal(t, "rate_limit_requeue_failure", errorCode)
			require.Contains(t, errorMessage, "rate limit requeue failed")
		}

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, failJobFunc)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		require.NoError(t, err)
		require.True(t, failJobCalled, "failJob should be called for failed rate limit requeue")
		// RequeueJobWithDelay should only be called once (by handleRateLimitErrors),
		// not a second time by handleTransientError
		mockRequeue.AssertNumberOfCalls(t, "RequeueJobWithDelay", 1)
	})

	t.Run("does not requeue when max requeues exceeded via headers", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Create an EventJob that can be unmarshaled
		eventJob := &EventJob{
			Id:           "test-event-123",
			Topic:        "test-topic",
			OwnerId:      123,
			RepositoryId: 456,
		}
		payload, err := eventJob.Marshal()
		require.NoError(t, err)

		// Handler that returns a primary rate limit error
		rateLimitErr := limiter.NewRateLimitError(
			sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
			"rate limit exceeded",
			limiter.Rate{
				Limit:     5000,
				Remaining: 0,
				Reset:     time.Now().Add(10 * time.Minute),
			},
		)

		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, rateLimitErr
		}

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: payload,
				Headers: map[string]string{
					RequeueCountHeader:    "5",
					RequeueMaxCountHeader: "5",
				},
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		// Should not return an error because we swallow ErrExceededMaxRequeues
		require.NoError(t, err)
		// Requeue should NOT be called
		mockRequeue.AssertNotCalled(t, "RequeueJobWithDelay")
	})

	t.Run("does not requeue when max requeues exceeded via job data", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Create an EventJob that has exceeded max requeues
		eventJob := &EventJob{
			Id:           "test-event-123",
			Topic:        "test-topic",
			OwnerId:      123,
			RepositoryId: 456,
			RequeueCount: EventJobMaxRequeueCount, // Already at max
		}
		payload, err := eventJob.Marshal()
		require.NoError(t, err)

		// Handler that returns a primary rate limit error
		rateLimitErr := limiter.NewRateLimitError(
			sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
			"rate limit exceeded",
			limiter.Rate{
				Limit:     5000,
				Remaining: 0,
				Reset:     time.Now().Add(10 * time.Minute),
			},
		)

		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, rateLimitErr
		}

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		// Should not return an error because we swallow ErrExceededMaxRequeues
		require.NoError(t, err)
		// Requeue should NOT be called
		mockRequeue.AssertNotCalled(t, "RequeueJobWithDelay")
	})

	t.Run("requeues job on transient non-rate-limit error", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Create an AgentJob that can be unmarshaled
		agentJob := &AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
		}
		payload, err := agentJob.Marshal()
		require.NoError(t, err)

		expectedErr := errors.New("quota service timeout")
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedErr
		}

		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, TransientErrorRequeueDelay).
			Return("new-job-id", nil)

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   AgentJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		// Error should be swallowed (not passed to Aqueduct) and job requeued
		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
	})

	t.Run("calls failJob when max requeues exceeded on transient error", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Create an AgentJob that has exceeded max requeues
		agentJob := &AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			RequeueCount: AgentJobMaxRequeueCount + 1,
		}
		payload, err := agentJob.Marshal()
		require.NoError(t, err)

		expectedErr := errors.New("transient failure")
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedErr
		}

		failJobCalled := false
		var capturedCode, capturedMsg string
		testFailJob := FailJobFunc(func(ctx context.Context, rr aq.ReceiveResult, code string, msg string) {
			failJobCalled = true
			capturedCode = code
			capturedMsg = msg
		})

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, testFailJob)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   AgentJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		require.NoError(t, err)
		require.True(t, failJobCalled)
		require.Equal(t, "processing_error", capturedCode)
		require.Contains(t, capturedMsg, "transient failure")
		// Requeue should NOT be called since max requeues exceeded
		mockRequeue.AssertNotCalled(t, "RequeueJobWithDelay")
	})

	t.Run("calls failJob when requeue fails on transient error", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		agentJob := &AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
		}
		payload, err := agentJob.Marshal()
		require.NoError(t, err)

		expectedErr := errors.New("db connection failed")
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedErr
		}

		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, TransientErrorRequeueDelay).
			Return("", errors.New("requeue failed"))

		failJobCalled := false
		var capturedCode string
		testFailJob := FailJobFunc(func(ctx context.Context, rr aq.ReceiveResult, code string, msg string) {
			failJobCalled = true
			capturedCode = code
		})

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, testFailJob)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   AgentJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		require.NoError(t, err)
		require.True(t, failJobCalled)
		require.Equal(t, "queue_failure", capturedCode)
		mockRequeue.AssertExpectations(t)
	})

	t.Run("handles transient error without failJob callback", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Create an AgentJob that has exceeded max requeues
		agentJob := &AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			RequeueCount: AgentJobMaxRequeueCount + 1,
		}
		payload, err := agentJob.Marshal()
		require.NoError(t, err)

		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, errors.New("some error")
		}

		// Pass nil failJob — should still swallow the error
		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   AgentJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		// Should not return error even without failJob
		require.NoError(t, err)
	})

	t.Run("handles rate limit error with invalid payload gracefully", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		// Handler that returns a rate limit error
		rateLimitErr := limiter.NewRateLimitError(
			sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
			"rate limit exceeded",
			limiter.Rate{
				Limit:     5000,
				Remaining: 0,
				Reset:     time.Now().Add(10 * time.Minute),
			},
		)

		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, rateLimitErr
		}

		wrapped := Handler(obsv, mockRequeue, noopFFClient, nil, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: []byte("invalid payload"), // Cannot be unmarshaled
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err := wrapped(ctx, receiveResult)

		// Outer handler swallows all errors to prevent Aqueduct NACK
		require.NoError(t, err)
		// Requeue should NOT be called since payload can't be parsed
		mockRequeue.AssertNotCalled(t, "RequeueJobWithDelay")
	})

	t.Run("uses rate limit delay for transient error when primary rate limited", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		agentJob := &AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
			AgentId:      0, // default copilot app
		}
		payload, err := agentJob.Marshal()
		require.NoError(t, err)

		expectedErr := errors.New("failed to get pull request context")
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedErr
		}

		// Set up a rate limiter with a cached primary rate limit
		mockClient := &mockClient{}
		rl := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)
		resetTime := time.Now().Add(30 * time.Minute)
		rl.SetRate(context.Background(), target, 0, limiter.Rate{Limit: 5000, Remaining: 0, Reset: resetTime})

		// Expect requeue with a delay much larger than TransientErrorRequeueDelay
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, mock.MatchedBy(func(d time.Duration) bool {
			return d > time.Minute
		})).Return("new-job-id", nil)

		wrapped := Handler(obsv, mockRequeue, noopFFClient, rl, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   AgentJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
	})

	t.Run("uses rate limit delay for transient error when secondary rate limited", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		eventJob := &EventJob{
			OwnerId:      100,
			RepositoryId: 200,
			AgentId:      0,
			Topic:        "test",
		}
		payload, err := eventJob.Marshal()
		require.NoError(t, err)

		expectedErr := errors.New("getting user permissions for repository")
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedErr
		}

		mockClient := &mockClient{}
		rl := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		rl.SetSecondaryRateLimitReset(context.Background(), 0, time.Now().Add(10*time.Minute))

		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, mock.MatchedBy(func(d time.Duration) bool {
			return d > time.Minute
		})).Return("new-job-id", nil)

		wrapped := Handler(obsv, mockRequeue, noopFFClient, rl, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
	})

	t.Run("skips secondary rate limit delay when skip flag is enabled", func(t *testing.T) {
		mockRequeue := &mockRequeue{}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSkipSecondaryRateLimitCache: true,
		})

		agentJob := &AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
			AgentId:      0,
		}
		payload, err := agentJob.Marshal()
		require.NoError(t, err)

		expectedErr := errors.New("failed to get pull request context")
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedErr
		}

		mockClient := &mockClient{}
		rl := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		// Set a secondary rate limit that would normally cause a longer delay
		rl.SetSecondaryRateLimitReset(context.Background(), 0, time.Now().Add(30*time.Minute))

		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, TransientErrorRequeueDelay).
			Return("new-job-id", nil)

		wrapped := Handler(obsv, mockRequeue, ffClient, rl, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   AgentJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
	})

	t.Run("uses default delay for transient error when not rate limited", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		agentJob := &AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
		}
		payload, err := agentJob.Marshal()
		require.NoError(t, err)

		expectedErr := errors.New("database timeout")
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedErr
		}

		// Rate limiter with no cached rate limits — cache miss should NOT call external API
		mockClient := &mockClient{}
		rl := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, TransientErrorRequeueDelay).
			Return("new-job-id", nil)

		wrapped := Handler(obsv, mockRequeue, noopFFClient, rl, inner, nil)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   AgentJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
	})
}

func TestCacheRateLimiter(t *testing.T) {
	ctx := context.Background()
	cache := cache.NewMemoryCacheStore()
	rate := limiter.Rate{Limit: 100, Remaining: 0, Reset: time.Now().Add(1 * time.Minute)}
	mockClient := &mockClient{rates: map[uint8]limiter.Rate{1: rate}}
	rl := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache, agenticapptest.NewTestProvider(t))

	t.Run("WaitToReceive returns correct delay when secondary rate limit is set", func(t *testing.T) {
		reset := time.Now().Add(2 * time.Second)
		cache.Set("rate_limit:secondary_rate_limit_reset:app:0", reset.Format(time.RFC3339Nano), time.Minute)
		delay, ok := rl.WaitToReceive(ctx, 0)
		require.True(t, ok)
		require.GreaterOrEqual(t, delay, 1*time.Second)
	})

	t.Run("WaitToReceive returns false when secondary rate limit is not set", func(t *testing.T) {
		cache.Set("rate_limit:secondary_rate_limit_reset:app:0", "", time.Minute)
		delay, ok := rl.WaitToReceive(ctx, 0)
		require.False(t, ok)
		require.Equal(t, time.Duration(0), delay)
	})

	t.Run("SetSecondaryRateLimitReset sets the reset time in cache", func(t *testing.T) {
		reset := time.Now().Add(3 * time.Second)
		rl.SetSecondaryRateLimitReset(ctx, 0, reset)
		val, ok := cache.Get("rate_limit:secondary_rate_limit_reset:app:0")
		require.True(t, ok)
		parsed, err := time.Parse(time.RFC3339Nano, val)
		require.NoError(t, err)
		require.WithinDuration(t, reset, parsed, time.Second)
	})

	t.Run("SetRate and GetRate store and retrieve a rate", func(t *testing.T) {
		target := sweagentd.ClientTargetForInstallationByOwnerID(0, 42)
		category := uint8(2)
		rate := limiter.Rate{Limit: 50, Remaining: 10, Reset: time.Now().Add(5 * time.Minute)}
		rl.SetRate(ctx, target, category, rate)
		got, ok := rl.GetRate(ctx, target, category)
		require.True(t, ok)
		require.Equal(t, rate.Limit, got.Limit)
		require.Equal(t, rate.Remaining, got.Remaining)
		require.WithinDuration(t, rate.Reset, got.Reset, time.Second)
	})

	t.Run("SetRates and GetRates store and retrieve multiple rates", func(t *testing.T) {
		target := sweagentd.ClientTargetForInstallationByOwnerID(0, 99)
		rates := map[uint8]limiter.Rate{
			1: {Limit: 10, Remaining: 5, Reset: time.Now().Add(1 * time.Minute)},
			2: {Limit: 20, Remaining: 15, Reset: time.Now().Add(2 * time.Minute)},
		}
		rl.SetRates(ctx, target, rates)
		got, ok := rl.GetRates(ctx, target, 1, 2)
		require.True(t, ok)
		require.Equal(t, rates[1].Limit, got[1].Limit)
		require.Equal(t, rates[2].Limit, got[2].Limit)
	})

	t.Run("DelayProcessing returns delay for secondary rate limit", func(t *testing.T) {
		reset := time.Now().Add(1 * time.Second)
		cache.Set("rate_limit:secondary_rate_limit_reset:app:0", reset.Format(time.RFC3339Nano), time.Minute)
		delay, ok := rl.DelayProcessing(ctx, 0, 123, 456, 1)
		require.True(t, ok)
		require.GreaterOrEqual(t, delay, 1*time.Second)
	})

	t.Run("DelayProcessing returns delay for primary rate limit from cache", func(t *testing.T) {
		target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)
		rate := limiter.Rate{Limit: 100, Remaining: 0, Reset: time.Now().Add(2 * time.Second)}
		rl.SetRate(ctx, target, 1, rate)
		delay, ok := rl.DelayProcessing(ctx, 0, 123, 456, 1)
		require.True(t, ok)
		// DelayProcessing adds a 1 second buffer, so delay will be ~3 seconds
		require.GreaterOrEqual(t, delay, 1*time.Second)
	})

	t.Run("DelayProcessing falls back to client when cache miss", func(t *testing.T) {
		// Clear cache
		cache.TestClear()
		delay, ok := rl.DelayProcessing(ctx, 0, 1, 2, 1)
		require.True(t, ok)
		require.GreaterOrEqual(t, delay, 1*time.Minute)
	})
}
