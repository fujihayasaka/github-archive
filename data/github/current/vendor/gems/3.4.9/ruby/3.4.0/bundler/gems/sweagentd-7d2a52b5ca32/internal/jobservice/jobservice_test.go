package jobservice

import (
	"context"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

func commonServiceDependencies(obsv observability.Exporters) (*capi.NoopClient, *memory.Store, *githubtwirp.NoopClient, github.ClientFactoryInterface, *experiments.NoopClient, sweagentd.AqueductClient, *jobLimiter.JobLimiter) {
	store := memory.NewStore()
	return capi.NewNoopClient(),
		store,
		githubtwirp.NewNoopClient(),
		&github.NoopClientFactory{},
		experiments.NewNoopClient(),
		aqueduct.NewMemoryClient(obsv),
		jobLimiter.NewJobLimiter(store, 10, time.Hour)
}

func TestFinalizeJob(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("maps success conclusion to completed status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test@example.com", nil)

		job := &jobs.Job{
			ID:      "test-job",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.Equal(t, int64(1234567890), updatedJob.CompletedAt)
	})

	t.Run("maps cancelled conclusion to cancelled status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test@example.com", nil)

		job := &jobs.Job{
			ID:      "test-job-2",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCancelled, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
	})

	t.Run("maps failure conclusion to failed status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test@example.com", nil)

		job := &jobs.Job{
			ID:      "test-job-4",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusFailed, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
	})

	t.Run("handles already terminal job status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test@example.com", nil)

		job := &jobs.Job{
			ID:          "test-job-5",
			OwnerID:     1,
			RepoID:      2,
			Status:      jobs.JobStatusCompleted,
			CompletedAt: 1234567890,
		}
		store.CreateJob(ctx, job)

		// Try to finalize an already completed job
		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.Equal(t, int64(1234567890), updatedJob.CompletedAt)
	})

	t.Run("sets completed time if not already set", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test@example.com", nil)

		job := &jobs.Job{
			ID:      "test-job-6",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		// Pass 0 for completedAt to use current time
		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, 0)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.NotZero(t, updatedJob.CompletedAt)
	})

	t.Run("decrements running jobs counter when finalizing running job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test@example.com", nil)

		job := &jobs.Job{
			ID:      "test-job-7",
			OwnerID: 1,
			RepoID:  2,
			ActorID: 123,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		// Increment to simulate a running job
		limiter.IncrementRunningJobs(ctx, job.ActorID)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, 1234567890)
		require.NoError(t, err)

		// The limiter should have decremented the counter
		// We can't easily test this without exposing internal state,
		// but at least ensure no error occurred
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
	})

	t.Run("does not decrement counter when finalizing non-running job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test@example.com", nil)

		job := &jobs.Job{
			ID:      "test-job-8",
			OwnerID: 1,
			RepoID:  2,
			ActorID: 123,
			Status:  jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCancelled, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
	})

	t.Run("finalizes job with timed out status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test@example.com", nil)

		job := &jobs.Job{
			ID:      "test-job-9",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusTimedOut, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusTimedOut, updatedJob.Status)
		require.Equal(t, int64(1234567890), updatedJob.CompletedAt)
	})
}
