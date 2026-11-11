package jobservice

import (
	"context"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/jobevents"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/launcher"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/runnerlabels"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

//nolint:gocritic // only for test code
func commonServiceDependencies(obsv observability.Exporters) (*capi.NoopClient, *memory.Store, *githubtwirp.NoopClient, github.ClientFactoryInterface, *experiments.NoopClient, sweagentd.AqueductClient, *jobLimiter.JobLimiter) {
	store := memory.NewStore()
	countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
	return capi.NewNoopClient(),
		store,
		githubtwirp.NewNoopClient(),
		&github.NoopClientFactory{},
		experiments.NewNoopClient(),
		aqueduct.NewMemoryClient(obsv),
		jobLimiter.NewJobLimiter(store, countTracker, nil)
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
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-job",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, nil, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.Equal(t, int64(1234567890), updatedJob.CompletedAt)
	})

	t.Run("maps cancelled conclusion to cancelled status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-job-2",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCancelled, nil, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
	})

	t.Run("maps failure conclusion to failed status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-job-4",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusFailed, nil, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
	})

	t.Run("handles already terminal job status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:          "test-job-5",
			OwnerID:     1,
			RepoID:      2,
			Status:      jobs.JobStatusCompleted,
			CompletedAt: 1234567890,
		}
		store.CreateJob(ctx, job)

		// Try to finalize an already completed job
		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, nil, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.Equal(t, int64(1234567890), updatedJob.CompletedAt)
	})

	t.Run("sets completed time if not already set", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-job-6",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		// Pass 0 for completedAt to use current time
		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, nil, 0)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.NotZero(t, updatedJob.CompletedAt)
	})

	t.Run("decrements running jobs counter when finalizing running job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-job-7",
			OwnerID: 1,
			RepoID:  2,
			ActorID: 123,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		// Increment to simulate a running job
		limiter.IncrementRunningJobs(ctx, job.ActorID, job.AgentID)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, nil, 1234567890)
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
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-job-8",
			OwnerID: 1,
			RepoID:  2,
			ActorID: 123,
			Status:  jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCancelled, nil, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
	})

	t.Run("finalizes job with timed out status", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-job-9",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusTimedOut, nil, 1234567890)
		require.NoError(t, err)

		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusTimedOut, updatedJob.Status)
		require.Equal(t, int64(1234567890), updatedJob.CompletedAt)
	})
}

func TestService_UpdateFromExecutionResult(t *testing.T) {
	tests := []struct {
		name                 string
		initialStatus        jobs.JobStatus
		initialStartedAt     int64
		newStatus            jobs.JobStatus
		expectStatusPatch    bool
		expectStartedAtPatch bool
		expectPatchCall      bool
	}{
		{
			name:                 "update status - non-terminal, first execution",
			initialStatus:        jobs.JobStatusQueued,
			initialStartedAt:     0,
			newStatus:            jobs.JobStatusRunning,
			expectStatusPatch:    true,
			expectStartedAtPatch: true,
			expectPatchCall:      true,
		},
		{
			name:             "update status - non-terminal, not first execution",
			initialStatus:    jobs.JobStatusRunning,
			initialStartedAt: time.Now().Unix() - 100,
			newStatus:        jobs.JobStatusRunning,
			expectPatchCall:  false, // Same status, no change
		},
		{
			name:             "terminal status - should not patch",
			initialStatus:    jobs.JobStatusQueued,
			initialStartedAt: 0,
			newStatus:        jobs.JobStatusCompleted,
			expectPatchCall:  false,
		},
		{
			name:                 "different status - non-terminal, already started",
			initialStatus:        jobs.JobStatusQueued,
			initialStartedAt:     time.Now().Unix() - 100,
			newStatus:            jobs.JobStatusRunning,
			expectStatusPatch:    true,
			expectStartedAtPatch: false, // Already started
			expectPatchCall:      true,
		},
		{
			name:                 "same status with StartedAt 0 - should set StartedAt only",
			initialStatus:        jobs.JobStatusRunning,
			initialStartedAt:     0,
			newStatus:            jobs.JobStatusRunning,
			expectStatusPatch:    false, // Same status
			expectStartedAtPatch: true,  // First execution
			expectPatchCall:      true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()

			// Create a memory store for testing
			store := memory.NewStore()
			obsv := observability.NewNoopExporters()

			service := &Service{
				store:        store,
				obsv:         obsv,
				eventEmitter: &noopJobEventEmitter{},
			}

			// Create a test job
			job := &jobs.Job{
				ID:         "test-job-id",
				OwnerID:    123,
				RepoID:     456,
				ActorID:    789,
				Status:     tt.initialStatus,
				StartedAt:  tt.initialStartedAt,
				LaunchedAt: time.Now().Unix() - 300, // 5 minutes ago
				CreatedAt:  time.Now().Unix() - 600, // 10 minutes ago
			}

			// Save the job to the store first
			_, err := store.CreateJob(ctx, job)
			require.NoError(t, err)

			// Keep track of original values
			originalStatus := job.Status
			originalStartedAt := job.StartedAt

			err = service.UpdateFromExecutionResult(ctx, job, tt.newStatus, time.Time{})
			require.NoError(t, err)

			// Verify the job object was updated correctly
			if tt.expectStatusPatch {
				require.Equal(t, tt.newStatus, job.Status, "Job status should be updated")
			} else {
				require.Equal(t, originalStatus, job.Status, "Job status should not be changed")
			}

			if tt.expectStartedAtPatch {
				require.Greater(t, job.StartedAt, int64(0), "Job StartedAt should be set")
				require.NotEqual(t, originalStartedAt, job.StartedAt, "Job StartedAt should be changed")
			} else {
				require.Equal(t, originalStartedAt, job.StartedAt, "Job StartedAt should not be changed")
			}

			// If we expected a patch call, verify the job was actually updated in the store
			if tt.expectPatchCall {
				// Retrieve the job from the store to verify it was persisted
				storedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
				require.NoError(t, err)

				if tt.expectStatusPatch {
					require.Equal(t, tt.newStatus, storedJob.Status, "Stored job status should be updated")
				}

				if tt.expectStartedAtPatch {
					require.Greater(t, storedJob.StartedAt, int64(0), "Stored job StartedAt should be set")
				}
			}
		})
	}
}

