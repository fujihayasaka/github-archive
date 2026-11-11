package agentcallback

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	js "github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/tips"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestExtractCoreBodyAndSuffixFromPR(t *testing.T) {
	m := &jobManager{}

	tests := []struct {
		name           string
		prBody         string
		expectedCore   string
		expectedSuffix string
		expectedTip    string
	}{
		{
			name:           "empty body",
			prBody:         "",
			expectedCore:   "",
			expectedSuffix: "",
			expectedTip:    "",
		},
		{
			name:           "core body only",
			prBody:         "This is the main PR description",
			expectedCore:   "This is the main PR description",
			expectedSuffix: "",
			expectedTip:    "",
		},
		{
			name: "body with suffix separator only",
			prBody: "This is the main PR description" +
				js.PullRequestBodySuffixSeparator +
				"This is the suffix content",
			expectedCore:   "This is the main PR description",
			expectedSuffix: js.PullRequestBodySuffixSeparator + "This is the suffix content",
			expectedTip:    "",
		},
		{
			name: "body with tip separator only",
			prBody: "This is the main PR description" +
				tips.PullRequestBodyTipSeparator +
				"This is a helpful tip",
			expectedCore:   "This is the main PR description",
			expectedSuffix: "",
			expectedTip:    tips.PullRequestBodyTipSeparator + "This is a helpful tip",
		},
		{
			name: "body with both suffix and tip separators",
			prBody: "This is the main PR description" +
				js.PullRequestBodySuffixSeparator +
				"This is the suffix content" +
				tips.PullRequestBodyTipSeparator +
				"This is a helpful tip",
			expectedCore:   "This is the main PR description",
			expectedSuffix: js.PullRequestBodySuffixSeparator + "This is the suffix content",
			expectedTip:    tips.PullRequestBodyTipSeparator + "This is a helpful tip",
		},
		{
			name: "multiline core body with suffix",
			prBody: "# Main Title\n\n" +
				"This is a detailed description\n" +
				"with multiple lines\n\n" +
				"- Item 1\n" +
				"- Item 2" +
				js.PullRequestBodySuffixSeparator +
				"Additional context from agent",
			expectedCore: "# Main Title\n\n" +
				"This is a detailed description\n" +
				"with multiple lines\n\n" +
				"- Item 1\n" +
				"- Item 2",
			expectedSuffix: js.PullRequestBodySuffixSeparator + "Additional context from agent",
			expectedTip:    "",
		},
		{
			name: "suffix with newlines",
			prBody: "Core content" +
				js.PullRequestBodySuffixSeparator +
				"Suffix line 1\n" +
				"Suffix line 2\n\n" +
				"Suffix line 3",
			expectedCore: "Core content",
			expectedSuffix: js.PullRequestBodySuffixSeparator + "Suffix line 1\n" +
				"Suffix line 2\n\n" +
				"Suffix line 3",
			expectedTip: "",
		},
		{
			name: "suffix followed by tip",
			prBody: "Core content" +
				js.PullRequestBodySuffixSeparator +
				"Suffix content" +
				tips.PullRequestBodyTipSeparator +
				"💡 **Tip**: This is helpful advice",
			expectedCore:   "Core content",
			expectedSuffix: js.PullRequestBodySuffixSeparator + "Suffix content",
			expectedTip:    tips.PullRequestBodyTipSeparator + "💡 **Tip**: This is helpful advice",
		},
		{
			name: "empty suffix section followed by tip",
			prBody: "Core content" +
				js.PullRequestBodySuffixSeparator +
				tips.PullRequestBodyTipSeparator +
				"💡 **Tip**: This is helpful advice",
			expectedCore:   "Core content",
			expectedSuffix: js.PullRequestBodySuffixSeparator,
			expectedTip:    tips.PullRequestBodyTipSeparator + "💡 **Tip**: This is helpful advice",
		},
		{
			name: "tip appears before suffix (unusual order)",
			prBody: "Core content" +
				tips.PullRequestBodyTipSeparator +
				"This is a tip" +
				js.PullRequestBodySuffixSeparator +
				"This is a suffix",
			expectedCore:   "Core content",
			expectedSuffix: js.PullRequestBodySuffixSeparator + "This is a suffix",
			expectedTip:    tips.PullRequestBodyTipSeparator + "This is a tip",
		},
		{
			name: "multiple tip sections",
			prBody: "Core content" +
				tips.PullRequestBodyTipSeparator +
				"First tip\n\n💡 Second tip\n\nThird tip",
			expectedCore:   "Core content",
			expectedSuffix: "",
			expectedTip:    tips.PullRequestBodyTipSeparator + "First tip\n\n💡 Second tip\n\nThird tip",
		},
		{
			name: "complex real-world example",
			prBody: "## Summary\n\nFixed the login bug\n\n" +
				"### Changes\n- Updated auth logic\n- Fixed tests" +
				js.PullRequestBodySuffixSeparator +
				"Generated by Copilot Coding Agent" +
				tips.PullRequestBodyTipSeparator +
				"💡 **Tip**: Consider adding more error handling\n\n" +
				"🔬 **Experiment**: This PR was created with enhanced AI assistance",
			expectedCore: "## Summary\n\nFixed the login bug\n\n" +
				"### Changes\n- Updated auth logic\n- Fixed tests",
			expectedSuffix: js.PullRequestBodySuffixSeparator + "Generated by Copilot Coding Agent",
			expectedTip: tips.PullRequestBodyTipSeparator + "💡 **Tip**: Consider adding more error handling\n\n" +
				"🔬 **Experiment**: This PR was created with enhanced AI assistance",
		},
		{
			name: "new format: core -> original prompt -> user suffix",
			prBody: "## Summary\n\nFixed the bug" +
				js.PullRequestBodyOriginalPromptSeparator +
				"<details>Original: Fix bug #123</details>" +
				js.PullRequestBodySuffixSeparator +
				"Fixes #123",
			expectedCore: "## Summary\n\nFixed the bug",
			expectedSuffix: js.PullRequestBodyOriginalPromptSeparator +
				"<details>Original: Fix bug #123</details>" +
				js.PullRequestBodySuffixSeparator +
				"Fixes #123",
			expectedTip: "",
		},
		{
			name: "new format: core -> original prompt -> user suffix -> tip",
			prBody: "## Summary\n\nFixed the bug" +
				js.PullRequestBodyOriginalPromptSeparator +
				"<details>Original: Fix bug #123</details>\n\n**Custom Agent:** Test Agent" +
				js.PullRequestBodySuffixSeparator +
				"Fixes #123" +
				tips.PullRequestBodyTipSeparator +
				"💡 Tip: Add tests",
			expectedCore: "## Summary\n\nFixed the bug",
			expectedSuffix: js.PullRequestBodyOriginalPromptSeparator +
				"<details>Original: Fix bug #123</details>\n\n**Custom Agent:** Test Agent" +
				js.PullRequestBodySuffixSeparator +
				"Fixes #123",
			expectedTip: tips.PullRequestBodyTipSeparator + "💡 Tip: Add tests",
		},
		{
			name: "new format: core -> original prompt only (no user suffix)",
			prBody: "## Summary\n\nFixed the bug" +
				js.PullRequestBodyOriginalPromptSeparator +
				"<details>Original: Fix the authentication bug</details>",
			expectedCore: "## Summary\n\nFixed the bug",
			expectedSuffix: js.PullRequestBodyOriginalPromptSeparator +
				"<details>Original: Fix the authentication bug</details>",
			expectedTip: "",
		},
		{
			name: "new format: core -> original prompt -> tip (no user suffix)",
			prBody: "## Summary\n\nFixed the bug" +
				js.PullRequestBodyOriginalPromptSeparator +
				"<details>Original prompt</details>" +
				tips.PullRequestBodyTipSeparator +
				"💡 Tip: Consider edge cases",
			expectedCore: "## Summary\n\nFixed the bug",
			expectedSuffix: js.PullRequestBodyOriginalPromptSeparator +
				"<details>Original prompt</details>",
			expectedTip: tips.PullRequestBodyTipSeparator + "💡 Tip: Consider edge cases",
		},
		{
			name: "new format: original prompt comes before old suffix separator (backward compat)",
			prBody: "Core content" +
				js.PullRequestBodyOriginalPromptSeparator +
				"Original prompt content" +
				js.PullRequestBodySuffixSeparator +
				"Old style suffix with Fixes #123",
			expectedCore: "Core content",
			expectedSuffix: js.PullRequestBodyOriginalPromptSeparator +
				"Original prompt content" +
				js.PullRequestBodySuffixSeparator +
				"Old style suffix with Fixes #123",
			expectedTip: "",
		},
		{
			name: "old format still works: core -> suffix only (no original prompt separator)",
			prBody: "Core content" +
				js.PullRequestBodySuffixSeparator +
				"<details>Original prompt was here</details>\nFixes #123",
			expectedCore: "Core content",
			expectedSuffix: js.PullRequestBodySuffixSeparator +
				"<details>Original prompt was here</details>\nFixes #123",
			expectedTip: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			core, suffix, tip := m.extractCoreBodyAndSuffixFromPR(tt.prBody)
			assert.Equal(t, tt.expectedCore, core, "Core body should match expected")
			assert.Equal(t, tt.expectedSuffix, suffix, "Suffix should match expected")
			assert.Equal(t, tt.expectedTip, tip, "Tip should match expected")
		})
	}
}

