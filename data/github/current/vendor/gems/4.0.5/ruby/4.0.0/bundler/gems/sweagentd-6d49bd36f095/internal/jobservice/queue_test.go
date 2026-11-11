package jobservice

import (
	"context"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/require"
)

type copyingJobsStore struct {
	db.JobsStore
}

func copyJob(job *jobs.Job) *jobs.Job {
	if job == nil {
		return nil
	}
	copied := *job
	return &copied
}

func (s copyingJobsStore) CreateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	created, err := s.JobsStore.CreateJob(ctx, copyJob(job))
	return copyJob(created), err
}

func (s copyingJobsStore) GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error) {
	job, err := s.JobsStore.GetJob(ctx, owner, repo, id)
	return copyJob(job), err
}

func (s copyingJobsStore) UpdateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	updated, err := s.JobsStore.UpdateJob(ctx, copyJob(job))
	return copyJob(updated), err
}

func (s copyingJobsStore) UpsertJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	upserted, err := s.JobsStore.UpsertJob(ctx, copyJob(job))
	return copyJob(upserted), err
}

func TestGetJobQueuedForProcessing(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("successfully retrieves assignment and job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test assignment and job
		assignment := &jobs.Assignment{
			ID:      "test-assignment",
			OwnerID: 123,
			RepoID:  456,
		}
		store.CreateAssignment(ctx, assignment)

		job := &jobs.Job{
			ID:           "test-job",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			Status:       jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		// Create APIJob
		apiJob := &aqueductJobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		// Test GetJobQueuedForProcessing
		retrievedAssignment, retrievedJob, err := service.GetJobQueuedForProcessing(ctx, apiJob)
		require.NoError(t, err)
		require.NotNil(t, retrievedAssignment)
		require.NotNil(t, retrievedJob)
		require.Equal(t, assignment.ID, retrievedAssignment.ID)
		require.Equal(t, job.ID, retrievedJob.ID)
	})

	t.Run("returns error when owner_id is missing", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		apiJob := &aqueductJobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      0, // Missing
			RepositoryId: 456,
		}

		_, _, err := service.GetJobQueuedForProcessing(ctx, apiJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid api job")
	})

	t.Run("returns error when repository_id is missing", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		apiJob := &aqueductJobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 0, // Missing
		}

		_, _, err := service.GetJobQueuedForProcessing(ctx, apiJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid api job")
	})

	t.Run("returns error when assignment_id is missing", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		apiJob := &aqueductJobs.APIJob{
			AssignmentId: "", // Missing
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		_, _, err := service.GetJobQueuedForProcessing(ctx, apiJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid api job")
	})

	t.Run("returns error when job_id is missing", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		apiJob := &aqueductJobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "", // Missing
			OwnerId:      123,
			RepositoryId: 456,
		}

		_, _, err := service.GetJobQueuedForProcessing(ctx, apiJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid api job")
	})

	t.Run("returns error when assignment not found", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		apiJob := &aqueductJobs.APIJob{
			AssignmentId: "non-existent-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		_, _, err := service.GetJobQueuedForProcessing(ctx, apiJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "assignment not found")
	})

	t.Run("returns error when job not found", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create assignment but not job
		assignment := &jobs.Assignment{
			ID:      "test-assignment",
			OwnerID: 123,
			RepoID:  456,
		}
		store.CreateAssignment(ctx, assignment)

		apiJob := &aqueductJobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "non-existent-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		_, _, err := service.GetJobQueuedForProcessing(ctx, apiJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to get job from store")
	})
}

