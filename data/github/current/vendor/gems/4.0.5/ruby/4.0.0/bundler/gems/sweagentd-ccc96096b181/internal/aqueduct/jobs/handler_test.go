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
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

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

		beforeReceiveHook := BeforeReceive(obsv, limiter, testHook)

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

		beforeReceiveHook := BeforeReceive(obsv, limiter, testHook)

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

		beforeReceiveHook := BeforeReceive(obsv, limiter, testHook)

		_, err := beforeReceiveHook(context.Background())
		require.Error(t, err)
		require.Equal(t, expectedError, err)
	})

	t.Run("handles default hook", func(t *testing.T) {
		mockClient := &mockClient{}
		limiter := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

		beforeReceiveHook := BeforeReceive(obsv, limiter, DefaultReceiveHook)

		_, err := beforeReceiveHook(context.Background())
		require.NoError(t, err)
	})

	t.Run("respects context cancellation while waiting", func(t *testing.T) {
		mockClient := &mockClient{}
		limiter := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

		// Set a secondary rate limit reset time in the future
		limiter.SetSecondaryRateLimitReset(context.Background(), 0, time.Now().Add(500*time.Millisecond))

		beforeReceiveHook := BeforeReceive(obsv, limiter, DefaultReceiveHook)

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
		wrappedHandler := Handler(obsv, &mockRequeue{}, mockHandler)

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
		wrappedHandler := Handler(obsv, &mockRequeue{}, mockHandler)

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
		wrappedHandler := Handler(obsv, &mockRequeue{}, mockHandler)

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

	t.Run("logs and reports errors", func(t *testing.T) {
		expectedError := errors.New("handler failed")
		errorHandler := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedError
		}

		wrappedHandler := Handler(obsv, &mockRequeue{}, errorHandler)

		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "test-job-id",
				Queue:   "test-queue",
				Payload: []byte("test payload"),
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err := wrappedHandler(ctx, receiveResult)
		require.Error(t, err)
		require.Equal(t, expectedError, err)
	})

	t.Run("succeeds with valid job", func(t *testing.T) {
		successHandler := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, nil
		}

		wrappedHandler := Handler(obsv, &mockRequeue{}, successHandler)

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

		wrappedHandler := Handler(obsv, &mockRequeue{}, mockHandler)

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
		wrapped := Handler(obsv, &mockRequeue{}, inner)
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

		wrapped := Handler(obsv, mockRequeue, inner)
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

		wrapped := Handler(obsv, mockRequeue, inner)
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

	t.Run("returns error when requeue fails after rate limit", func(t *testing.T) {
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

		// Requeue fails
		requeueErr := errors.New("requeue failed")
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, mock.Anything).
			Return("", requeueErr)

		wrapped := Handler(obsv, mockRequeue, inner)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: payload,
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err = wrapped(ctx, receiveResult)

		// Should return the original rate limit error because requeue failed
		require.Error(t, err)
		require.True(t, limiter.IsRateLimitError(err))
		mockRequeue.AssertExpectations(t)
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

		wrapped := Handler(obsv, mockRequeue, inner)
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

		wrapped := Handler(obsv, mockRequeue, inner)
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

	t.Run("passes through non-rate-limit errors", func(t *testing.T) {
		mockRequeue := &mockRequeue{}

		expectedErr := errors.New("some other error")
		inner := func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
			return ctx, expectedErr
		}

		wrapped := Handler(obsv, mockRequeue, inner)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   "test-queue",
				Payload: []byte("test payload"),
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err := wrapped(ctx, receiveResult)

		// Should return the original error
		require.Error(t, err)
		require.Equal(t, expectedErr, err)
		// Requeue should NOT be called
		mockRequeue.AssertNotCalled(t, "RequeueJobWithDelay")
	})

	t.Run("returns original error when job unmarshal fails during rate limit handling", func(t *testing.T) {
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

		wrapped := Handler(obsv, mockRequeue, inner)
		receiveResult := aq.ReceiveResult{
			Job: aq.Job{
				ID:      "job-123",
				Queue:   EventJobQueueName,
				Payload: []byte("invalid payload"), // Cannot be unmarshaled
			},
		}

		ctx := requestctx.NewContext(context.Background())
		_, err := wrapped(ctx, receiveResult)

		// Should return the original rate limit error because we can't unmarshal the job
		require.Error(t, err)
		require.True(t, limiter.IsRateLimitError(err))
		// Requeue should NOT be called
		mockRequeue.AssertNotCalled(t, "RequeueJobWithDelay")
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