func TestService_UpdateFromExecutionResult_ErrorHandling(t *testing.T) {
	ctx := context.Background()

	// Create a memory store for testing
	store := memory.NewStore()
	obsv := observability.NewNoopExporters()

	service := &Service{
		store: store,
		obsv:  obsv,
	}

	// Create a test job but don't save it to the store (to trigger an error)
	job := &jobs.Job{
		ID:      "non-existent-job",
		OwnerID: 123,
		RepoID:  456,
		Status:  jobs.JobStatusQueued,
	}

	newStatus := jobs.JobStatusRunning

	// This should return an error because the job doesn't exist in the store
	err := service.UpdateFromExecutionResult(ctx, job, newStatus, time.Time{})
	require.Error(t, err)
	require.Contains(t, err.Error(), "failed to patch job")
}

func TestService_UpdateFromExecutionResult_RunningAt(t *testing.T) {
	tests := []struct {
		name                 string
		initialStatus        jobs.JobStatus
		initialStartedAt     int64
		initialRunningAt     int64
		newStatus            jobs.JobStatus
		runningAt            time.Time
		expectRunningAtPatch bool
		expectPatchCall      bool
	}{
		{
			name:                 "tool call - first tool call sets RunningAt",
			initialStatus:        jobs.JobStatusRunning,
			initialStartedAt:     time.Now().Unix() - 100,
			initialRunningAt:     0,
			newStatus:            jobs.JobStatusRunning,
			runningAt:            time.Now().UTC(),
			expectRunningAtPatch: true,
			expectPatchCall:      true,
		},
		{
			name:                 "tool call - RunningAt already set",
			initialStatus:        jobs.JobStatusRunning,
			initialStartedAt:     time.Now().Unix() - 100,
			initialRunningAt:     time.Now().Unix() - 50,
			newStatus:            jobs.JobStatusRunning,
			runningAt:            time.Now().UTC(),
			expectRunningAtPatch: false,
			expectPatchCall:      false, // Nothing to update
		},
		{
			name:                 "no runningAt provided - should not set RunningAt",
			initialStatus:        jobs.JobStatusRunning,
			initialStartedAt:     time.Now().Unix() - 100,
			initialRunningAt:     0,
			newStatus:            jobs.JobStatusRunning,
			runningAt:            time.Time{},
			expectRunningAtPatch: false,
			expectPatchCall:      false, // Nothing to update
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()

			// Create a memory store for testing
			store := memory.NewStore()
			obsv := observability.NewNoopExporters()

			service := &Service{
				store: store,
				obsv:  obsv,
			}

			// Create and persist a test job
			job := &jobs.Job{
				ID:        "test-job-id",
				OwnerID:   123,
				RepoID:    456,
				Status:    tt.initialStatus,
				StartedAt: tt.initialStartedAt,
				RunningAt: tt.initialRunningAt,
			}

			_, err := store.CreateJob(ctx, job)
			require.NoError(t, err)

			// Keep track of original value
			originalRunningAt := job.RunningAt

			err = service.UpdateFromExecutionResult(ctx, job, tt.newStatus, tt.runningAt)
			require.NoError(t, err)

			if tt.expectRunningAtPatch {
				require.Greater(t, job.RunningAt, int64(0), "Job RunningAt should be set")
				require.NotEqual(t, originalRunningAt, job.RunningAt, "Job RunningAt should be changed")
			} else {
				require.Equal(t, originalRunningAt, job.RunningAt, "Job RunningAt should not be changed")
			}

			// Verify the job was actually updated in the store
			if tt.expectPatchCall {
				storedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
				require.NoError(t, err)

				if tt.expectRunningAtPatch {
					require.Greater(t, storedJob.RunningAt, int64(0), "Stored job RunningAt should be set")
				}
			}
		})
	}
}

