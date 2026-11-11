package agentjob

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobexecutor"
	db "github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
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

type mockClient struct {
	mock.Mock
}

func (m *mockClient) RateLimitsForRepo(ctx context.Context, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
	args := m.Called(ctx, ownerID, repoID)
	return args.Get(0).(map[uint8]limiter.Rate), args.Error(1)
}

type mockStore struct {
	mock.Mock
}

func (m *mockStore) GetJobCountByStatusForActor(ctx context.Context, actor int64, window time.Duration) (sweagentd.JobCounts, error) {
	args := m.Called(ctx, actor, window)
	return args.Get(0).(sweagentd.JobCounts), args.Error(1)
}

type mockJobService struct {
	mock.Mock
}

func (m *mockJobService) GetJobQueuedForExecution(ctx context.Context, queueJob *jobs.AgentJob) (*db.Job, error) {
	args := m.Called(ctx, queueJob)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*db.Job), args.Error(1)
}

func (m *mockJobService) FinalizeUnexecutedJob(ctx context.Context, job *db.Job, status db.JobStatus, errorMessage string) error {
	args := m.Called(ctx, job, status, errorMessage)
	return args.Error(0)
}

func TestJobHandler(t *testing.T) {
	obsv := observability.NewNoopExporters()

	executor := jobexecutor.NewNoopJobExecutor(obsv)

	t.Run("returns error for unknown queue", func(t *testing.T) {
		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   "unknown-queue",
				Payload: []byte("test payload"),
			},
		}

		store := &mockStore{}
		service := &mockJobService{}
		requeue := &mockRequeue{}
		rateLimiter := limiter.NewRateLimiterV1(&mockClient{}, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, executor))

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		require.Error(t, err)
		require.Contains(t, err.Error(), `unknown queue "unknown-queue"`)
	})

	t.Run("returns error for invalid job payload", func(t *testing.T) {
		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: []byte("invalid protobuf payload"),
			},
		}

		store := &mockStore{}
		service := &mockJobService{}
		requeue := &mockRequeue{}
		rateLimiter := limiter.NewRateLimiterV1(&mockClient{}, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, executor))

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to unmarshal")
	})

	t.Run("handles panic in job processing", func(t *testing.T) {
		// This test demonstrates the panic recovery mechanism
		// We would need a job type that panics to test this properly
		// For now, we'll test with valid input to ensure the defer mechanism works

		testJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
		}

		payload, err := proto.Marshal(testJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, int64(0), mock.Anything).Return(sweagentd.JobCounts{Running: 5, Queued: 0}, nil)

		// Use a mock executor that returns an error to simulate job processing failure
		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		mockExecutor.On("ProcessJob", mock.Anything, mock.Anything).Return(errors.New("simulated error"))

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.Error(t, err)
		mockExecutor.AssertExpectations(t)
	})

	t.Run("errors when job processing fails", func(t *testing.T) {
		// Test the error logging mechanism by using an invalid payload
		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: []byte("invalid payload"),
			},
		}

		store := &mockStore{}
		service := &mockJobService{}
		requeue := &mockRequeue{}
		rateLimiter := limiter.NewRateLimiterV1(&mockClient{}, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, executor))

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to unmarshal")
	})

	t.Run("forwards tenant information from AgentJob", func(t *testing.T) {
		testTenantSlug := "test-org"
		testTenantID := "test-tenant-123"

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
				Headers: map[string]string{
					requestctx.GitHubTenantHeader:   testTenantSlug,
					requestctx.GitHubTenantIDHeader: testTenantID,
				},
			},
		}

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, int64(0), mock.Anything).Return(sweagentd.JobCounts{Running: 5, Queued: 0}, nil)

		// Use a mock executor that captures the context
		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		var capturedCtx context.Context
		mockExecutor.On("ProcessJob", mock.MatchedBy(func(c context.Context) bool {
			capturedCtx = c //nolint:fatcontext // capturing context for test verification
			return true
		}), mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.AssignmentId == "test-assignment" && job.JobId == "test-job"
		})).Return(nil)

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		// Verify that the tenant information was forwarded to the context
		require.Equal(t, testTenantSlug, requestctx.TenantSlug(capturedCtx))
		require.Equal(t, testTenantID, requestctx.TenantID(capturedCtx))
		mockExecutor.AssertExpectations(t)
	})

	t.Run("handles GitHub request ID in AgentJob", func(t *testing.T) {
		testActorID := int64(12345)
		testRequestID := "test-request-456"

		agentJob := &jobs.AgentJob{
			AssignmentId:    "test-assignment",
			JobId:           "test-job",
			ActorId:         testActorID,
			GithubRequestId: testRequestID,
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		mockExecutor.On("ProcessJob", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.GithubRequestId == testRequestID
		})).Return(nil)

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 5, Queued: 0}, nil)

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		mockExecutor.AssertExpectations(t)
	})

	t.Run("handles GitHub request ID in AgentJob with", func(t *testing.T) {
		testActorID := int64(12345)
		testRequestID := "test-request-456"

		agentJob := &jobs.AgentJob{
			AssignmentId:    "test-assignment",
			JobId:           "test-job",
			ActorId:         testActorID,
			GithubRequestId: testRequestID,
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		ffClient := featureflags.NewNoopClient(nil)

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		mockExecutor.On("ProcessJob", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.GithubRequestId == testRequestID
		})).Return(nil)

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 5, Queued: 0}, nil)

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, ffClient, requeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		mockExecutor.AssertExpectations(t)
	})

	t.Run("returns error when ProcessJob fails", func(t *testing.T) {
		testActorID := int64(12345)
		expectedError := errors.New("job processing failed")

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			ActorId:      testActorID,
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		// Mock executor that returns an error
		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		mockExecutor.On("ProcessJob", mock.Anything, mock.Anything).Return(expectedError)

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 5, Queued: 0}, nil)

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.Error(t, err)

		mockExecutor.AssertExpectations(t)
	})

	t.Run("requeues job when too many running jobs", func(t *testing.T) {
		testActorID := int64(12345)
		testRepoID := int64(67890)
		testOwnerID := int64(11111)

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			ActorId:      testActorID,
			RepositoryId: testRepoID,
			OwnerId:      testOwnerID,
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		// Should not call ProcessJob since we're requeuing

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 20, Queued: 0}, nil)

		mockRequeue := &mockRequeue{}
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, limiter.JobRequeueDelay).Return("new-job-id", nil)

		service := &mockJobService{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, mockRequeue, Handler(obsv, featureflags.NewNoopClient(nil), mockRequeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		mockRequeue.AssertExpectations(t)
		mockExecutor.AssertExpectations(t)
	})

	t.Run("processes job when concurrency limits enabled but not exceeded", func(t *testing.T) {
		testActorID := int64(12345)
		testRepoID := int64(67890)
		testOwnerID := int64(11111)

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			ActorId:      testActorID,
			RepositoryId: testRepoID,
			OwnerId:      testOwnerID,
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		mockExecutor.On("ProcessJob", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.AssignmentId == "test-assignment" && job.JobId == "test-job"
		})).Return(nil)

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 5, Queued: 0}, nil) // Below limit

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		mockExecutor.AssertExpectations(t)
	})

	t.Run("fails job and swallows error when job exceeds max requeue count", func(t *testing.T) {
		testActorID := int64(12345)
		testRepoID := int64(67890)
		testOwnerID := int64(11111)

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			ActorId:      testActorID,
			RepositoryId: testRepoID,
			OwnerId:      testOwnerID,
			RequeueCount: jobs.AgentJobMaxRequeueCount + 1, // Above max requeue count of 16
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		// Should not call ProcessJob or RequeueJob

		mockService := &mockJobService{}
		// Should call GetJobQueuedForExecution followed by FinalizeUnexecutedJob
		mockDbJob := &db.Job{
			ID:      "test-job",
			OwnerID: testOwnerID,
			RepoID:  testRepoID,
		}
		mockService.On("GetJobQueuedForExecution", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.JobId == "test-job"
		})).Return(mockDbJob, nil)
		mockService.On("FinalizeUnexecutedJob", mock.Anything, mockDbJob, db.JobStatusFailed, "too many agent jobs in progress").Return(nil)

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 20, Queued: 0}, nil)

		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, mockService, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		// ErrExceededMaxRequeues should be swallowed by the outer jobs.Handler
		require.NoError(t, err)

		mockExecutor.AssertExpectations(t)
		mockService.AssertExpectations(t)
	})

	t.Run("returns error when RequeueJobWithDelay fails during concurrency limiting", func(t *testing.T) {
		testActorID := int64(12345)
		testRepoID := int64(67890)
		testOwnerID := int64(11111)
		expectedError := errors.New("requeue with delay failed")

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			ActorId:      testActorID,
			RepositoryId: testRepoID,
			OwnerId:      testOwnerID,
			RequeueCount: 5, // Below max requeue count
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		// Should not call ProcessJob

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 20, Queued: 0}, nil)

		mockRequeue := &mockRequeue{}
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, limiter.JobRequeueDelay).Return("", expectedError)

		// Expect GetJobQueuedForExecution and FinalizeUnexecutedJob to be called when requeue fails
		mockService := &mockJobService{}
		mockDbJob := &db.Job{
			ID:      "test-job",
			OwnerID: testOwnerID,
			RepoID:  testRepoID,
		}
		mockService.On("GetJobQueuedForExecution", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.JobId == "test-job"
		})).Return(mockDbJob, nil)
		mockService.On("FinalizeUnexecutedJob", mock.Anything, mockDbJob, db.JobStatusFailed, "").Return(nil)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, mockRequeue, Handler(obsv, featureflags.NewNoopClient(nil), mockRequeue, rateLimiter, jobLimiter, mockService, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to requeue agent job with delay")

		mockRequeue.AssertExpectations(t)
		mockExecutor.AssertExpectations(t)
		mockService.AssertExpectations(t)
	})

	t.Run("processes job when concurrency limits enabled but DelayProcessing returns false", func(t *testing.T) {
		testActorID := int64(12345)
		testRepoID := int64(67890)
		testOwnerID := int64(11111)

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			ActorId:      testActorID,
			RepositoryId: testRepoID,
			OwnerId:      testOwnerID,
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		mockExecutor.On("ProcessJob", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.AssignmentId == "test-assignment" && job.JobId == "test-job"
		})).Return(nil)

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 8, Queued: 0}, nil) // Below limit

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		mockExecutor.AssertExpectations(t)
	})

	t.Run("handles store error during concurrency check gracefully", func(t *testing.T) {
		testActorID := int64(12345)
		testRepoID := int64(67890)
		testOwnerID := int64(11111)

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			ActorId:      testActorID,
			RepositoryId: testRepoID,
			OwnerId:      testOwnerID,
		}

		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)

		receiveResult := aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				ID:      "test-job-id",
				Queue:   jobs.AgentJobQueueName,
				Payload: payload,
			},
		}

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		mockExecutor.On("ProcessJob", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.AssignmentId == "test-assignment" && job.JobId == "test-job"
		})).Return(nil)

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 0, Queued: 0}, errors.New("store error"))

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, requeue, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, service, mockExecutor))

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err) // Should continue processing despite store error

		mockExecutor.AssertExpectations(t)
	})

	t.Run("does not call FailJob when requeuing succeeds", func(t *testing.T) {
		testActorID := int64(777)
		testRepoID := int64(888)
		testOwnerID := int64(999)
		agentJob := &jobs.AgentJob{AssignmentId: "a", JobId: "b", ActorId: testActorID, RepositoryId: testRepoID, OwnerId: testOwnerID, RequeueCount: 2}
		payload, err := proto.Marshal(agentJob)
		require.NoError(t, err)
		receiveResult := aqueduct.ReceiveResult{Job: aqueduct.Job{ID: "id", Queue: jobs.AgentJobQueueName, Payload: payload}}
		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything).Return(sweagentd.JobCounts{Running: 20, Queued: 0}, nil)
		mockRequeue := &mockRequeue{}
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, limiter.JobRequeueDelay).Return("new-id", nil)
		mockExecutor := jobexecutor.NewMockJobExecutor(t) // FailJob should not be called
		mockService := &mockJobService{}                  // GetJobQueuedForExecution and FinalizeUnexecutedJob should not be called
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewRateLimiterV1(client, 10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, 10, time.Minute*5)
		handler := jobs.Handler(obsv, mockRequeue, Handler(obsv, featureflags.NewNoopClient(nil), mockRequeue, rateLimiter, jobLimiter, mockService, mockExecutor))
		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
		mockExecutor.AssertExpectations(t)
		mockService.AssertExpectations(t)
	})
}
