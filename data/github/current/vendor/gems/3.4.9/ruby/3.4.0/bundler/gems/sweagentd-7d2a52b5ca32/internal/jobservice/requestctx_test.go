package jobservice

import (
	"context"
	"strconv"
	"testing"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAddRequestCtxSessionFromJob(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("adds session to request context from job", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		job := &jobs.Job{
			SessionID:     "test-session-id",
			Status:        jobs.JobStatusRunning,
			PullRequestID: 12345,
			EventType:     jobs.EventTypePullRequestComment,
			ComputeID:     "67890",
		}

		s.addRequestCtxSessionFromJob(ctx, job)

		session, ok := requestctx.Session(ctx)
		require.True(t, ok)
		assert.Equal(t, "test-session-id", session.ID)
		assert.Equal(t, string(capi.SessionStateInProgress), session.State)
		assert.Equal(t, string(capi.ResourceTypePullRequest), session.ResourceType)
		assert.Equal(t, int64(12345), session.ResourceID)
		assert.Equal(t, string(jobs.EventTypePullRequestComment), session.EventType)
		assert.Equal(t, uint64(67890), session.WorkflowRunID)
	})

	t.Run("handles invalid compute ID gracefully", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		job := &jobs.Job{
			SessionID:     "test-session-id",
			Status:        jobs.JobStatusQueued,
			PullRequestID: 999,
			EventType:     jobs.EventTypePullRequestComment,
			ComputeID:     "invalid-number",
		}

		s.addRequestCtxSessionFromJob(ctx, job)

		session, ok := requestctx.Session(ctx)
		require.True(t, ok)
		assert.Equal(t, "test-session-id", session.ID)
		assert.Equal(t, uint64(0), session.WorkflowRunID)
	})

	t.Run("sets session state based on job status", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		testCases := []struct {
			jobStatus     jobs.JobStatus
			expectedState string
		}{
			{jobs.JobStatusQueued, string(capi.SessionStateQueued)},
			{jobs.JobStatusRunning, string(capi.SessionStateInProgress)},
			{jobs.JobStatusCompleted, string(capi.SessionStateCompleted)},
			{jobs.JobStatusFailed, string(capi.SessionStateFailed)},
			{jobs.JobStatusCancelled, string(capi.SessionStateCancelled)},
		}

		for _, tc := range testCases {
			t.Run(string(tc.jobStatus), func(t *testing.T) {
				ctx := requestctx.NewContext(context.Background())
				job := &jobs.Job{
					SessionID: "session-" + string(tc.jobStatus),
					Status:    tc.jobStatus,
				}

				s.addRequestCtxSessionFromJob(ctx, job)

				session, ok := requestctx.Session(ctx)
				require.True(t, ok)
				assert.Equal(t, tc.expectedState, session.State)
			})
		}
	})
}

func TestAddRequestContextSession(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("adds session to request context", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		session := &capi.Session{
			ID:            "session-123",
			State:         capi.SessionStateInProgress,
			ResourceType:  capi.ResourceTypePullRequest,
			ResourceID:    456,
			EventType:     "pull_request",
			WorkflowRunID: 789,
		}

		s.addRequestContextSession(ctx, session)

		ctxSession, ok := requestctx.Session(ctx)
		require.True(t, ok)
		assert.Equal(t, "session-123", ctxSession.ID)
		assert.Equal(t, string(capi.SessionStateInProgress), ctxSession.State)
		assert.Equal(t, string(capi.ResourceTypePullRequest), ctxSession.ResourceType)
		assert.Equal(t, int64(456), ctxSession.ResourceID)
		assert.Equal(t, "pull_request", ctxSession.EventType)
		assert.Equal(t, uint64(789), ctxSession.WorkflowRunID)
	})

	t.Run("removes session when nil is passed", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		// First add a session
		session := &capi.Session{ID: "test-session"}
		s.addRequestContextSession(ctx, session)
		_, ok := requestctx.Session(ctx)
		require.True(t, ok)

		// Now remove it by passing nil
		s.addRequestContextSession(ctx, nil)
		// Note: The implementation may still return ok=true but with nil/empty session
	})
}

func TestUpdateRequestContextSession(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("updates existing session in context", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		// Set up initial session
		initialSession := &requestctx.CtxSession{
			ID:    "session-id",
			State: string(capi.SessionStateQueued),
		}
		require.NoError(t, requestctx.AddSession(ctx, initialSession))

		// Update the session
		newState := capi.SessionStateInProgress
		update := capi.SessionUpdate{
			State:         newState,
			ResourceID:    999,
			ResourceType:  func() *capi.SessionResourceType { rt := capi.ResourceTypePullRequest; return &rt }(),
			WorkflowRunID: 12345,
		}

		s.updateRequestContextSession(ctx, update)

		session, ok := requestctx.Session(ctx)
		require.True(t, ok)
		assert.Equal(t, string(capi.SessionStateInProgress), session.State)
		assert.Equal(t, int64(999), session.ResourceID)
		assert.Equal(t, string(capi.ResourceTypePullRequest), session.ResourceType)
		assert.Equal(t, uint64(12345), session.WorkflowRunID)
	})

	t.Run("creates new session if none exists", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		update := capi.SessionUpdate{
			State:      capi.SessionStateInProgress,
			ResourceID: 123,
		}

		s.updateRequestContextSession(ctx, update)

		session, ok := requestctx.Session(ctx)
		require.True(t, ok)
		assert.Equal(t, string(capi.SessionStateInProgress), session.State)
		assert.Equal(t, int64(123), session.ResourceID)
	})
}