func TestService_UpdateFromExecutionResult_NoPatchEmitsOnlyWithPRMetadata(t *testing.T) {
	ctx := context.Background()
	store := memory.NewStore()
	obsv := observability.NewNoopExporters()

	t.Run("does not emit when PR title and description are empty", func(t *testing.T) {
		mockEmitter := &mockEventEmitter{}
		service := &Service{
			store:        store,
			obsv:         obsv,
			eventEmitter: mockEmitter,
		}

		job := &jobs.Job{
			ID:               "test-job-no-op-no-pr-metadata",
			OwnerID:          123,
			RepoID:           456,
			Status:           jobs.JobStatusRunning,
			StartedAt:        time.Now().Unix() - 100,
			UseAsyncSessions: true,
		}

		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		err = service.UpdateFromExecutionResult(ctx, job, jobs.JobStatusRunning, time.Time{})
		require.NoError(t, err)
		require.Empty(t, mockEmitter.jobUpdatedCalls)
	})

	t.Run("emits when PR title or description is present", func(t *testing.T) {
		mockEmitter := &mockEventEmitter{}
		service := &Service{
			store:        store,
			obsv:         obsv,
			eventEmitter: mockEmitter,
		}

		job := &jobs.Job{
			ID:                     "test-job-no-op-with-pr-metadata",
			OwnerID:                123,
			RepoID:                 456,
			Status:                 jobs.JobStatusRunning,
			StartedAt:              time.Now().Unix() - 100,
			UseAsyncSessions:       true,
			PullRequestTitle:       "PR title",
			PullRequestDescription: "",
		}

		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		err = service.UpdateFromExecutionResult(ctx, job, jobs.JobStatusRunning, time.Time{})
		require.NoError(t, err)
		require.Len(t, mockEmitter.jobUpdatedCalls, 1)
		require.Equal(t, job, mockEmitter.jobUpdatedCalls[0])
	})
}

// mockEventEmitter is a mock implementation of JobEventEmitter that records calls.
type mockEventEmitter struct {
	jobUpdatedCalls  []*jobs.Job
	jobProgressCalls []struct {
		job      *jobs.Job
		progress *jobevents.ProgressUpdate
	}
}

func (m *mockEventEmitter) EmitJobUpdated(_ context.Context, job *jobs.Job, _ observability.Exporters) {
	m.jobUpdatedCalls = append(m.jobUpdatedCalls, job)
}

func (m *mockEventEmitter) EmitJobProgress(_ context.Context, job *jobs.Job, progress *jobevents.ProgressUpdate, _ observability.Exporters) {
	m.jobProgressCalls = append(m.jobProgressCalls, struct {
		job      *jobs.Job
		progress *jobevents.ProgressUpdate
	}{job, progress})
}

func TestMaybeEmitJobUpdated(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("emits JobUpdated event when UseAsyncSessions is true", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		job := &jobs.Job{
			ID:               "test-job-emit",
			OwnerID:          1,
			RepoID:           2,
			Status:           jobs.JobStatusRunning,
			UseAsyncSessions: true,
		}

		service.emitJobUpdated(ctx, job)

		require.Len(t, mockEmitter.jobUpdatedCalls, 1)
		require.Equal(t, job, mockEmitter.jobUpdatedCalls[0])
	})

	t.Run("does not emit JobUpdated event when UseAsyncSessions is false", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		job := &jobs.Job{
			ID:               "test-job-no-emit",
			OwnerID:          1,
			RepoID:           2,
			Status:           jobs.JobStatusRunning,
			UseAsyncSessions: false,
		}

		service.emitJobUpdated(ctx, job)

		require.Empty(t, mockEmitter.jobUpdatedCalls)
	})

	t.Run("uses noop emitter when eventEmitter is nil", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:               "test-job-nil-emitter",
			OwnerID:          1,
			RepoID:           2,
			Status:           jobs.JobStatusRunning,
			UseAsyncSessions: true,
		}

		// Should not panic when nil eventEmitter is passed (noop emitter is used)
		require.NotPanics(t, func() {
			service.emitJobUpdated(ctx, job)
		})
	})
}

func TestFinalizeJob_WithEventEmitter(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("emits JobUpdated when UseAsyncSessions is true on finalize", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		job := &jobs.Job{
			ID:               "test-job-emit-finalize",
			OwnerID:          1,
			RepoID:           2,
			Status:           jobs.JobStatusRunning,
			UseAsyncSessions: true,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, nil, 1234567890)
		require.NoError(t, err)

		// Should have emitted an event for finalization
		require.Len(t, mockEmitter.jobUpdatedCalls, 1)
		require.Equal(t, jobs.JobStatusCompleted, mockEmitter.jobUpdatedCalls[0].Status)
	})

	t.Run("does not emit JobUpdated when UseAsyncSessions is false on finalize", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capi, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		job := &jobs.Job{
			ID:               "test-job-no-emit-finalize",
			OwnerID:          1,
			RepoID:           2,
			Status:           jobs.JobStatusRunning,
			UseAsyncSessions: false,
		}
		store.CreateJob(ctx, job)

		err := service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, nil, 1234567890)
		require.NoError(t, err)

		// Should not have emitted any events
		require.Empty(t, mockEmitter.jobUpdatedCalls)
	})
}

