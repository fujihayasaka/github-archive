package apijob

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/featureflags"
	db "github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

type mockRequeue struct {
	mock.Mock
}

func (m *mockRequeue) RequeueJobWithDelay(ctx context.Context, job sweagentd.AqueductJob, delay time.Duration) (string, error) {
	args := m.Called(ctx, job, delay)
	return args.String(0), args.Error(1)
}

type mockJobService struct {
	mock.Mock
}

func (m *mockJobService) GetJobQueuedForProcessing(ctx context.Context, queueJob *jobs.APIJob) (*db.Assignment, *db.Job, error) {
	args := m.Called(ctx, queueJob)
	if args.Get(0) == nil || args.Get(1) == nil {
		return nil, nil, args.Error(2)
	}
	return args.Get(0).(*db.Assignment), args.Get(1).(*db.Job), args.Error(2)
}

func (m *mockJobService) FinalizeJob(ctx context.Context, job *db.Job, status db.JobStatus, completedAt int64) error {
	args := m.Called(ctx, job, status, completedAt)
	return args.Error(0)
}

func (m *mockJobService) Process(ctx context.Context, job *jobs.APIJob) error {
	args := m.Called(ctx, job)
	return args.Error(0)
}

type mockClient struct {
	mock.Mock
}

func (m *mockClient) RateLimitsForRepo(ctx context.Context, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
	args := m.Called(ctx, ownerID, repoID)
	return args.Get(0).(map[uint8]limiter.Rate), args.Error(1)
}