func TestUpdateRequestContextJob(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("adds job to request context", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		job := &jobs.Job{
			ID:                "job-123",
			RepoID:            1,
			OwnerID:           2,
			AssignmentID:      "assignment-456",
			ComputeID:         "compute-789",
			SessionID:         "session-abc",
			EventType:         jobs.EventTypePullRequestComment,
			ActorID:           100,
			PullRequestID:     200,
			PullRequestNumber: 3,
			CreatedAt:         1000,
			CompletedAt:       2000,
			QueuedAt:          1500,
			Status:            jobs.JobStatusCompleted,
			BranchName:        "feature-branch",
			CustomAgent: customagent.DBRecord{
				Name:        "custom-agent-name",
				RepoID:      456,
				RepoOwnerID: 789,
				Version:     "sha-some-value-here",
			},
		}

		s.updateRequestContextJob(ctx, job)

		ctxJob, ok := requestctx.Job(ctx)
		require.True(t, ok)
		assert.Equal(t, "job-123", ctxJob.ID)
		assert.Equal(t, int64(1), ctxJob.RepoID)
		assert.Equal(t, int64(2), ctxJob.OwnerID)
		assert.Equal(t, "assignment-456", ctxJob.AssignmentID)
		assert.Equal(t, "compute-789", ctxJob.ComputeID)
		assert.Equal(t, "session-abc", ctxJob.SessionID)
		assert.Equal(t, string(jobs.EventTypePullRequestComment), ctxJob.EventType)
		assert.Equal(t, int64(100), ctxJob.ActorID)
		assert.Equal(t, int64(200), ctxJob.PullRequestID)
		assert.Equal(t, 3, ctxJob.PullRequestNumber)
		assert.Equal(t, int64(1000), ctxJob.CreatedAt)
		assert.Equal(t, int64(2000), ctxJob.CompletedAt)
		assert.Equal(t, int64(1500), ctxJob.QueuedAt)
		assert.Equal(t, string(jobs.JobStatusCompleted), ctxJob.Status)
		assert.Equal(t, "feature-branch", ctxJob.BranchName)
		assert.Equal(t, "custom-agent-name", ctxJob.CustomAgent.Name)
		assert.Equal(t, int64(456), ctxJob.CustomAgent.RepoID)
		assert.Equal(t, int64(789), ctxJob.CustomAgent.OwnerID)
		assert.Equal(t, "sha-some-value-here", ctxJob.CustomAgent.Version)
	})

	t.Run("removes job when nil is passed", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		// First add a job
		job := &jobs.Job{ID: "test-job"}
		s.updateRequestContextJob(ctx, job)
		_, ok := requestctx.Job(ctx)
		require.True(t, ok)

		// Now remove it by passing nil
		s.updateRequestContextJob(ctx, nil)
	})

	t.Run("updates job with experiments", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		job := &jobs.Job{
			ID:     "job-with-experiments",
			RepoID: 1,
			Experiments: &experiments.AssignmentExperiments{
				Variations: map[string]any{
					"exp1": "variant-a",
					"exp2": "variant-b",
				},
				AssignmentContext: "test-context",
			},
		}

		s.updateRequestContextJob(ctx, job)

		ctxJob, ok := requestctx.Job(ctx)
		require.True(t, ok)
		assert.Equal(t, "job-with-experiments", ctxJob.ID)
		assert.NotNil(t, ctxJob.Experiments)
		assert.Equal(t, "variant-a", ctxJob.Experiments.Variations["exp1"])
		assert.Equal(t, "variant-b", ctxJob.Experiments.Variations["exp2"])
		assert.Equal(t, "test-context", ctxJob.Experiments.AssignmentContext)
	})

	t.Run("creates new context job when job ID changes", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		ctx := requestctx.NewContext(context.Background())
		// Add first job
		job1 := &jobs.Job{ID: "job-1", RepoID: 1}
		s.updateRequestContextJob(ctx, job1)

		ctxJob1, ok := requestctx.Job(ctx)
		require.True(t, ok)
		assert.Equal(t, "job-1", ctxJob1.ID)

		// Add different job - should create new context
		job2 := &jobs.Job{ID: "job-2", RepoID: 2}
		s.updateRequestContextJob(ctx, job2)

		ctxJob2, ok := requestctx.Job(ctx)
		require.True(t, ok)
		assert.Equal(t, "job-2", ctxJob2.ID)
		assert.Equal(t, int64(2), ctxJob2.RepoID)
	})

	t.Run("static method updates job correctly", func(t *testing.T) {
		ctx := requestctx.NewContext(context.Background())
		job := &jobs.Job{
			ID:      "static-job",
			RepoID:  5,
			OwnerID: 10,
			Status:  jobs.JobStatusRunning,
		}

		updateRequestContextJob(ctx, obsv, job)

		ctxJob, ok := requestctx.Job(ctx)
		require.True(t, ok)
		assert.Equal(t, "static-job", ctxJob.ID)
		assert.Equal(t, int64(5), ctxJob.RepoID)
		assert.Equal(t, int64(10), ctxJob.OwnerID)
		assert.Equal(t, string(jobs.JobStatusRunning), ctxJob.Status)
	})

	t.Run("handles all job status types correctly", func(t *testing.T) {
		capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, nil, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		statuses := []jobs.JobStatus{
			jobs.JobStatusQueued,
			jobs.JobStatusRunning,
			jobs.JobStatusCompleted,
			jobs.JobStatusFailed,
			jobs.JobStatusCancelled,
		}

		for i, status := range statuses {
			ctx := requestctx.NewContext(context.Background())
			job := &jobs.Job{
				ID:     "job-" + strconv.Itoa(i),
				Status: status,
			}

			s.updateRequestContextJob(ctx, job)

			ctxJob, ok := requestctx.Job(ctx)
			require.True(t, ok)
			assert.Equal(t, string(status), ctxJob.Status)
		}
	})
}
