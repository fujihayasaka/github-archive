package events

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOnPullRequestStateChangeInvalidPR(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	handler, _, _ := NewTestHandler(t, obsv, nil, nil, nil, nil, nil)
	handler.automationLookup = nil

	tests := []struct {
		name  string
		event PullRequestStateChangedEvent
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

	handler, _, _ := NewTestHandler(t, obsv, &capi.NoopClient{}, nil, mockJobsStore, nil, nil)
	handler.automationLookup = nil

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
			ffClient := featureflags.NewNoopClient(map[string]bool{})

			handler, _, testExecutor := NewTestHandler(t, obsv, &capi.NoopClient{}, ffClient, nil, nil, nil)
			// Service-style handler: nil automationLookup routes to cancellation path.
			handler.automationLookup = nil

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

// TestOnPullRequestStateChange_DoesNotCancelMergedTriggerJobs asserts that a
// Worker-built merged-trigger assignment (which deliberately omits the PR
// ID/number, since those identify the cancellable agent assignment) is not
// matched by the Service cancellation lookup. This protects against a race
// where Worker fires the merged trigger and Service then cancels the resulting
// job for the same merge event.
func TestOnPullRequestStateChange_DoesNotCancelMergedTriggerJobs(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	handler, _, testExecutor := NewTestHandler(t, obsv, &capi.NoopClient{}, ffClient, nil, nil, nil)
	handler.automationLookup = nil

	// Worker-style merged-trigger assignment: no PullRequestID/PullRequestNumber.
	workerAssignment := &jobs.Assignment{
		ID:      "worker-merged-assignment",
		RepoID:  789,
		OwnerID: 456,
	}
	workerJob := &jobs.Job{
		ID:           "worker-merged-job",
		AssignmentID: workerAssignment.ID,
		SessionID:    "session-worker",
		Status:       jobs.JobStatusRunning,
		ActorID:      123,
		OwnerID:      456,
		RepoID:       789,
		ComputeID:    "55555",
	}

	handler.jobsStore.CreateAssignment(ctx, workerAssignment)
	handler.jobsStore.CreateJob(ctx, workerJob)

	event := PullRequestStateChangedEvent{
		PullRequest: &PullRequest{
			ID:     123,
			Number: 456,
			State:  PullRequestStateMerged,
		},
		Actor: &Actor{ID: 123},
		Repo:  &Repository{ID: 789, OwnerID: 456},
	}

	err := handler.OnPullRequestStateChanged(ctx, event)
	require.NoError(t, err)
	assert.Empty(t, testExecutor.TerminateAgentCalls(), "Worker-built merged-trigger jobs must not be cancelled by Service cancellation lookup")
}

// TestOnPullRequestStateChange_SkipsAppsOptingOut covers the
// AgenticAppSkipPRCloseCancel opt-out path: when an agentic app implements
// the interface and returns true, AND the rollout flag is enabled for the
// repo/owner, the running job is left alone. When the flag is off, the
// job is cancelled regardless (interface implementation is a no-op without
// the flag). Apps that do not implement the interface are unaffected.
func TestOnPullRequestStateChange_SkipsAppsOptingOut(t *testing.T) {
	const ccrAppID int64 = 9001

	assignment := &jobs.Assignment{
		ID:                "assignment-ccr-skip",
		PullRequestID:     123,
		PullRequestNumber: 456,
		RepoID:            789,
		OwnerID:           456,
	}
	ccrRunningJob := &jobs.Job{
		ID:           "ccr-running-job",
		AssignmentID: assignment.ID,
		SessionID:    "session-ccr",
		Status:       jobs.JobStatusRunning,
		ActorID:      123,
		AgentID:      ccrAppID,
		OwnerID:      456,
		RepoID:       789,
		ComputeID:    "ccr-compute",
	}

	event := PullRequestStateChangedEvent{
		PullRequest: &PullRequest{ID: 123, Number: 456, State: PullRequestStateMerged},
		Actor:       &Actor{ID: 123},
		Repo:        &Repository{ID: 789, OwnerID: 456},
	}

	tests := []struct {
		name         string
		ffEnabled    bool
		expectCancel bool
	}{
		{name: "flag off: opt-in app job is still cancelled", ffEnabled: false, expectCancel: true},
		{name: "flag on: opt-in app job is left running", ffEnabled: true, expectCancel: false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ctx := requestctx.NewContext(context.Background())
			obsv := observability.NewNoopExporters()
			ffClient := featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSkipPRCloseCancel: tc.ffEnabled,
			})

			handler, _, testExecutor := NewTestHandler(t, obsv, &capi.NoopClient{}, ffClient, nil, nil, nil)
			handler.automationLookup = nil

			ccrApp := agenticapp.NewCopilotCodeReview(
				ccrAppID,
				agenticapp.CopilotCodeReviewComputeSlug,
				ccrAppID+1,
				"copilot-pull-request-reviewer[bot]",
				"commit-login",
				"commit@email.com",
			)
			handler.appProvider = agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)

			_, err := handler.jobsStore.CreateAssignment(ctx, assignment)
			require.NoError(t, err)
			_, err = handler.jobsStore.CreateJob(ctx, ccrRunningJob)
			require.NoError(t, err)

			require.NoError(t, handler.OnPullRequestStateChanged(ctx, event))

			if tc.expectCancel {
				assert.Len(t, testExecutor.TerminateAgentCalls(), 1, "opt-in app job should still be cancelled when flag is off")
			} else {
				assert.Empty(t, testExecutor.TerminateAgentCalls(), "opt-in app job should be skipped when flag is on")
			}
		})
	}
}