func TestFinalizeUnexecutedJob_UseAsyncSessions(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("skips session finalization when UseAsyncSessions is true", func(t *testing.T) {
		capiClient, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capiClient, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		job := &jobs.Job{
			ID:               "test-job-async",
			OwnerID:          1,
			RepoID:           2,
			ActorID:          123,
			Status:           jobs.JobStatusPending,
			SessionID:        "session-123",
			UseAsyncSessions: true,
		}
		store.CreateJob(ctx, job)

		jobError := &jobs.JobError{
			Message: "test error",
		}

		// This should succeed without trying to finalize the session
		err := service.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, jobError)
		require.NoError(t, err)

		// Verify job was finalized
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
	})

	t.Run("finalizes session when UseAsyncSessions is false", func(t *testing.T) {
		capiClient, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capiClient, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		job := &jobs.Job{
			ID:               "test-job-sync",
			OwnerID:          1,
			RepoID:           2,
			ActorID:          123,
			Status:           jobs.JobStatusPending,
			SessionID:        "", // No session
			UseAsyncSessions: false,
		}
		store.CreateJob(ctx, job)

		jobError := &jobs.JobError{
			Message: "test error",
		}

		// This should succeed (session finalization will be a no-op since no session exists)
		err := service.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, jobError)
		require.NoError(t, err)

		// Verify job was finalized
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
	})
}

func TestFinalizeJob_PreconditionFailedRetry(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	mockTwirpClientForEnterpriseUser := newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
		CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
	})

	t.Run("succeeds when job is already in desired terminal state after precondition failure", func(t *testing.T) {
		capiClient, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capiClient, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		// Create and save the job
		job := &jobs.Job{
			ID:      "test-precondition-success",
			OwnerID: 1,
			RepoID:  2,
			ActorID: 123,
			Status:  jobs.JobStatusRunning,
		}
		job, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		// Save the original ETag to use for the stale job
		originalETag := job.ETag

		// Simulate a concurrent update that finalizes the job to the same terminal state
		// by updating the job directly in the store
		completedStatus := jobs.JobStatusCompleted
		completedAt := int64(1234567890)
		err = store.PatchJob(ctx, job, db.JobPatch{Status: &completedStatus, CompletedAt: &completedAt})
		require.NoError(t, err)

		// Now try to finalize with a stale version of the job (the one we created before the update)
		// The job's ETag is now stale
		staleJob := &jobs.Job{
			ID:      job.ID,
			OwnerID: job.OwnerID,
			RepoID:  job.RepoID,
			ActorID: job.ActorID,
			Status:  jobs.JobStatusRunning,
			ETag:    originalETag, // This ETag is now stale
		}

		// This should succeed because after the precondition failure,
		// the service will fetch the latest job and see it's already completed
		err = service.FinalizeJob(ctx, staleJob, jobs.JobStatusCompleted, nil, 1234567890)
		require.NoError(t, err)

		// Verify the job in the store is still completed
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
	})

	t.Run("retries patch when job is not in desired terminal state after precondition failure", func(t *testing.T) {
		capiClient, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capiClient, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		// Create and save the job
		job := &jobs.Job{
			ID:      "test-precondition-retry",
			OwnerID: 1,
			RepoID:  2,
			ActorID: 123,
			Status:  jobs.JobStatusQueued,
		}
		job, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		// Save the original ETag to use for the stale job
		originalETag := job.ETag

		// Simulate a concurrent update that changes the job's ETag but doesn't finalize it
		runningStatus := jobs.JobStatusRunning
		err = store.PatchJob(ctx, job, db.JobPatch{Status: &runningStatus})
		require.NoError(t, err)

		// Now try to finalize with a stale version of the job
		staleJob := &jobs.Job{
			ID:      job.ID,
			OwnerID: job.OwnerID,
			RepoID:  job.RepoID,
			ActorID: job.ActorID,
			Status:  jobs.JobStatusQueued,
			ETag:    originalETag, // This ETag is now stale
		}

		// This should succeed because after the precondition failure,
		// the service will fetch the latest job, see it's not yet completed,
		// and retry the patch with the updated ETag
		err = service.FinalizeJob(ctx, staleJob, jobs.JobStatusCompleted, nil, 1234567890)
		require.NoError(t, err)

		// Verify the job in the store is now completed
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
	})

	t.Run("succeeds without retry when job is already in desired state before patching", func(t *testing.T) {
		capiClient, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capiClient, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		// Create a job that's already completed
		job := &jobs.Job{
			ID:          "test-already-completed",
			OwnerID:     1,
			RepoID:      2,
			ActorID:     123,
			Status:      jobs.JobStatusCompleted,
			CompletedAt: 1234567890,
		}
		job, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		// Trying to finalize to the same status should succeed immediately
		err = service.FinalizeJob(ctx, job, jobs.JobStatusCompleted, nil, 1234567890)
		require.NoError(t, err)

		// Verify the job in the store is still completed
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
	})

	t.Run("succeeds when job transitions to different terminal state concurrently", func(t *testing.T) {
		capiClient, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		mockEmitter := &mockEventEmitter{}
		service := New(obsv, ffClient, store, capiClient, ghf, mockTwirpClientForEnterpriseUser, queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), mockEmitter)

		// Create and save the job
		job := &jobs.Job{
			ID:      "test-different-terminal",
			OwnerID: 1,
			RepoID:  2,
			ActorID: 123,
			Status:  jobs.JobStatusRunning,
		}
		job, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		// Save the original ETag to use for the stale job
		originalETag := job.ETag

		// Simulate a concurrent update that finalizes to a DIFFERENT terminal state
		cancelledStatus := jobs.JobStatusCancelled
		completedAt := int64(1234567890)
		err = store.PatchJob(ctx, job, db.JobPatch{Status: &cancelledStatus, CompletedAt: &completedAt})
		require.NoError(t, err)

		// Now try to finalize with a stale version
		staleJob := &jobs.Job{
			ID:      job.ID,
			OwnerID: job.OwnerID,
			RepoID:  job.RepoID,
			ActorID: job.ActorID,
			Status:  jobs.JobStatusRunning,
			ETag:    originalETag,
		}

		// Try to complete, but it was already cancelled
		// After precondition failure, it should try to patch again,
		// even though the job is in a terminal state (but not the desired one)
		err = service.FinalizeJob(ctx, staleJob, jobs.JobStatusCompleted, nil, 1234567890)
		require.NoError(t, err)

		// Verify the job in the store is now completed (the retry succeeded)
		updatedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
	})
}

