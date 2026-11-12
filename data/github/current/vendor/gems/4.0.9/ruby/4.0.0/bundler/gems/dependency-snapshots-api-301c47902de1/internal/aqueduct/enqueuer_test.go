package aqueduct

import (
	"context"
	"testing"

	"github.com/avast/retry-go/v4"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	enqueuermock "github.com/github/dependency-snapshots-api/internal/aqueduct/mock"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Test helper functions

// newTestConfig creates a test config with a given app name
func newTestConfig(appName string) *config.Config {
	return &config.Config{
		AqueductAppName: appName,
	}
}

// newTestEchoJob creates a sample EchoJob for testing
func newTestEchoJob(message string) *jobs.EchoJob {
	return &jobs.EchoJob{
		Message: message,
		SentAt:  timestamppb.Now(),
	}
}

// newTestEnqueuer creates a JobEnqueuer with test defaults
func newTestEnqueuer(mockClient *enqueuermock.MockedAqueductClient, opts ...retry.Option) *JobEnqueuer {
	return NewJobEnqueuer(newTestConfig("test-app"), mockClient, stats.NullStatter, opts...)
}

// fastRetryOptions returns retry options optimized for fast test execution
func fastRetryOptions(attempts uint) []retry.Option {
	return []retry.Option{
		retry.Attempts(attempts),
		retry.Delay(0),
	}
}

func TestQueueForJob(t *testing.T) {
	tests := []struct {
		job       proto.Message
		wantQueue string
		wantErr   bool
	}{
		{
			job:       &jobs.EchoJob{},
			wantQueue: EchoQueue,
			wantErr:   false,
		},
		{
			job:       &jobs.ExcludeCanonicalSnapshotsJob{},
			wantQueue: ExcludeCanonicalSnapshotsQueue,
			wantErr:   false,
		},
		{
			job:       &jobs.DependabotSnapshotInitJob{},
			wantQueue: DependabotSnapshotInitQueue,
			wantErr:   false,
		},
		{
			job:       &jobs.DependabotSnapshotPostPushJob{},
			wantQueue: DependabotSnapshotPostPushQueue,
			wantErr:   false,
		},
		{
			job:       &jobs.UpdateGraphComputeUsageJob{},
			wantQueue: UpdateGraphComputeUsageQueue,
			wantErr:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.wantQueue, func(t *testing.T) {
			queue, err := QueueForJob(tt.job)
			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.wantQueue, queue)
			}
		})
	}

	t.Run("unknown job type returns error", func(t *testing.T) {
		// Use a different protobuf message type that isn't registered
		type unknownJob struct {
			proto.Message
		}
		_, err := QueueForJob(&unknownJob{})
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unknown job type")
	})
}

func TestJobForQueue(t *testing.T) {
	tests := []struct {
		queue    string
		wantType proto.Message
		wantErr  bool
	}{
		{
			queue:    EchoQueue,
			wantType: &jobs.EchoJob{},
			wantErr:  false,
		},
		{
			queue:    ExcludeCanonicalSnapshotsQueue,
			wantType: &jobs.ExcludeCanonicalSnapshotsJob{},
			wantErr:  false,
		},
		{
			queue:    DependabotSnapshotInitQueue,
			wantType: &jobs.DependabotSnapshotInitJob{},
			wantErr:  false,
		},
		{
			queue:    DependabotSnapshotPostPushQueue,
			wantType: &jobs.DependabotSnapshotPostPushJob{},
			wantErr:  false,
		},
		{
			queue:    UpdateGraphComputeUsageQueue,
			wantType: &jobs.UpdateGraphComputeUsageJob{},
			wantErr:  false,
		},
		{
			queue:    "unknown-queue",
			wantType: nil,
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.queue, func(t *testing.T) {
			job, err := JobForQueue(tt.queue)
			if tt.wantErr {
				require.Error(t, err)
				assert.Nil(t, job)
			} else {
				require.NoError(t, err)
				assert.IsType(t, tt.wantType, job)
			}
		})
	}
}