func TestDetermineTipToAddSkipsNonCopilotApp(t *testing.T) {
	copilot := agenticapptest.NewTestCopilotWithID(t, 101)
	nonCopilotID := int64(202)
	nonCopilot := agenticapptest.NewTestApp(nonCopilotID)

	manager := &jobManager{
		ffClient: featureflags.NewNoopClient(map[string]bool{
			"copilot_swe_agent_tips":            true,
			"copilot_swe_agent_tips_onboarding": true,
		}),
		appProvider: agenticapp.NewProvider(copilot, nonCopilot),
	}

	job := &jobs.Job{
		AgentID: nonCopilotID,
	}

	repoOwner := "owner"
	repoName := "name"

	repo := &gg.Repository{
		Owner: &gg.User{
			Login: &repoOwner,
		},
		Name: &repoName,
	}

	// Existing tips should be preserved
	require.Equal(t, "existing", manager.determineTipToAdd(context.Background(), job, repo, "existing"))

	// Tips should not be added for non-Copilot apps
	require.Empty(t, manager.determineTipToAdd(context.Background(), job, repo, ""))

	// Tips should be added for Copilot jobs
	copilotJob := *job
	copilotJob.AgentID = copilot.AppID()
	tip := manager.determineTipToAdd(context.Background(), &copilotJob, repo, "")
	require.NotEmpty(t, tip)
	require.Contains(t, tip, tips.PullRequestBodyTipSeparator)
	require.Contains(t, tip, "Let Copilot coding agent")
}