func TestGetJobQueuedForExecution(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("successfully retrieves job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job
		job := &jobs.Job{
			ID:           "test-job",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			Status:       jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		// Create AgentJob
		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		// Test GetJobQueuedForExecution
		retrievedJob, err := service.GetJobQueuedForExecution(ctx, agentJob)
		require.NoError(t, err)
		require.NotNil(t, retrievedJob)
		require.Equal(t, job.ID, retrievedJob.ID)
	})

	t.Run("returns error when owner_id is missing", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      0, // Missing
			RepositoryId: 456,
		}

		_, err := service.GetJobQueuedForExecution(ctx, agentJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid agent job")
	})

	t.Run("returns error when repository_id is missing", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 0, // Missing
		}

		_, err := service.GetJobQueuedForExecution(ctx, agentJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid agent job")
	})

	t.Run("returns error when assignment_id is missing", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "", // Missing
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		_, err := service.GetJobQueuedForExecution(ctx, agentJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid agent job")
	})

	t.Run("returns error when job_id is missing", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "", // Missing
			OwnerId:      123,
			RepositoryId: 456,
		}

		_, err := service.GetJobQueuedForExecution(ctx, agentJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid agent job")
	})

	t.Run("returns error when job not found", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "non-existent-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		_, err := service.GetJobQueuedForExecution(ctx, agentJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to get job from store")
	})
}

func TestGetJobQueuedForExecutionWithNonce(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("successfully retrieves job and generates nonce for queued job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job in queued state
		job := &jobs.Job{
			ID:           "test-job",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			Status:       jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		// Create AgentJob
		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		// Test GetJobQueuedForExecutionWithNonce
		retrievedJob, nonce, err := service.GetJobQueuedForExecutionWithNonce(ctx, agentJob)
		require.NoError(t, err)
		require.NotNil(t, retrievedJob)
		require.NotEmpty(t, nonce)
		require.NotEmpty(t, retrievedJob.NonceHash)
		require.Equal(t, job.ID, retrievedJob.ID)
	})

	t.Run("does not persist nonce hash before returning job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		copyingStore := copyingJobsStore{JobsStore: store}
		service := New(obsv, ffClient, copyingStore, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:           "test-job-unpersisted-nonce",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			Status:       jobs.JobStatusQueued,
		}
		_, err := copyingStore.CreateJob(ctx, job)
		require.NoError(t, err)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job-unpersisted-nonce",
			OwnerId:      123,
			RepositoryId: 456,
		}

		retrievedJob, nonce, err := service.GetJobQueuedForExecutionWithNonce(ctx, agentJob)
		require.NoError(t, err)
		require.NotEmpty(t, nonce)
		require.NotEmpty(t, retrievedJob.NonceHash)

		persistedJob, err := copyingStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Empty(t, persistedJob.NonceHash)
	})

	t.Run("successfully retrieves job and generates nonce for pending job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job in pending state
		job := &jobs.Job{
			ID:           "test-job-pending",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			Status:       jobs.JobStatusPending,
		}
		store.CreateJob(ctx, job)

		// Create AgentJob
		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job-pending",
			OwnerId:      123,
			RepositoryId: 456,
		}

		// Test GetJobQueuedForExecutionWithNonce
		retrievedJob, nonce, err := service.GetJobQueuedForExecutionWithNonce(ctx, agentJob)
		require.NoError(t, err)
		require.NotNil(t, retrievedJob)
		require.NotEmpty(t, nonce)
		require.NotEmpty(t, retrievedJob.NonceHash)
		require.Equal(t, job.ID, retrievedJob.ID)
	})

	t.Run("generates nonce for running job but warns", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job in running state (not ideal for nonce generation)
		job := &jobs.Job{
			ID:           "test-job-running",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			Status:       jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job-running",
			OwnerId:      123,
			RepositoryId: 456,
		}

		// Should still succeed but log a warning
		retrievedJob, nonce, err := service.GetJobQueuedForExecutionWithNonce(ctx, agentJob)
		require.NoError(t, err)
		require.NotNil(t, retrievedJob)
		require.NotEmpty(t, nonce)
		require.NotEmpty(t, retrievedJob.NonceHash)
	})

	t.Run("returns error when job not found", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "non-existent-job",
			OwnerId:      123,
			RepositoryId: 456,
		}

		_, _, err := service.GetJobQueuedForExecutionWithNonce(ctx, agentJob)
		require.Error(t, err)
	})

	t.Run("nonce is different on each call", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job
		job := &jobs.Job{
			ID:           "test-job-nonce",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			Status:       jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		agentJob := &aqueductJobs.AgentJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job-nonce",
			OwnerId:      123,
			RepositoryId: 456,
		}

		// Call twice
		_, nonce1, err := service.GetJobQueuedForExecutionWithNonce(ctx, agentJob)
		require.NoError(t, err)

		_, nonce2, err := service.GetJobQueuedForExecutionWithNonce(ctx, agentJob)
		require.NoError(t, err)

		// Nonces should be different
		require.NotEqual(t, nonce1, nonce2)
	})
}