func TestJobEnqueuer_Enqueue(t *testing.T) {
	t.Run("successfully enqueues job", func(t *testing.T) {
		mockClient := &enqueuermock.MockedAqueductClient{}
		mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).Return("job-123", nil)

		enqueuer := newTestEnqueuer(mockClient)
		job := newTestEchoJob("test message")

		jobID, err := enqueuer.Enqueue(context.Background(), job)

		require.NoError(t, err)
		assert.Equal(t, "job-123", jobID)
		mockClient.AssertExpectations(t)
	})

	t.Run("returns error when aqueduct send fails", func(t *testing.T) {
		mockClient := &enqueuermock.MockedAqueductClient{}
		mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).
			Return("", errors.New("send failure"))

		enqueuer := newTestEnqueuer(mockClient, fastRetryOptions(1)...)
		job := newTestEchoJob("test message")

		jobID, err := enqueuer.Enqueue(context.Background(), job)

		require.Error(t, err)
		assert.Empty(t, jobID)
		assert.Contains(t, err.Error(), "failed to enqueue job")
		mockClient.AssertExpectations(t)
	})
}

func TestJobEnqueuer_EnqueueWithRoute(t *testing.T) {
	t.Run("successfully enqueues job to custom queue", func(t *testing.T) {
		customQueue := "custom-queue"
		job := newTestEchoJob("test message")
		bytes, _ := proto.Marshal(job)

		mockClient := &enqueuermock.MockedAqueductClient{}
		mockClient.On("Send",
			mock.Anything,
			aqueduct.Job{
				App:     "test-app",
				Queue:   customQueue,
				Payload: bytes,
				Headers: map[string]string{},
			},
			mock.Anything,
		).Return("job-123", nil)

		enqueuer := newTestEnqueuer(mockClient)
		jobID, err := enqueuer.EnqueueWithRoute(context.Background(), job, customQueue)

		require.NoError(t, err)
		assert.Equal(t, "job-123", jobID)
		mockClient.AssertExpectations(t)
	})

	t.Run("sets headers correctly", func(t *testing.T) {
		job := newTestEchoJob("test message")
		bytes, _ := proto.Marshal(job)

		mockClient := &enqueuermock.MockedAqueductClient{}
		mockClient.On("Send",
			mock.Anything,
			aqueduct.Job{
				App:     "my-app",
				Queue:   EchoQueue,
				Payload: bytes,
				Headers: map[string]string{
					"X-GitHub-Tenant":    "my-tenant",
					"X-GitHub-Tenant-ID": "tenant-001",
				},
			},
			mock.Anything,
		).Return("job-123", nil)

		cfg := newTestConfig("my-app")
		enqueuer := NewJobEnqueuer(cfg, mockClient, stats.NullStatter)

		ctx := context.Background()
		ctx = tenant.TenantContext(ctx, "my-tenant")
		ctx = tenant.TenantIDContext(ctx, "tenant-001")

		jobID, err := enqueuer.EnqueueWithRoute(ctx, job, EchoQueue)

		require.NoError(t, err)
		assert.Equal(t, "job-123", jobID)
		mockClient.AssertExpectations(t)
	})
}

func TestJobEnqueuer_EnqueueWithRetry(t *testing.T) {
	t.Run("retries on failure and eventually succeeds", func(t *testing.T) {
		mockClient := &enqueuermock.MockedAqueductClient{}
		mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).
			Return("", errors.New("failed")).Twice()
		mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).
			Return("job-123", nil).Once()

		enqueuer := newTestEnqueuer(mockClient, fastRetryOptions(3)...)
		job := newTestEchoJob("test message")

		jobID, err := enqueuer.Enqueue(context.Background(), job)

		require.NoError(t, err)
		assert.Equal(t, "job-123", jobID)
		mockClient.AssertExpectations(t)
		mockClient.AssertNumberOfCalls(t, "Send", 3)
	})

	t.Run("fails after exhausting retries", func(t *testing.T) {
		mockClient := &enqueuermock.MockedAqueductClient{}
		mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).
			Return("", errors.New("failed")).Twice()

		enqueuer := newTestEnqueuer(mockClient, fastRetryOptions(2)...)
		job := newTestEchoJob("test message")

		jobID, err := enqueuer.Enqueue(context.Background(), job)

		require.Error(t, err)
		assert.Empty(t, jobID)
		assert.Contains(t, err.Error(), "failed to enqueue job")
		mockClient.AssertExpectations(t)
	})
}

func TestJobEnqueuer_ContextCancellation(t *testing.T) {
	t.Run("respects context cancellation", func(t *testing.T) {
		mockClient := &enqueuermock.MockedAqueductClient{}
		enqueuer := newTestEnqueuer(mockClient, fastRetryOptions(5)...)
		job := newTestEchoJob("test message")

		// Create a cancelled context
		ctx, cancel := context.WithCancel(context.Background())
		cancel()

		jobID, err := enqueuer.Enqueue(ctx, job)

		require.Error(t, err)
		assert.Empty(t, jobID)
		assert.Contains(t, err.Error(), "context canceled")
	})
}
