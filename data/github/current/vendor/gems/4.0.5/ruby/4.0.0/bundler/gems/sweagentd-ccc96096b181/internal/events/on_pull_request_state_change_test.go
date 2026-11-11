package events

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOnPullRequestStateChange(t *testing.T) {
	truePtr := true
	falsePtr := false

	tests := []struct {
		name                  string
		pullRequestState      string
		pullRequestIsDraft    *bool
		expectedResourceState capi.ResourceState
		shouldUpdateSessions  bool
	}{
		{
			name:                  "reopened draft PR sets draft state",
			pullRequestState:      PullRequestStateOpen,
			pullRequestIsDraft:    &truePtr,
			expectedResourceState: capi.ResourceStateDraft,
			shouldUpdateSessions:  true,
		},
		{
			name:                  "reopened non-draft PR sets open state",
			pullRequestState:      PullRequestStateOpen,
			pullRequestIsDraft:    &falsePtr,
			expectedResourceState: capi.ResourceStateOpen,
			shouldUpdateSessions:  true,
		},
		{
			name:                  "closed PR sets closed state",
			pullRequestState:      PullRequestStateClosed,
			pullRequestIsDraft:    nil,
			expectedResourceState: capi.ResourceStateClosed,
			shouldUpdateSessions:  true,
		},
		{
			name:                  "merged PR sets merged state",
			pullRequestState:      PullRequestStateMerged,
			pullRequestIsDraft:    nil,
			expectedResourceState: capi.ResourceStateMerged,
			shouldUpdateSessions:  true,
		},
		{
			name:                  "unknown state skips processing",
			pullRequestState:      "unknown",
			pullRequestIsDraft:    nil,
			expectedResourceState: "",
			shouldUpdateSessions:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := requestctx.NewContext(context.Background())
			obsv := observability.NewNoopExporters()

			// Track session API calls
			var patchCalled bool
			var capturedPatches []capi.SessionPatch

			// Set up CAPI client with mock that will be copied to session clients
			mockCapiClient := &capi.NoopClient{
				MockPatchSessions: func(ctx context.Context, patches []capi.SessionPatch) error {
					patchCalled = true
					capturedPatches = patches
					return nil
				},
			}

			// Enable the feature flag for agent sessions
			ffClient := featureflags.NewNoopClient(map[string]bool{
				capi.CopilotAPIAgentSessions: true,
			})

			// Create memory store and populate with test assignment and jobs
			mockJobsStore := memory.NewStore()

			prID := int64(123)
			prNumber := 456

			// Create test assignment
			testAssignment := &jobs.Assignment{
				ID:                "assignment-1",
				OwnerID:           456,
				RepoID:            789,
				PullRequestID:     prID,
				PullRequestNumber: prNumber,
			}

			// Add assignment to store
			_, err := mockJobsStore.CreateAssignment(ctx, testAssignment)
			require.NoError(t, err)

			// Create test jobs
			testJobs := []*jobs.Job{
				{
					ID:           "job-1",
					SessionID:    "session-1",
					ActorID:      123,
					AssignmentID: "assignment-1",
					OwnerID:      456,
					RepoID:       789,
				},
				{
					ID:           "job-2",
					SessionID:    "session-2",
					ActorID:      123,
					AssignmentID: "assignment-1",
					OwnerID:      456,
					RepoID:       789,
				},
				{
					ID:           "job-3",
					SessionID:    "", // Job without session should be skipped
					ActorID:      123,
					AssignmentID: "assignment-1",
					OwnerID:      456,
					RepoID:       789,
				},
			}

			// Add jobs to store
			for _, job := range testJobs {
				_, err := mockJobsStore.CreateJob(ctx, job)
				require.NoError(t, err)
			}

			handler, _, _ := NewTestHandler(t, obsv, mockCapiClient, ffClient, mockJobsStore, githubtwirp.NewNoopClient(), nil)

			ownerID := int64(456)
			repoID := int64(789)
			event := PullRequestStateChangedEvent{
				PullRequest: &PullRequest{
					ID:      prID,
					Number:  prNumber, // Add the Number field
					IsDraft: tt.pullRequestIsDraft,
					State:   tt.pullRequestState,
				},
				Actor: &Actor{
					ID: 123,
				},
				Repo: &Repository{
					ID:      repoID,
					OwnerID: ownerID,
				},
			}

			// Test the full handler flow
			err = handler.OnPullRequestStateChanged(ctx, event)
			require.NoError(t, err)

			if tt.shouldUpdateSessions {
				assert.True(t, patchCalled, "Should call PatchSessions")
				assert.Len(t, capturedPatches, 2, "Should create exactly 2 patches (skipping empty SessionID)")

				// Check that both sessions are included in the patch
				var sessionIDs []string
				for _, patch := range capturedPatches {
					sessionIDs = append(sessionIDs, patch.SessionID)
					assert.Equal(t, uint64(123), patch.UserID, "Should use correct actor ID as user ID")
					assert.Equal(t, string(tt.expectedResourceState), patch.ResourceState, "Should set correct resource state")
				}
				assert.Contains(t, sessionIDs, "session-1", "Should update session-1")
				assert.Contains(t, sessionIDs, "session-2", "Should update session-2")
			} else {
				assert.False(t, patchCalled, "Should not call PatchSessions for unknown events")
			}
		})
	}
}