// mockStatterWithDistribution extends MockStatter to capture DistributionMs calls
type mockStatterWithDistribution struct {
	*observability.MockStatter

	distributionCalls *[]distributionCall
}

type distributionCall struct {
	key      string
	tags     stats.Tags
	duration time.Duration
}

func (m *mockStatterWithDistribution) DistributionMs(key string, tags stats.Tags, duration time.Duration) {
	*m.distributionCalls = append(*m.distributionCalls, distributionCall{key, tags, duration})
}

func TestEmitJobPerformanceMetrics(t *testing.T) {
	ctx := context.Background()
	store := memory.NewStore()

	t.Run("emits total_duration_ms and execution_duration_ms on job completion", func(t *testing.T) {
		distributionCalls := []distributionCall{}
		mockStatter := &mockStatterWithDistribution{
			MockStatter:       &observability.MockStatter{},
			distributionCalls: &distributionCalls,
		}

		obsv := observability.NewNoopExporters()
		obsv.Statter = mockStatter

		service := &Service{
			store:       store,
			obsv:        obsv,
			appProvider: agenticapptest.NewTestProvider(t),
		}

		now := time.Now().Unix()
		job := &jobs.Job{
			ID:          "test-job-metrics",
			OwnerID:     1,
			RepoID:      2,
			Status:      jobs.JobStatusCompleted,
			Launcher:    launcher.TypeSandbox,
			EventType:   jobs.EventTypeIssueAssignment,
			Action:      jobs.AgentActionFix,
			CreatedAt:   now - 600, // 10 minutes ago
			QueuedAt:    now - 550, // 9 min 10 sec ago
			LaunchedAt:  now - 500, // 8 min 20 sec ago
			StartedAt:   now - 400, // 6 min 40 sec ago
			CompletedAt: now,
		}

		service.emitJobPerformanceMetrics(ctx, job)

		// Should have 2 distribution calls: total_duration_ms and execution_duration_ms
		require.Len(t, distributionCalls, 2)

		// Check total_duration_ms
		require.Equal(t, "jobs.total_duration_ms", distributionCalls[0].key)
		require.Equal(t, 600*time.Second, distributionCalls[0].duration)
		require.Equal(t, string(jobs.EventTypeIssueAssignment), distributionCalls[0].tags["event_type"])
		require.Equal(t, string(jobs.AgentActionFix), distributionCalls[0].tags["agent_type"])
		require.Equal(t, "copilot", distributionCalls[0].tags["agent"])
		require.Equal(t, "sandbox", distributionCalls[0].tags["launcher_type"])
		require.Equal(t, string(jobs.JobStatusCompleted), distributionCalls[0].tags["terminal_state"])

		// Check execution_duration_ms
		require.Equal(t, "jobs.execution_duration_ms", distributionCalls[1].key)
		require.Equal(t, 400*time.Second, distributionCalls[1].duration)
		require.Equal(t, string(jobs.EventTypeIssueAssignment), distributionCalls[1].tags["event_type"])
		require.Equal(t, string(jobs.AgentActionFix), distributionCalls[1].tags["agent_type"])
		require.Equal(t, "copilot", distributionCalls[1].tags["agent"])
		require.Equal(t, "sandbox", distributionCalls[1].tags["launcher_type"])
		require.Equal(t, string(jobs.JobStatusCompleted), distributionCalls[1].tags["terminal_state"])
	})

	t.Run("does not emit metrics for non-terminal jobs", func(t *testing.T) {
		distributionCalls := []distributionCall{}
		mockStatter := &mockStatterWithDistribution{
			MockStatter:       &observability.MockStatter{},
			distributionCalls: &distributionCalls,
		}

		obsv := observability.NewNoopExporters()
		obsv.Statter = mockStatter

		service := &Service{
			store: store,
			obsv:  obsv,
		}

		job := &jobs.Job{
			ID:         "test-job-running",
			OwnerID:    1,
			RepoID:     2,
			Status:     jobs.JobStatusRunning,
			EventType:  jobs.EventTypeIssueAssignment,
			Action:     jobs.AgentActionFix,
			CreatedAt:  time.Now().Unix() - 100,
			LaunchedAt: time.Now().Unix() - 50,
			StartedAt:  time.Now().Unix() - 30,
		}

		service.emitJobPerformanceMetrics(ctx, job)

		// Should not emit any metrics for non-terminal jobs
		require.Empty(t, distributionCalls)
	})

	t.Run("handles missing timestamps gracefully", func(t *testing.T) {
		distributionCalls := []distributionCall{}
		mockStatter := &mockStatterWithDistribution{
			MockStatter:       &observability.MockStatter{},
			distributionCalls: &distributionCalls,
		}

		obsv := observability.NewNoopExporters()
		obsv.Statter = mockStatter

		service := &Service{
			store: store,
			obsv:  obsv,
		}

		// Job with only CompletedAt set (no CreatedAt or StartedAt)
		job := &jobs.Job{
			ID:          "test-job-missing-timestamps",
			OwnerID:     1,
			RepoID:      2,
			Status:      jobs.JobStatusFailed,
			EventType:   jobs.EventTypeIssueAssignment,
			Action:      jobs.AgentActionFix,
			CompletedAt: time.Now().Unix(),
		}

		service.emitJobPerformanceMetrics(ctx, job)

		// Should not emit any metrics since required timestamps are missing
		require.Empty(t, distributionCalls)
	})
}

