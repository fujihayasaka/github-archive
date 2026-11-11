package jobservice

import (
	"context"
	_ "embed"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestJobServiceSessions_getPreviousSessionIDs(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("returns empty slice when feature flag is disabled", func(t *testing.T) {
		ffs := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		assignment := eventstest.Assignment()
		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		job, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "current-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
		})
		require.NoError(t, err)
		// Include current job in the list

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
		result := s.getPreviousSessionIDs(ctx, job)
		assert.Equal(t, []string{}, result)
	})

	t.Run("returns empty slice when jobsForAssignment is empty", func(t *testing.T) {
		ffs := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		assignment := eventstest.Assignment()
		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		job := &jobs.Job{
			ID:           "current-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
		}
		// Don't create the job in the store to simulate no other jobs

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
		result := s.getPreviousSessionIDs(ctx, job)
		assert.Equal(t, []string{}, result)
	})

	t.Run("returns empty slice when only current job exists", func(t *testing.T) {
		ffs := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		assignment := eventstest.Assignment()
		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		job, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "current-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
		}) // Only current job in the list
		require.NoError(t, err)

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
		result := s.getPreviousSessionIDs(ctx, job)
		assert.Equal(t, []string{}, result)
	})

	t.Run("returns session IDs from incomplete jobs", func(t *testing.T) {
		ffs := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		assignment := eventstest.Assignment()
		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		now := time.Now()
		currentJob, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "current-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusRunning,
			CreatedAt:    now.Unix(),
		})
		require.NoError(t, err)

		// Create a previous job that's still running
		previousJob, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "previous-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusRunning,
			SessionID:    "previous-session",
			CreatedAt:    now.Add(-1 * time.Hour).Unix(), // Created earlier
		})
		require.NoError(t, err)

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
		result := s.getPreviousSessionIDs(ctx, currentJob)
		assert.Equal(t, []string{previousJob.SessionID}, result)
	})

	t.Run("skips jobs with empty session IDs", func(t *testing.T) {
		ffs := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		assignment := eventstest.Assignment()
		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		now := time.Now()
		currentJob, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "current-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusRunning,
			CreatedAt:    now.Unix(),
		})
		require.NoError(t, err)

		// Create a previous completed job without session ID
		_, err = store.CreateJob(ctx, &jobs.Job{
			ID:           "previous-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			SessionID:    "",                             // No session ID
			CreatedAt:    now.Add(-1 * time.Hour).Unix(), // Created earlier
		})
		require.NoError(t, err)

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
		result := s.getPreviousSessionIDs(ctx, currentJob)
		assert.Equal(t, []string{}, result)
	})

	t.Run("skips empty session IDs but continues processing other jobs", func(t *testing.T) {
		ffs := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		assignment := eventstest.Assignment()
		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		now := time.Now()
		currentJob, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "current-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusRunning,
			CreatedAt:    now.Unix(),
		})
		require.NoError(t, err)

		// Create jobs with mixed session ID states
		jobWithSession, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "job-with-session",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			SessionID:    "valid-session",
			CreatedAt:    now.Add(-1 * time.Hour).Unix(), // Most recent
		})
		require.NoError(t, err)

		_, err = store.CreateJob(ctx, &jobs.Job{
			ID:           "job-without-session",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			SessionID:    "", // Empty session ID - should be skipped
			CreatedAt:    now.Add(-2 * time.Hour).Unix(),
		})
		require.NoError(t, err)

		anotherJobWithSession, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "another-job-with-session",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			SessionID:    "another-valid-session",
			CreatedAt:    now.Add(-3 * time.Hour).Unix(), // Oldest
		})
		require.NoError(t, err)

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
		result := s.getPreviousSessionIDs(ctx, currentJob)
		// Should return only the jobs with valid session IDs, in chronological order
		assert.Equal(t, []string{jobWithSession.SessionID, anotherJobWithSession.SessionID}, result)
	})

	t.Run("handles zero CreatedAt values gracefully", func(t *testing.T) {
		ffs := featureflags.NewNoopClient(map[string]bool{})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		assignment := eventstest.Assignment()
		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		now := time.Now()
		currentJob, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "current-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusRunning,
			CreatedAt:    now.Unix(),
		})
		require.NoError(t, err)

		// Create a job with zero CreatedAt (should be sorted last)
		zeroCreatedJob, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "zero-created-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			SessionID:    "zero-session",
			CreatedAt:    1, // Zero value
		})
		require.NoError(t, err)

		// Create another job with non-zero CreatedAt
		normalJob, err := store.CreateJob(ctx, &jobs.Job{
			ID:           "normal-job",
			ActorID:      123,
			RepoID:       assignment.RepoID,
			OwnerID:      assignment.OwnerID,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			SessionID:    "normal-session",
			CreatedAt:    now.Add(-1 * time.Hour).Unix(),
		})
		require.NoError(t, err)

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
		result := s.getPreviousSessionIDs(ctx, currentJob)
		// Should return the normal job's session since it has higher CreatedAt than 0
		assert.Equal(t, []string{normalJob.SessionID, zeroCreatedJob.SessionID}, result)
	})
}

func TestGetSessionForJob_UseAsyncSessions(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffs := featureflags.NewNoopClient(map[string]bool{})
	capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

	t.Run("returns nil when UseAsyncSessions is true", func(t *testing.T) {
		s := New(obsv, ffs, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:               "test-job",
			ActorID:          123,
			RepoID:           456,
			OwnerID:          789,
			SessionID:        "session-123",
			UseAsyncSessions: true,
		}

		session, err := s.GetSessionForJob(ctx, job)
		require.NoError(t, err)
		assert.Nil(t, session)
	})
}

func TestUpdateSession_UseAsyncSessions(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffs := featureflags.NewNoopClient(map[string]bool{})
	capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

	t.Run("returns nil when UseAsyncSessions is true", func(t *testing.T) {
		s := New(obsv, ffs, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			ID:               "test-job",
			ActorID:          123,
			RepoID:           456,
			OwnerID:          789,
			SessionID:        "session-123",
			UseAsyncSessions: true,
		}

		update := capi.SessionUpdate{
			State: capi.SessionStateCompleted,
		}

		err := s.UpdateSession(ctx, job, update)
		require.NoError(t, err)
	})
}