func TestHandleJobUpdate_StartedAtTracking(t *testing.T) {
	tests := []struct {
		name                string
		initialStartedAt    int64
		initialStatus       jobs.JobStatus
		expectSaveJobCalled bool
		expectStartedAtSet  bool
	}{
		{
			name:                "StartedAt not set",
			initialStatus:       jobs.JobStatusQueued,
			expectSaveJobCalled: true,
			expectStartedAtSet:  true,
		},
		{
			name:                "StartedAt already set, Queued",
			initialStartedAt:    time.Now().Unix() - 100,
			initialStatus:       jobs.JobStatusQueued,
			expectSaveJobCalled: true,
		},
		{
			name:                "StartedAt already set, Running",
			initialStartedAt:    time.Now().Unix() - 100,
			initialStatus:       jobs.JobStatusRunning,
			expectSaveJobCalled: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := t.Context()

			mockJobSvc := &mockJobService{}
			mockJobsStore := memory.NewStore()
			mockClients := &github.NoopClientFactory{}
			mockGHTwirp := githubtwirp.NewNoopClient()
			obsv := observability.NewNoopExporters()

			ffClient := featureflags.NewNoopClient(nil)

			updateJobCalled := false
			var capturedStatus jobs.JobStatus
			mockJobSvc.mockUpdateFromExecutionResult = func(ctx context.Context, job *jobs.Job, newStatus jobs.JobStatus) error {
				updateJobCalled = true
				capturedStatus = newStatus
				// Apply the changes to the job object like the real implementation would
				job.Status = newStatus
				if job.StartedAt == 0 {
					job.StartedAt = time.Now().Unix()
				}
				return nil
			}

			manager := &jobManager{
				obsv:       obsv,
				jobsStore:  mockJobsStore,
				jobService: mockJobSvc,
				clients:    mockClients,
				ghTwirp:    mockGHTwirp,
				ffClient:   ffClient,
			}

			// Create test job
			originalStartedAt := tt.initialStartedAt
			job := &jobs.Job{
				ID:         "test-job-id",
				ActorID:    123,
				StartedAt:  originalStartedAt,
				Status:     tt.initialStatus,
				LaunchedAt: time.Now().Unix() - 200, // Set LaunchedAt to test the duration calculation
			}

			_, err := mockJobsStore.CreateJob(ctx, job)
			require.NoError(t, err)

			update := JobUpdate{
				Kind: AgentUpdateKindProgress,
			}

			req := httptest.NewRequest(http.MethodPost, "/test", http.NoBody)

			_, err = manager.HandleJobUpdate(ctx, req, job, update, 123)

			require.NoError(t, err)

			if tt.expectStartedAtSet {
				require.Greater(t, job.StartedAt, int64(0))
				require.NotEqual(t, originalStartedAt, job.StartedAt)
			} else {
				require.Equal(t, originalStartedAt, job.StartedAt)
			}

			if tt.expectSaveJobCalled {
				require.True(t, updateJobCalled)
				require.Equal(t, jobs.JobStatusRunning, capturedStatus)
			}
		})
	}
}