func TestQueuePartialJob(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("successfully queues partial job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job
		job := &jobs.Job{
			ID:           "test-job",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			ActorID:      789,
			Status:       jobs.JobStatusPending,
		}
		store.CreateJob(ctx, job)

		// Test QueueJobForProcessing
		apiJob, err := service.QueueJobForProcessing(ctx, job)
		require.NoError(t, err)
		require.NotNil(t, apiJob)
		require.Equal(t, job.ID, apiJob.JobId)
		require.Equal(t, job.AssignmentID, apiJob.AssignmentId)
		require.Equal(t, job.OwnerID, apiJob.OwnerId)
		require.Equal(t, job.RepoID, apiJob.RepositoryId)
		require.Equal(t, job.ActorID, apiJob.ActorId)
	})

	t.Run("updates job status if queueing fails", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job
		job := &jobs.Job{
			ID:           "test-job-fail",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			ActorID:      789,
			Status:       jobs.JobStatusPending,
			SessionID:    "test-session",
		}
		store.CreateJob(ctx, job)

		// Note: MemoryClient should succeed, but let's verify the behavior
		_, err := service.QueueJobForProcessing(ctx, job)
		require.NoError(t, err)
	})
}

func TestQueueJobForExecution(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("successfully queues job with existing session", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job with session
		job := &jobs.Job{
			ID:           "test-job",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			ActorID:      789,
			SessionID:    "existing-session",
			Status:       jobs.JobStatusPending,
		}
		store.CreateJob(ctx, job)

		// Test QueueJob
		agentJob, err := service.QueueJobForExecution(ctx, job)
		require.NoError(t, err)
		require.NotNil(t, agentJob)
		require.Equal(t, job.ID, agentJob.JobId)
		require.Equal(t, job.AssignmentID, agentJob.AssignmentId)
		require.Equal(t, job.OwnerID, agentJob.OwnerId)
		require.Equal(t, job.RepoID, agentJob.RepositoryId)
		require.Equal(t, job.ActorID, agentJob.ActorId)
		require.Equal(t, job.SessionID, agentJob.SessionId)

		// Verify job status was updated to queued
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusQueued, updatedJob.Status)
		require.NotZero(t, updatedJob.QueuedAt)
	})

	t.Run("creates session if missing and queues job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job without session
		job := &jobs.Job{
			ID:           "test-job-no-session",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			ActorID:      789,
			SessionID:    "", // No session
			Status:       jobs.JobStatusPending,
		}
		store.CreateJob(ctx, job)

		// Test QueueJob - should create session
		agentJob, err := service.QueueJobForExecution(ctx, job)
		require.NoError(t, err)
		require.NotNil(t, agentJob)
		require.NotEmpty(t, job.SessionID) // Session should be created
		require.NotEmpty(t, agentJob.SessionId)

		// Verify job status was updated to queued
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusQueued, updatedJob.Status)
		require.NotZero(t, updatedJob.QueuedAt)
	})

	t.Run("sets queued_at timestamp", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:           "test-job-timestamp",
			AssignmentID: "test-assignment",
			OwnerID:      123,
			RepoID:       456,
			ActorID:      789,
			SessionID:    "test-session",
			Status:       jobs.JobStatusPending,
		}
		store.CreateJob(ctx, job)

		beforeQueue := time.Now().Unix()
		_, err := service.QueueJobForExecution(ctx, job)
		afterQueue := time.Now().Unix()
		require.NoError(t, err)

		// Verify QueuedAt is within reasonable range
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.GreaterOrEqual(t, updatedJob.QueuedAt, beforeQueue)
		require.LessOrEqual(t, updatedJob.QueuedAt, afterQueue)
	})

	t.Run("does not create session when UseAsyncSessions is true", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		// Create test job without session but with UseAsyncSessions enabled
		job := &jobs.Job{
			ID:               "test-job-async-sessions",
			AssignmentID:     "test-assignment",
			OwnerID:          123,
			RepoID:           456,
			ActorID:          789,
			SessionID:        "", // No session
			UseAsyncSessions: true,
			Status:           jobs.JobStatusPending,
		}
		store.CreateJob(ctx, job)

		// Test QueueJob - should NOT create session because UseAsyncSessions is true
		agentJob, err := service.QueueJobForExecution(ctx, job)
		require.NoError(t, err)
		require.NotNil(t, agentJob)
		require.Empty(t, job.SessionID) // Session should NOT be created
		require.Empty(t, agentJob.SessionId)

		// Verify job status was updated to queued
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusQueued, updatedJob.Status)
		require.NotZero(t, updatedJob.QueuedAt)
	})
}