func TestOnPullRequestStateChangeInvalidPR(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	handler, _, _ := NewTestHandler(t, obsv, nil, nil, nil, nil, nil)

	tests := []struct {
		name          string
		event         PullRequestStateChangedEvent
		errorContains string
	}{
		{
			name: "nil pull request",
			event: PullRequestStateChangedEvent{
				PullRequest: nil,
			},
		},
		{
			name: "nil pull request ID",
			event: PullRequestStateChangedEvent{
				PullRequest: &PullRequest{},
			},
		},
		{
			name: "nil pull request state",
			event: PullRequestStateChangedEvent{
				PullRequest: &PullRequest{
					ID:    123,
					State: "",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := handler.OnPullRequestStateChanged(ctx, tt.event)
			assert.NoError(t, err)
		})
	}
}

func TestOnPullRequestStateChangeNoAssignment(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	mockJobsStore := memory.NewStore()
	mockCapiClient := &capi.NoopClient{}

	handler, _, _ := NewTestHandler(t, obsv, mockCapiClient, nil, mockJobsStore, githubtwirp.NewNoopClient(), nil)

	prNumber := 456
	event := PullRequestStateChangedEvent{
		PullRequest: &PullRequest{
			ID:     123,
			Number: prNumber,
			State:  PullRequestStateClosed,
		},
		Actor: &Actor{
			ID: 123,
		},
		Repo: &Repository{
			ID:      789,
			OwnerID: 456,
		},
	}

	// Should succeed but do nothing when no assignment is found
	err := handler.OnPullRequestStateChanged(ctx, event)
	require.NoError(t, err)
}

// TestOnPullRequestStateChangeCancelsRunningJobs tests that running jobs are cancelled when PR is closed or merged
func TestOnPullRequestStateChangeCancelsRunningJobs(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	obsv := observability.NewNoopExporters()

	// Create test assignment and jobs with different states
	assignment := &jobs.Assignment{
		ID:                "test-assignment",
		PullRequestID:     123,
		PullRequestNumber: 456,
		RepoID:            789,
		OwnerID:           456,
	}

	runningJob := &jobs.Job{
		ID:           "running-job-1",
		AssignmentID: assignment.ID,
		SessionID:    "session-1",
		Status:       jobs.JobStatusRunning,
		ActorID:      123,
		OwnerID:      456,
		RepoID:       789,
		ComputeID:    "12345", // Workflow run ID as string
	}

	completedJob := &jobs.Job{
		ID:           "completed-job-1",
		AssignmentID: assignment.ID,
		SessionID:    "session-2",
		Status:       jobs.JobStatusCompleted,
		ActorID:      123,
		OwnerID:      456,
		RepoID:       789,
		ComputeID:    "67890", // Workflow run ID as string
	}

	testCases := []struct {
		name            string
		prState         string
		expectJobCancel bool
	}{
		{
			name:            "closed PR cancels running jobs",
			prState:         PullRequestStateClosed,
			expectJobCancel: true,
		},
		{
			name:            "merged PR cancels running jobs",
			prState:         PullRequestStateMerged,
			expectJobCancel: true,
		},
		{
			name:            "open PR does not cancel jobs",
			prState:         PullRequestStateOpen,
			expectJobCancel: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Create handler without feature flag setup since job cancellation is now default
			ffClient := featureflags.NewNoopClient(map[string]bool{})

			handler, _, testExecutor := NewTestHandler(t, obsv, &capi.NoopClient{}, ffClient, nil, nil, nil)

			// Set up test data
			handler.jobsStore.CreateAssignment(ctx, assignment)
			handler.jobsStore.CreateJob(ctx, runningJob)
			handler.jobsStore.CreateJob(ctx, completedJob)

			event := PullRequestStateChangedEvent{
				PullRequest: &PullRequest{
					ID:     123,
					Number: 456,
					State:  tc.prState,
				},
				Actor: &Actor{
					ID: 123,
				},
				Repo: &Repository{
					ID:      789,
					OwnerID: 456,
				},
			}

			err := handler.OnPullRequestStateChanged(ctx, event)
			require.NoError(t, err)

			// Check if job cancellation happened as expected
			terminateAgentCalls := testExecutor.TerminateAgentCalls()
			if tc.expectJobCancel {
				assert.Len(t, terminateAgentCalls, 1, "expected exactly one job cancellation")

				// Verify the parameters of the cancellation call
				call := terminateAgentCalls[0]
				assert.Equal(t, int64(456), call.OwnerID)
				assert.Equal(t, int64(789), call.RepoID)
				assert.Equal(t, "test-owner", call.RepoOwner)
				assert.Equal(t, "test-repo", call.RepoName)
				assert.Equal(t, "12345", call.ComputeID, "should only terminate the running job")
			} else {
				assert.Len(t, terminateAgentCalls, 0, "expected no job cancellations")
			}
		})
	}
}
