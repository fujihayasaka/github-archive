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
	tokens "github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
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

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
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

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
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

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
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

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
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

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
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

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
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

		s := New(obsv, ffs, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
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
		s := New(obsv, ffs, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

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
		s := New(obsv, ffs, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

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

func TestGetSessionClient_TriggeredJobUsesUserToken(t *testing.T) {
	ctx := tokens.NewContext(context.Background())
	obsv := observability.NewNoopExporters()
	ffs := featureflags.NewNoopClient(map[string]bool{
		capi.CopilotAPIAgentSessions: true,
	})
	capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

	var userTokenRequest *sweagentdTwirp.MintUserToServerTokenForRepoRequest
	twirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepo = func(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error) {
		userTokenRequest = req
		return &sweagentdTwirp.MintUserToServerTokenForRepoResponse{Token: "user-token"}, nil
	}
	twirp.NoopSweagentdAPI.MockMintServerToServerTokenForRepo = func(ctx context.Context, req *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error) {
		t.Fatal("triggered user-attributed jobs must not mint org S2S tokens")
		return nil, nil
	}

	s := New(obsv, ffs, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)
	job := &jobs.Job{
		ID:          "triggered-user-job",
		ActorID:     123,
		RepoID:      456,
		OwnerID:     789,
		IsTriggered: true,
	}

	sessionClient, err := s.GetSessionClient(ctx, 1, job)
	require.NoError(t, err)
	require.NotNil(t, sessionClient)
	require.NotNil(t, userTokenRequest)
	assert.Equal(t, uint64(123), userTokenRequest.UserId)
	assert.Equal(t, uint64(456), userTokenRequest.RepositoryId)
	assert.Equal(t, int64(1), userTokenRequest.AgentId)
}

func TestStoreGeneratedPullData_AsyncSession(t *testing.T) {
	ctx := tokens.NewContext(context.Background())
	obsv := observability.NewNoopExporters()
	ffs := featureflags.NewNoopClient(map[string]bool{
		capi.CopilotAPIAgentSessions: true,
	})

	var capturedSessionID string
	var capturedUpdate capi.SessionUpdate
	updateCalled := false

	capiClient := capi.NewNoopClient()
	capiClient.MockUpdateSession = func(_ context.Context, sessionID string, update capi.SessionUpdate) error {
		updateCalled = true
		capturedSessionID = sessionID
		capturedUpdate = update
		return nil
	}

	_, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	s := New(obsv, ffs, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

	asyncJob := &jobs.Job{
		ID:               "async-job",
		ActorID:          123,
		RepoID:           456,
		OwnerID:          789,
		SessionID:        "test-session-id",
		UseAsyncSessions: true,
	}

	t.Run("persists GeneratedPullData for async job bypassing UseAsyncSessions guard", func(t *testing.T) {
		err := s.StoreGeneratedPullData(ctx, asyncJob, "Async PR Title", "Async PR description")
		require.NoError(t, err)

		require.True(t, updateCalled, "CAPI UpdateSession must be called for async jobs")
		assert.Equal(t, "test-session-id", capturedSessionID)
		require.NotNil(t, capturedUpdate.GeneratedPullData)
		assert.Equal(t, "Async PR Title", capturedUpdate.GeneratedPullData.Title)
		assert.Equal(t, "Async PR description", capturedUpdate.GeneratedPullData.Description)
	})

	t.Run("UpdateSession skips the same async job", func(t *testing.T) {
		updateCalled = false
		err := s.UpdateSession(ctx, asyncJob, capi.SessionUpdate{
			GeneratedPullData: &capi.GeneratedPullData{
				Title:       "Should NOT appear",
				Description: "Should NOT appear",
			},
		})
		require.NoError(t, err)
		assert.False(t, updateCalled, "UpdateSession must skip async jobs")
	})

	t.Run("skips when both title and description are empty", func(t *testing.T) {
		updateCalled = false
		err := s.StoreGeneratedPullData(ctx, asyncJob, "", "")
		require.NoError(t, err)
		assert.False(t, updateCalled, "StoreGeneratedPullData must skip empty title+description")
	})
}

func TestCreateSessionForJob_ResourceNumber(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffs := featureflags.NewNoopClient(map[string]bool{
		capi.CopilotAPIAgentSessions: true,
	})

	var capturedCreate capi.SessionCreate
	capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

	sessionClient := &capi.NoopSessionClient{
		MockCreateSession: func(ctx context.Context, create capi.SessionCreate) (*capi.CreateSessionResponse, error) {
			capturedCreate = create
			return &capi.CreateSessionResponse{ID: "session-1"}, nil
		},
	}
	_ = capiClient

	s := New(obsv, ffs, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", nil, agenticapptest.NewTestProvider(t), nil)

	job := &jobs.Job{
		ID:                "test-job",
		ActorID:           123,
		RepoID:            456,
		OwnerID:           789,
		PullRequestID:     999,
		PullRequestNumber: 42,
	}

	sessionID, err := s.createSessionForJob(ctx, sessionClient, job, capi.SessionStateQueued, "Test Session")
	require.NoError(t, err)
	require.Equal(t, "session-1", sessionID)
	assert.Equal(t, 42, capturedCreate.ResourceNumber)
	assert.Equal(t, int64(999), capturedCreate.ResourceID)
}

func TestGetPreviousJobContext(t *testing.T) {
	obsv := observability.NewNoopExporters()

	setup := func(t *testing.T) (*Service, *memory.Store) {
		t.Helper()
		ffClient := featureflags.NewNoopClient(nil)
		store := memory.NewStore()
		service := &Service{
			obsv:  obsv,
			ffs:   ffClient,
			store: store,
		}
		return service, store
	}

	t.Run("returns ComputeID from most recent previous job", func(t *testing.T) {
		service, store := setup(t)
		ctx := context.Background()

		prevJob := &jobs.Job{
			ID: "prev", OwnerID: 1, RepoID: 2, AssignmentID: "a1",
			ComputeID: "sb-old", Status: jobs.JobStatusCompleted, CreatedAt: 100,
		}
		_, err := store.CreateJob(ctx, prevJob)
		require.NoError(t, err)

		currentJob := &jobs.Job{
			ID: "curr", OwnerID: 1, RepoID: 2, AssignmentID: "a1",
			CreatedAt: 200,
		}
		_, err = store.CreateJob(ctx, currentJob)
		require.NoError(t, err)

		_, computeID, _ := service.GetPreviousJobContext(ctx, currentJob)
		assert.Equal(t, "sb-old", computeID)
	})

	t.Run("returns empty when no previous jobs", func(t *testing.T) {
		service, store := setup(t)
		ctx := context.Background()

		job := &jobs.Job{
			ID: "only", OwnerID: 1, RepoID: 2, AssignmentID: "a2",
			CreatedAt: 100,
		}
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)

		_, computeID, _ := service.GetPreviousJobContext(ctx, job)
		assert.Equal(t, "", computeID)
	})

	t.Run("skips previous jobs without ComputeID", func(t *testing.T) {
		service, store := setup(t)
		ctx := context.Background()

		noCompute := &jobs.Job{
			ID: "no-compute", OwnerID: 1, RepoID: 2, AssignmentID: "a3",
			Status: jobs.JobStatusCompleted, CreatedAt: 100,
		}
		_, err := store.CreateJob(ctx, noCompute)
		require.NoError(t, err)

		currentJob := &jobs.Job{
			ID: "curr3", OwnerID: 1, RepoID: 2, AssignmentID: "a3",
			CreatedAt: 200,
		}
		_, err = store.CreateJob(ctx, currentJob)
		require.NoError(t, err)

		_, computeID, _ := service.GetPreviousJobContext(ctx, currentJob)
		assert.Equal(t, "", computeID)
	})

	t.Run("scopes ComputeID to same actor", func(t *testing.T) {
		service, store := setup(t)
		ctx := context.Background()

		userAJob := &jobs.Job{
			ID: "user-a-job", OwnerID: 1, RepoID: 2, AssignmentID: "a4",
			ComputeID: "sb-user-a", ActorID: 100, Status: jobs.JobStatusCompleted, CreatedAt: 100,
		}
		_, err := store.CreateJob(ctx, userAJob)
		require.NoError(t, err)

		userBJob := &jobs.Job{
			ID: "user-b-job", OwnerID: 1, RepoID: 2, AssignmentID: "a4",
			ActorID: 200, CreatedAt: 200,
		}
		_, err = store.CreateJob(ctx, userBJob)
		require.NoError(t, err)

		_, computeID, _ := service.GetPreviousJobContext(ctx, userBJob)
		assert.Equal(t, "", computeID)

		userAFollowUp := &jobs.Job{
			ID: "user-a-followup", OwnerID: 1, RepoID: 2, AssignmentID: "a4",
			ActorID: 100, CreatedAt: 300,
		}
		_, err = store.CreateJob(ctx, userAFollowUp)
		require.NoError(t, err)
		_, computeID, _ = service.GetPreviousJobContext(ctx, userAFollowUp)
		assert.Equal(t, "sb-user-a", computeID)
	})

	t.Run("returns both session IDs and ComputeID", func(t *testing.T) {
		service, store := setup(t)
		ctx := context.Background()

		prevJob := &jobs.Job{
			ID: "prev-both", OwnerID: 1, RepoID: 2, AssignmentID: "a5",
			ComputeID: "sb-prev", SessionID: "sess-1", ActorID: 42,
			Status: jobs.JobStatusCompleted, CreatedAt: 100,
		}
		_, err := store.CreateJob(ctx, prevJob)
		require.NoError(t, err)

		currentJob := &jobs.Job{
			ID: "curr-both", OwnerID: 1, RepoID: 2, AssignmentID: "a5",
			ActorID: 42, CreatedAt: 200,
		}
		_, err = store.CreateJob(ctx, currentJob)
		require.NoError(t, err)

		sessionIDs, computeID, _ := service.GetPreviousJobContext(ctx, currentJob)
		assert.Equal(t, []string{"sess-1"}, sessionIDs)
		assert.Equal(t, "sb-prev", computeID)
	})
}