func TestQueueWaitDurationMetric(t *testing.T) {
	ctx := context.Background()

	t.Run("emits queue_wait_duration_ms when job is launched", func(t *testing.T) {
		distributionCalls := []distributionCall{}
		mockStatter := &mockStatterWithDistribution{
			MockStatter:       &observability.MockStatter{},
			distributionCalls: &distributionCalls,
		}

		obsv := observability.NewNoopExporters()
		obsv.Statter = mockStatter

		store := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(store, countTracker, nil)
		ffClient := featureflags.NewNoopClient(nil)

		service := &Service{
			store:        store,
			obsv:         obsv,
			limiter:      limiter,
			twirp:        githubtwirp.NewNoopClient(),
			ffs:          ffClient,
			eventEmitter: &noopJobEventEmitter{},
			appProvider:  agenticapptest.NewTestProvider(t),
		}

		now := time.Now().Unix()
		job := &jobs.Job{
			ID:               "test-job-queue-wait",
			OwnerID:          1,
			RepoID:           2,
			ActorID:          123,
			Status:           jobs.JobStatusQueued,
			Launcher:         launcher.TypeSandbox,
			EventType:        jobs.EventTypeIssueAssignment,
			Action:           jobs.AgentActionFix,
			QueuedAt:         now - 60, // Queued 60 seconds ago
			UseAsyncSessions: true,     // Skip session creation
		}

		store.CreateJob(ctx, job)

		launchedAt := now - 30 // Launched 30 seconds ago
		_, err := service.UpdateJobForLaunched(ctx, job, "12345", launchedAt)
		require.NoError(t, err)

		// Find queue_wait_duration_ms metric
		var queueWaitMetric *distributionCall
		for i := range distributionCalls {
			if distributionCalls[i].key == "jobs.queue_wait_duration_ms" {
				queueWaitMetric = &distributionCalls[i]
			}
		}

		require.NotNil(t, queueWaitMetric, "queue_wait_duration_ms metric should be emitted")
		require.Equal(t, string(jobs.EventTypeIssueAssignment), queueWaitMetric.tags["event_type"])
		require.Equal(t, string(jobs.AgentActionFix), queueWaitMetric.tags["agent_type"])
		require.Equal(t, "copilot", queueWaitMetric.tags["agent"])
		require.Equal(t, "sandbox", queueWaitMetric.tags["launcher_type"])

		// Verify the duration is approximately 30 seconds (launchedAt - queuedAt)
		expectedDuration := time.Duration(30) * time.Second
		require.Equal(t, expectedDuration, queueWaitMetric.duration)
	})
}