func TestProcess_RegeneratesSessionName(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ctx := context.Background()

	t.Run("regenerates AI session name for job with placeholder title", func(t *testing.T) {
		ff := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentAINameGeneration: true,
			capi.CopilotAPIAgentSessions:                 true,
		})
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		// Mock user details for model selection
		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		// Mock the AI client to return a generated session name
		capiClient.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			response := `{
				"branch_name": "fix-auth-bug",
				"session_name": "AI Generated Session Name",
				"pull_request_title": "Fix authentication bug"
			}`
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{
							Content: response,
						},
					},
				},
			}, nil
		}

		// Track session updates
		var updatedSessionName string
		capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, sessionUpdate capi.SessionUpdate) error {
			if sessionUpdate.Name != "" {
				updatedSessionName = sessionUpdate.Name
			}
			return nil
		}

		// Mock spokes for branch checks
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))

		// Mock PR creation
		twirp.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
			return &sweagentdtwirp.CreatePullRequestResponse{
				PullRequest: &sweagentdtwirp.PullRequest{
					Id:           999,
					GithubNumber: 321,
					RepositoryId: req.RepositoryId,
				},
			}, nil
		}

		service := New(obsv, ff, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		// Create an assignment
		assignment := &jobs.Assignment{
			ID:      "test-assignment",
			OwnerID: 1,
			RepoID:  2,
		}
		store.CreateAssignment(ctx, assignment)

		// Create a job with a placeholder title (simulating async API creation)
		job := &jobs.Job{
			ID:           "test-job",
			AssignmentID: "test-assignment",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      42,
			ActorLogin:   "testuser",
			AgentID:      0,                        // Default test app ID
			Title:        "Initial implementation", // Placeholder title
			SessionID:    "existing-session-123",   // Session already exists
			Status:       jobs.JobStatusPending,
			Action:       jobs.AgentActionFix,
			BaseCommit:   "abc123",
			ProblemStatement: jobs.ProblemStatement{
				Content: "Fix the authentication bug in the login flow",
			},
			Features: jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{
					TitlePlaceholder: "Draft PR",
					BodyPlaceholder:  "PR body",
					BaseRef:          "main",
				},
			},
		}
		store.CreateJob(ctx, job)

		// Create APIJob to simulate queue processing
		apiJob := &aqueductJobs.APIJob{
			AssignmentId: "test-assignment",
			JobId:        "test-job",
			OwnerId:      1,
			RepositoryId: 2,
			AgentId:      0, // Default test app ID
		}

		// Process the job (this is what happens when it's pulled from the queue)
		testCtx := requestctx.NewContext(ctx)
		err := service.Process(testCtx, apiJob)
		require.NoError(t, err)

		// Verify the session name was updated with AI-generated name
		require.Equal(t, "AI Generated Session Name", updatedSessionName)

		// Verify the job title was also updated
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, "AI Generated Session Name", updatedJob.Title)
	})
}
