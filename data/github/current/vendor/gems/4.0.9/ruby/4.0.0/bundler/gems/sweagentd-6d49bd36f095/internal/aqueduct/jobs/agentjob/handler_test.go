package agentjob

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/cache"
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

func (m *mockClient) RateLimitsForRepo(ctx context.Context, app sweagentd.AgenticApp, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
	args := m.Called(ctx, ownerID, repoID)
	return args.Get(0).(map[uint8]limiter.Rate), args.Error(1)
}

type mockStore struct {
	mock.Mock
}

func (m *mockStore) GetJobCountByStatusForActor(ctx context.Context, actor int64, window time.Duration, excludeAgentIDs []int64) (sweagentd.JobCounts, error) {
	args := m.Called(ctx, actor, window, excludeAgentIDs)
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

func (m *mockJobService) FinalizeUnexecutedJob(ctx context.Context, job *db.Job, status db.JobStatus, jobError *db.JobError) error {
	args := m.Called(ctx, job, status, jobError)
	return args.Error(0)
}

func TestJobHandler(t *testing.T) {
	obsv := observability.NewNoopExporters()

	executor := jobexecutor.NewNoopJobExecutor(obsv)

	t.Run("handles unknown queue gracefully", func(t *testing.T) {
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
		rateLimiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, service, executor), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		// Outer handler swallows the error to prevent Aqueduct NACK
		require.NoError(t, err)
	})

	t.Run("handles invalid job payload gracefully", func(t *testing.T) {
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
		rateLimiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, service, executor), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		// Outer handler swallows the error to prevent Aqueduct NACK
		require.NoError(t, err)
	})

	t.Run("requeues job when processing fails with transient error", func(t *testing.T) {
		// When ProcessJob returns a non-rate-limit error, the outer jobs.Handler
		// should catch it and requeue the job instead of passing it to Aqueduct
		// (which would NACK and silently drop it).

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
		store.On("GetJobCountByStatusForActor", mock.Anything, int64(0), mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 1, Queued: 0}, nil)

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		mockExecutor.On("ProcessJob", mock.Anything, mock.Anything).Return(errors.New("simulated transient error"))

		mockRequeue := &mockRequeue{}
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, jobs.TransientErrorRequeueDelay).Return("new-job-id", nil)

		service := &mockJobService{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, mockRequeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), mockRequeue, rateLimiter, jobLimiter, nil, service, mockExecutor), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)

		require.NoError(t, err)
		mockExecutor.AssertExpectations(t)
		mockRequeue.AssertExpectations(t)
	})

	t.Run("handles unmarshal error gracefully", func(t *testing.T) {
		// Invalid payload causes unmarshal error, but the outer handler swallows
		// it to prevent Aqueduct from NACKing the job.
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
		rateLimiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, service, executor), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err := handler(ctx, receiveResult)

		// Error is swallowed by the outer handler
		require.NoError(t, err)
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
		store.On("GetJobCountByStatusForActor", mock.Anything, int64(0), mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 1, Queued: 0}, nil)

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
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, service, mockExecutor), nil)

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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 1, Queued: 0}, nil)

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, service, mockExecutor), nil)

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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 1, Queued: 0}, nil)

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, ffClient, requeue, rateLimiter, jobLimiter, nil, service, mockExecutor), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		mockExecutor.AssertExpectations(t)
	})

	t.Run("resolves and sets agent slug when app provider is configured", func(t *testing.T) {
		const testAgentID = int64(12345)
		testActorID := int64(12345)
		testRepoID := int64(67890)
		testOwnerID := int64(11111)

		agentJob := &jobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			ActorId:      testActorID,
			RepositoryId: testRepoID,
			OwnerId:      testOwnerID,
			AgentId:      testAgentID,
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

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 1, Queued: 0}, nil)

		mockExecutor := jobexecutor.NewMockJobExecutor(t)
		var capturedCtx context.Context
		mockExecutor.On("ProcessJob", mock.MatchedBy(func(ctx context.Context) bool {
			capturedCtx = ctx //nolint:fatcontext // capturing context for test verification
			return true
		}), mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.JobId == "test-job"
		})).Return(nil)

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil).Maybe()
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentEmitAgentSlugTelemetry: true,
		})
		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		handler := Handler(obsv, ffClient, requeue, rateLimiter, jobLimiter, appProvider, service, mockExecutor)

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		agent, ok := requestctx.Agent(capturedCtx)
		require.True(t, ok)
		require.Equal(t, testAgentID, agent.ID)
		require.Equal(t, "copilot", agent.Slug)

		mockExecutor.AssertExpectations(t)
		client.AssertExpectations(t)
	})

	t.Run("fails job when ProcessJob error cannot be requeued", func(t *testing.T) {
		testActorID := int64(12345)
		expectedError := errors.New("job processing failed")
		requeueError := errors.New("requeue failed")

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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 1, Queued: 0}, nil)

		// Requeue fails — outer handler will try to requeue via handleTransientError
		mockRequeue := &mockRequeue{}
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, jobs.TransientErrorRequeueDelay).Return("", requeueError)

		// Expect job to be finalized as failed via failJob callback
		mockService := &mockJobService{}
		mockDBJob := &db.Job{ID: "test-job"}
		mockService.On("GetJobQueuedForExecution", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.JobId == "test-job"
		})).Return(mockDBJob, nil)
		mockService.On("FinalizeUnexecutedJob", mock.Anything, mockDBJob, db.JobStatusFailed, mock.MatchedBy(func(je *db.JobError) bool {
			return je.ResponseStatusCode == "queue_failure" && je.Service == "sweagentd"
		})).Return(nil)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, int64(0), int64(0)).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		failJobFunc := NewFailJobFunc(obsv, mockService)
		handler := jobs.Handler(obsv, mockRequeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), mockRequeue, rateLimiter, jobLimiter, nil, mockService, mockExecutor), failJobFunc)

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)

		mockExecutor.AssertExpectations(t)
		mockRequeue.AssertExpectations(t)
		mockService.AssertExpectations(t)
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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 20, Queued: 0}, nil)

		mockRequeue := &mockRequeue{}
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, limiter.JobRequeueDelay).Return("new-job-id", nil)

		service := &mockJobService{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, mockRequeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), mockRequeue, rateLimiter, jobLimiter, nil, service, mockExecutor), nil)

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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 1, Queued: 0}, nil) // Below limit

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, service, mockExecutor), nil)

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
			RequeueCount: jobs.AgentJobMaxRequeueCount + 1, // Above max requeue count
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
		mockDBJob := &db.Job{
			ID:      "test-job",
			OwnerID: testOwnerID,
			RepoID:  testRepoID,
		}
		mockService.On("GetJobQueuedForExecution", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.JobId == "test-job"
		})).Return(mockDBJob, nil)
		mockService.On("FinalizeUnexecutedJob", mock.Anything, mockDBJob, db.JobStatusFailed, mock.AnythingOfType("*jobs.JobError")).Return(nil)

		store := &mockStore{}
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 20, Queued: 0}, nil)

		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, mockService, mockExecutor), nil)

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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 20, Queued: 0}, nil)

		mockRequeue := &mockRequeue{}
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, limiter.JobRequeueDelay).Return("", expectedError)
		// The outer handler also attempts to requeue with its own delay
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, jobs.TransientErrorRequeueDelay).Return("new-job-id", nil)

		// Expect GetJobQueuedForExecution and FinalizeUnexecutedJob to be called when requeue fails
		mockService := &mockJobService{}
		mockDBJob := &db.Job{
			ID:      "test-job",
			OwnerID: testOwnerID,
			RepoID:  testRepoID,
		}
		mockService.On("GetJobQueuedForExecution", mock.Anything, mock.MatchedBy(func(job *jobs.AgentJob) bool {
			return job.JobId == "test-job"
		})).Return(mockDBJob, nil)
		mockService.On("FinalizeUnexecutedJob", mock.Anything, mockDBJob, db.JobStatusFailed, mock.AnythingOfType("*jobs.JobError")).Return(nil)

		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, mockRequeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), mockRequeue, rateLimiter, jobLimiter, nil, mockService, mockExecutor), nil)

		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		// Outer handler swallows the error
		require.NoError(t, err)

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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 1, Queued: 0}, nil) // Below limit

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, service, mockExecutor), nil)

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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 0, Queued: 0}, errors.New("store error"))

		service := &mockJobService{}
		requeue := &mockRequeue{}
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, requeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), requeue, rateLimiter, jobLimiter, nil, service, mockExecutor), nil)

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
		store.On("GetJobCountByStatusForActor", mock.Anything, testActorID, mock.Anything, mock.Anything).Return(sweagentd.JobCounts{Running: 20, Queued: 0}, nil)
		mockRequeue := &mockRequeue{}
		mockRequeue.On("RequeueJobWithDelay", mock.Anything, mock.Anything, limiter.JobRequeueDelay).Return("new-id", nil)
		mockExecutor := jobexecutor.NewMockJobExecutor(t) // FailJob should not be called
		mockService := &mockJobService{}                  // GetJobQueuedForExecution and FinalizeUnexecutedJob should not be called
		client := &mockClient{}
		client.On("RateLimitsForRepo", mock.Anything, testOwnerID, testRepoID).Return(map[uint8]limiter.Rate{}, nil)
		rateLimiter := limiter.NewCacheRateLimiter(client, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
		countTracker := limiter.NewJobCountMemoryTracker(10, time.Minute*5)
		jobLimiter := limiter.NewJobLimiter(store, countTracker, nil)
		handler := jobs.Handler(obsv, mockRequeue, featureflags.NewNoopClient(nil), nil, Handler(obsv, featureflags.NewNoopClient(nil), mockRequeue, rateLimiter, jobLimiter, nil, mockService, mockExecutor), nil)
		ctx := requestctx.NewContext(context.Background())
		_, err = handler(ctx, receiveResult)
		require.NoError(t, err)
		mockRequeue.AssertExpectations(t)
		mockExecutor.AssertExpectations(t)
		mockService.AssertExpectations(t)
	})
}