func TestRequestToLaunchedMetric(t *testing.T) {
	ctx := context.Background()

	t.Run("emits request_to_launched when job has RequestStartedAt", func(t *testing.T) {
		distributionCalls := []distributionCall{}
		mockStatter := &mockStatterWithDistribution{
			MockStatter:       &observability.MockStatter{},
			distributionCalls: &distributionCalls,
		}

		obsv := observability.NewNoopExporters()
		obsv.Statter = mockStatter

		store := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(store, countTracker, nil)
		ffClient := featureflags.NewNoopClient(nil)

		service := &Service{
			store:        store,
			obsv:         obsv,
			limiter:      limiter,
			twirp:        githubtwirp.NewNoopClient(),
			ffs:          ffClient,
			eventEmitter: &noopJobEventEmitter{},
			appProvider:  agenticapptest.NewTestProvider(t),
		}

		now := time.Now().Unix()
		job := &jobs.Job{
			ID:               "test-job-request-to-launched",
			OwnerID:          1,
			RepoID:           2,
			ActorID:          123,
			Status:           jobs.JobStatusQueued,
			Launcher:         launcher.TypeSandbox,
			EventType:        jobs.EventTypeIssueAssignment,
			Action:           jobs.AgentActionFix,
			RequestStartedAt: now - 90, // Request received 90 seconds ago
			QueuedAt:         now - 60, // Queued 60 seconds ago
			UseAsyncSessions: true,     // Skip session creation
		}

		store.CreateJob(ctx, job)

		launchedAt := now
		_, err := service.UpdateJobForLaunched(ctx, job, "12345", launchedAt)
		require.NoError(t, err)

		// Find request_to_launched metric
		var requestToLaunchedMetric *distributionCall
		for i := range distributionCalls {
			if distributionCalls[i].key == "jobs.request_to_launched" {
				requestToLaunchedMetric = &distributionCalls[i]
			}
		}

		require.NotNil(t, requestToLaunchedMetric, "request_to_launched metric should be emitted")
		require.Equal(t, string(jobs.EventTypeIssueAssignment), requestToLaunchedMetric.tags["event_type"])
		require.Equal(t, string(jobs.AgentActionFix), requestToLaunchedMetric.tags["agent_type"])
		require.Equal(t, "copilot", requestToLaunchedMetric.tags["agent"])
		require.Equal(t, "sandbox", requestToLaunchedMetric.tags["launcher_type"])

		// Verify the duration is approximately 90 seconds (launchedAt - requestStartedAt)
		expectedDuration := time.Duration(90) * time.Second
		require.Equal(t, expectedDuration, requestToLaunchedMetric.duration)
	})

	t.Run("does not emit request_to_launched when RequestStartedAt is zero", func(t *testing.T) {
		distributionCalls := []distributionCall{}
		mockStatter := &mockStatterWithDistribution{
			MockStatter:       &observability.MockStatter{},
			distributionCalls: &distributionCalls,
		}

		obsv := observability.NewNoopExporters()
		obsv.Statter = mockStatter

		store := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(store, countTracker, nil)
		ffClient := featureflags.NewNoopClient(nil)

		service := &Service{
			store:        store,
			obsv:         obsv,
			limiter:      limiter,
			twirp:        githubtwirp.NewNoopClient(),
			ffs:          ffClient,
			eventEmitter: &noopJobEventEmitter{},
			appProvider:  agenticapptest.NewTestProvider(t),
		}

		now := time.Now().Unix()
		job := &jobs.Job{
			ID:               "test-job-no-request-started",
			OwnerID:          1,
			RepoID:           2,
			ActorID:          123,
			Status:           jobs.JobStatusQueued,
			EventType:        jobs.EventTypeIssueAssignment,
			Action:           jobs.AgentActionFix,
			RequestStartedAt: 0, // No request started time
			QueuedAt:         now - 60,
			UseAsyncSessions: true,
		}

		store.CreateJob(ctx, job)

		launchedAt := now
		_, err := service.UpdateJobForLaunched(ctx, job, "12345", launchedAt)
		require.NoError(t, err)

		// Verify request_to_launched was NOT emitted
		for i := range distributionCalls {
			require.NotEqual(t, "jobs.request_to_launched", distributionCalls[i].key,
				"request_to_launched should not be emitted when RequestStartedAt is 0")
		}
	})
}

func TestPreparedToQueuedMetric(t *testing.T) {
	ctx := context.Background()

	t.Run("emits prepared_to_queued when job has PreparedAt", func(t *testing.T) {
		distributionCalls := []distributionCall{}
		mockStatter := &mockStatterWithDistribution{
			MockStatter:       &observability.MockStatter{},
			distributionCalls: &distributionCalls,
		}

		obsv := observability.NewNoopExporters()
		obsv.Statter = mockStatter

		store := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(store, countTracker, nil)
		ffClient := featureflags.NewNoopClient(nil)

		service := &Service{
			store:        store,
			obsv:         obsv,
			limiter:      limiter,
			twirp:        githubtwirp.NewNoopClient(),
			ffs:          ffClient,
			eventEmitter: &noopJobEventEmitter{},
			appProvider:  agenticapptest.NewTestProvider(t),
		}

		now := time.Now().Unix()
		job := &jobs.Job{
			ID:         "test-prepared-to-queued",
			OwnerID:    1,
			RepoID:     2,
			ActorID:    123,
			Status:     jobs.JobStatusPending,
			Launcher:   launcher.TypeSandbox,
			EventType:  jobs.EventTypeIssueAssignment,
			Action:     jobs.AgentActionFix,
			PreparedAt: now - 5, // Prepared 5 seconds ago
		}

		store.CreateJob(ctx, job)

		queuedAt := now
		_, err := service.UpdateJobForQueued(ctx, job, queuedAt)
		require.NoError(t, err)

		var preparedToQueued *distributionCall
		for i := range distributionCalls {
			if distributionCalls[i].key == "jobs.prepared_to_queued" {
				preparedToQueued = &distributionCalls[i]
			}
		}

		require.NotNil(t, preparedToQueued, "prepared_to_queued metric should be emitted")
		require.Equal(t, 5*time.Second, preparedToQueued.duration)
		require.Equal(t, string(jobs.EventTypeIssueAssignment), preparedToQueued.tags["event_type"])
		require.Equal(t, string(jobs.AgentActionFix), preparedToQueued.tags["agent_type"])
		require.Equal(t, "copilot", preparedToQueued.tags["agent"])
		require.Equal(t, "sandbox", preparedToQueued.tags["launcher_type"])
		require.Equal(t, "false", preparedToQueued.tags["custom_setup_steps"])
		require.Equal(t, runnerlabels.UbuntuLatestLabel, preparedToQueued.tags["runs_on"])
		require.Equal(t, "false", preparedToQueued.tags["async_sessions"])
	})

	t.Run("skips when PreparedAt is zero", func(t *testing.T) {
		distributionCalls := []distributionCall{}
		mockStatter := &mockStatterWithDistribution{
			MockStatter:       &observability.MockStatter{},
			distributionCalls: &distributionCalls,
		}

		obsv := observability.NewNoopExporters()
		obsv.Statter = mockStatter

		store := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(store, countTracker, nil)
		ffClient := featureflags.NewNoopClient(nil)

		service := &Service{
			store:        store,
			obsv:         obsv,
			limiter:      limiter,
			twirp:        githubtwirp.NewNoopClient(),
			ffs:          ffClient,
			eventEmitter: &noopJobEventEmitter{},
		}

		job := &jobs.Job{
			ID:        "test-no-prepared",
			OwnerID:   1,
			RepoID:    2,
			ActorID:   123,
			Status:    jobs.JobStatusPending,
			EventType: jobs.EventTypeIssueAssignment,
			Action:    jobs.AgentActionFix,
		}

		store.CreateJob(ctx, job)

		_, err := service.UpdateJobForQueued(ctx, job, time.Now().Unix())
		require.NoError(t, err)

		for _, call := range distributionCalls {
			require.NotEqual(t, "jobs.prepared_to_queued", call.key, "prepared_to_queued should not be emitted when PreparedAt is zero")
		}
	})
}