func TestAPIJobHandler(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	t.Run("returns error for unknown queue", func(t *testing.T) {
		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   "unknown-queue",
				Payload: []byte("test payload"),
			},
		}

		service := &mockJobService{}
		requeue := &mockRequeue{}
		limiter := limiter.NewRateLimiterV1(&mockClient{}, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		require.Error(t, err)
		require.Contains(t, err.Error(), `unknown queue "unknown-queue"`)
	})

	t.Run("returns error for invalid job payload", func(t *testing.T) {
		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: []byte("invalid protobuf payload"),
			},
		}

		service := &mockJobService{}
		requeue := &mockRequeue{}
		limiter := limiter.NewRateLimiterV1(&mockClient{}, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to unmarshal")
	})

	t.Run("processes job when rate limits not exceeded", func(t *testing.T) {
		testJob := &jobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			SessionId:    "test-session",
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
			},
		}

		service := &mockJobService{}
		requeue := &mockRequeue{}
		service.On("Process", mock.Anything, mock.MatchedBy(func(job *jobs.APIJob) bool {
			return job.JobId == "test-job" && job.AssignmentId == "test-assignment"
		})).Return(nil)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{
				uint8(gg.CoreCategory):    {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
				uint8(gg.GraphqlCategory): {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
			}, nil)

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.NoError(t, err)
		service.AssertExpectations(t)
		client.AssertExpectations(t)
	})

	t.Run("handles GitHub request ID in APIJob", func(t *testing.T) {
		testRequestID := "test-request-456"

		testJob := &jobs.APIJob{
			AssignmentId:    "test-assignment",
			JobId:           "test-job",
			OwnerId:         12345,
			RepositoryId:    67890,
			ActorId:         11111,
			SessionId:       "test-session",
			GithubRequestId: testRequestID,
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
			},
		}

		service := &mockJobService{}
		requeue := &mockRequeue{}
		service.On("Process", mock.Anything, mock.MatchedBy(func(job *jobs.APIJob) bool {
			return job.GithubRequestId == testRequestID
		})).Return(nil)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{
				uint8(gg.CoreCategory):    {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
				uint8(gg.GraphqlCategory): {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
			}, nil)

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.NoError(t, err)
		service.AssertExpectations(t)
	})

	t.Run("returns error when processor fails", func(t *testing.T) {
		testJob := &jobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			SessionId:    "test-session",
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
			},
		}

		expectedError := errors.New("processor failed")
		service := &mockJobService{}
		requeue := &mockRequeue{}
		service.On("Process", mock.Anything, mock.AnythingOfType("*jobs.APIJob")).Return(expectedError)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{
				uint8(gg.CoreCategory):    {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
				uint8(gg.GraphqlCategory): {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
			}, nil)

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.Error(t, err)
		require.Equal(t, expectedError, err)
		service.AssertExpectations(t)
	})

	t.Run("requeues job when rate limits exceeded", func(t *testing.T) {
		testJob := &jobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			SessionId:    "test-session",
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
			},
		}

		// Mock processor - should not be called since we're requeuing
		service := &mockJobService{}

		// Mock requeue
		mockReq := &mockRequeue{}
		mockReq.On("RequeueJobWithDelay", mock.Anything, mock.MatchedBy(func(job sweagentd.AqueductJob) bool {
			apiJob, ok := job.(*jobs.APIJob)
			return ok && apiJob.JobId == "test-job"
		}), mock.AnythingOfType("time.Duration")).Return("new-job-id", nil)

		// Mock rate limiter to trigger delay
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{
				uint8(gg.CoreCategory):    {Remaining: 0, Reset: time.Now().Add(time.Hour)}, // Exhausted
				uint8(gg.GraphqlCategory): {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
			}, nil)

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, mockReq, Handler(obsv, ffClient, mockReq, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.NoError(t, err)
		mockReq.AssertExpectations(t)
		// Processor should not be called
		service.AssertNotCalled(t, "Process")
	})

	t.Run("returns error when job exceeds max requeue count", func(t *testing.T) {
		testJob := &jobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			SessionId:    "test-session",
			RequeueCount: jobs.APIJobMaxRequeueCount + 1, // Exceeds max
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
			},
		}

		// Mock the job service to handle failJob calls
		service := &mockJobService{}
		mockAssignment := &db.Assignment{ID: "test-assignment"}
		mockJob := &db.Job{ID: "test-job"}
		service.On("GetJobQueuedForProcessing", mock.Anything, mock.AnythingOfType("*jobs.APIJob")).Return(mockAssignment, mockJob, nil)
		service.On("FinalizeJob", mock.Anything, mockJob, db.JobStatusFailed, mock.AnythingOfType("int64")).Return(nil)

		mockReq := &mockRequeue{}

		// Mock rate limiter to trigger delay (but should not requeue due to exceeded count)
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{
				uint8(gg.CoreCategory):    {Remaining: 0, Reset: time.Now().Add(time.Hour)}, // Exhausted
				uint8(gg.GraphqlCategory): {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
			}, nil)

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, mockReq, Handler(obsv, ffClient, mockReq, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		// ErrExceededMaxRequeues should be swallowed by the outer jobs.Handler
		require.NoError(t, err)

		// Neither processor nor requeue should be called
		service.AssertNotCalled(t, "Process")
		mockReq.AssertNotCalled(t, "RequeueJobWithDelay")
		// But failJob methods should be called
		service.AssertExpectations(t)
	})

	t.Run("returns error when RequeueJobWithDelay fails", func(t *testing.T) {
		testJob := &jobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			SessionId:    "test-session",
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
			},
		}

		// Mock the job service to handle failJob calls
		service := &mockJobService{}
		mockAssignment := &db.Assignment{ID: "test-assignment"}
		mockJob := &db.Job{ID: "test-job"}
		service.On("GetJobQueuedForProcessing", mock.Anything, mock.AnythingOfType("*jobs.APIJob")).Return(mockAssignment, mockJob, nil)
		service.On("FinalizeJob", mock.Anything, mockJob, db.JobStatusFailed, mock.AnythingOfType("int64")).Return(nil)

		// Mock requeue to fail
		expectedRequeueError := errors.New("requeue failed")
		mockReq := &mockRequeue{}
		mockReq.On("RequeueJobWithDelay", mock.Anything, mock.AnythingOfType("*jobs.APIJob"), mock.AnythingOfType("time.Duration")).Return("", expectedRequeueError)

		// Mock rate limiter to trigger delay
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{
				uint8(gg.CoreCategory):    {Remaining: 0, Reset: time.Now().Add(time.Hour)}, // Exhausted
				uint8(gg.GraphqlCategory): {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
			}, nil)

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, mockReq, Handler(obsv, ffClient, mockReq, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to requeue api job with delay")
		require.Contains(t, err.Error(), "requeue failed")

		mockReq.AssertExpectations(t)
		service.AssertNotCalled(t, "Process")
		service.AssertExpectations(t) // Verify failJob was called
	})

	t.Run("processes job when rate limits enabled but not exceeded", func(t *testing.T) {
		testJob := &jobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			SessionId:    "test-session",
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
			},
		}

		service := &mockJobService{}
		requeue := &mockRequeue{}
		service.On("Process", mock.Anything, mock.AnythingOfType("*jobs.APIJob")).Return(nil)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{
				uint8(gg.CoreCategory):    {Remaining: 100, Reset: time.Now().Add(time.Hour)}, // Below limit
				uint8(gg.GraphqlCategory): {Remaining: 100, Reset: time.Now().Add(time.Hour)},
			}, nil)

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.NoError(t, err)
		service.AssertExpectations(t)
	})

	t.Run("handles rate limit client error gracefully", func(t *testing.T) {
		testJob := &jobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			SessionId:    "test-session",
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
			},
		}

		service := &mockJobService{}
		requeue := &mockRequeue{}
		service.On("Process", mock.Anything, mock.AnythingOfType("*jobs.APIJob")).Return(nil)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{}, errors.New("rate limit client error")) // Should continue processing despite error

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.NoError(t, err)
		service.AssertExpectations(t)
	})

	t.Run("forwards tenant information from APIJob", func(t *testing.T) {
		testTenantSlug := "test-org"
		testTenantID := "test-tenant-123"

		apiJob := &jobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      12345,
			RepositoryId: 67890,
			ActorId:      11111,
			SessionId:    "test-session",
		}

		payload, err := proto.Marshal(apiJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.APIJobQueueName,
				Payload: payload,
				Headers: map[string]string{
					requestctx.GitHubTenantHeader:   testTenantSlug,
					requestctx.GitHubTenantIDHeader: testTenantID,
				},
			},
		}

		// Use a mock processor that captures the context
		service := &mockJobService{}
		requeue := &mockRequeue{}
		var capturedCtx context.Context
		service.On("Process", mock.MatchedBy(func(c context.Context) bool {
			capturedCtx = c //nolint:fatcontext // capturing context for test verification
			return true
		}), mock.MatchedBy(func(job *jobs.APIJob) bool {
			return job.JobId == "test-job"
		})).Return(nil)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(12345), int64(67890)).Return(
			map[uint8]limiter.Rate{
				uint8(gg.CoreCategory):    {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
				uint8(gg.GraphqlCategory): {Remaining: 1000, Reset: time.Now().Add(time.Hour)},
			}, nil)

		limiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, limiter, service))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		// Verify that the tenant information was forwarded to the context
		require.Equal(t, testTenantSlug, requestctx.TenantSlug(capturedCtx))
		require.Equal(t, testTenantID, requestctx.TenantID(capturedCtx))
		service.AssertExpectations(t)
	})
}