func TestUpdateJobForLaunched_SessionFailure(t *testing.T) {
	ctx := context.Background()

	t.Run("succeeds when session update fails but feature flag is enabled", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		store := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(store, countTracker, nil)

		ffClient := featureflags.NewNoopClient(nil)
		// Configure capi client to fail on session update
		capiClient := capi.NewNoopClient()
		capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			return goerrors.New("session update failed")
		}

		service := &Service{
			store:        store,
			obsv:         obsv,
			limiter:      limiter,
			twirp:        githubtwirp.NewNoopClient(),
			ffs:          ffClient,
			capi:         capiClient,
			eventEmitter: &noopJobEventEmitter{},
		}

		now := time.Now().Unix()
		job := &jobs.Job{
			ID:               "test-job-session-fail-skip",
			OwnerID:          1,
			RepoID:           2,
			ActorID:          123,
			Status:           jobs.JobStatusQueued,
			SessionID:        "session-123",
			UseAsyncSessions: false, // Session update will be attempted
		}

		store.CreateJob(ctx, job)

		updatedJob, err := service.UpdateJobForLaunched(ctx, job, "12345", now)
		require.NoError(t, err)
		require.NotNil(t, updatedJob)
		require.Equal(t, jobs.JobStatusRunning, updatedJob.Status)
		require.Equal(t, "12345", updatedJob.ComputeID)
	})
}

func TestRunsOnMetricTag(t *testing.T) {
	tests := []struct {
		runsOn string
		want   string
	}{
		{"", runnerlabels.UbuntuLatestLabel},
		{runnerlabels.UbuntuLatestLabel, runnerlabels.UbuntuLatestLabel},
		{runnerlabels.WindowsLatestLabel, runnerlabels.WindowsLatestLabel},
		{runnerlabels.CustomImageLabel, runnerlabels.CustomImageLabel},
		{runnerlabels.MacOSLatestLabel, "other"},
		{runnerlabels.SelfHostedLabel, "other"},
		{"custom", "other"},
	}
	for _, tt := range tests {
		t.Run(tt.runsOn, func(t *testing.T) {
			got := runsOnMetricTag(tt.runsOn)
			require.Equal(t, tt.want, got)
		})
	}
}

func TestUpdateJobForLaunched_ComputeIDValidation(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("accepts numeric compute ID for Actions job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		ffClient := featureflags.NewNoopClient(nil)
		service := New(obsv, ffClient, store, capi, ghf, githubtwirp.NewNoopClient(), queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-actions-numeric",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		updated, err := service.UpdateJobForLaunched(ctx, job, "12345", time.Now().Unix())
		require.NoError(t, err)
		require.Equal(t, "12345", updated.ComputeID)
		require.Equal(t, jobs.JobStatusRunning, updated.Status)
	})

	t.Run("rejects non-numeric compute ID for Actions job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		ffClient := featureflags.NewNoopClient(nil)
		service := New(obsv, ffClient, store, capi, ghf, githubtwirp.NewNoopClient(), queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-actions-bad-id",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		_, err := service.UpdateJobForLaunched(ctx, job, "sb-abc-123", time.Now().Unix())
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid Actions compute ID")
	})

	t.Run("accepts UUID compute ID for sandbox job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		ffClient := featureflags.NewNoopClient(nil)
		service := New(obsv, ffClient, store, capi, ghf, githubtwirp.NewNoopClient(), queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:       "test-sandbox-uuid",
			OwnerID:  1,
			RepoID:   2,
			Status:   jobs.JobStatusQueued,
			Launcher: launcher.TypeSandbox,
		}
		store.CreateJob(ctx, job)

		sandboxID := "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
		updated, err := service.UpdateJobForLaunched(ctx, job, sandboxID, time.Now().Unix())
		require.NoError(t, err)
		require.Equal(t, sandboxID, updated.ComputeID)
		require.Equal(t, jobs.JobStatusRunning, updated.Status)
	})

	t.Run("rejects empty compute ID for Actions job", func(t *testing.T) {
		capi, store, _, ghf, experiments, queue, limiter := commonServiceDependencies(obsv)
		ffClient := featureflags.NewNoopClient(nil)
		service := New(obsv, ffClient, store, capi, ghf, githubtwirp.NewNoopClient(), queue, limiter, experiments, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:      "test-actions-empty",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusQueued,
		}
		store.CreateJob(ctx, job)

		_, err := service.UpdateJobForLaunched(ctx, job, "", time.Now().Unix())
		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid Actions compute ID")
	})
}
