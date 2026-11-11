package launcher

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLaunchAgentOpts_Immutability(t *testing.T) {
	// This test verifies that functions receiving *LaunchAgentOpts do not mutate the struct.
	// Even though we pass pointers for efficiency, functions should treat opts as read-only.
	t.Run("addAgentVariables does not mutate opts", func(t *testing.T) {
		opts := &LaunchAgentOpts{
			Model:            "original-model",
			ProblemStatement: "test problem",
			Action:           "fix",
			JobID:            "job-123",
			BranchName:       "main",
			GitHubBaseCommit: "abc123",
			IssueNumber:      42,
			Nonce:            "test-nonce",
			Agent:            agenticapptest.NewTestCopilot(t),
		}

		launcherOpts := &AgentLauncherOpts{
			ModelOverride:     "override-model",
			RuntimeSHA:        "v1.0.0",
			CopilotAPIURL:     "https://api.github.com",
			AgentCallbackURL:  "https://callback.github.com",
			UploadsURL:        "https://uploads.github.com",
			DownloadsURL:      "https://downloads.github.com",
			SecretScanningURL: "https://secrets.github.com",
		}

		vars := &Variables{}
		addAgentVariables(context.Background(), nil, vars, launcherOpts, opts, false)

		// The original opts.Model should remain unchanged even though ModelOverride was set
		assert.Equal(t, "original-model", opts.Model, "opts.Model should not be mutated by addAgentVariables")

		// But the generated variable should use the override
		assert.Equal(t, "override-model", (*vars)["COPILOT_AGENT_MODEL"].Value, "COPILOT_AGENT_MODEL should use ModelOverride")
	})

	t.Run("GetVariables does not mutate opts", func(t *testing.T) {
		opts := &LaunchAgentOpts{
			Model:             "original-model",
			ProblemStatement:  "test problem",
			Action:            "fix",
			JobID:             "job-123",
			BranchName:        "main",
			GitHubBaseCommit:  "abc123",
			IssueNumber:       42,
			Nonce:             "test-nonce",
			GitHubRepo:        "owner/repo",
			GitHubRepoOwner:   "owner",
			GitHubRepoOwnerID: 123,
			GitHubRepoID:      456,
			Agent:             agenticapptest.NewTestCopilot(t),
		}

		launcherOpts := ExternalLauncherOpts{
			AgentLauncherOpts: AgentLauncherOpts{
				ModelOverride:     "override-model",
				RuntimeSHA:        "v1.0.0",
				CopilotAPIURL:     "https://api.github.com",
				AgentCallbackURL:  "https://callback.github.com",
				UploadsURL:        "https://uploads.github.com",
				DownloadsURL:      "https://downloads.github.com",
				SecretScanningURL: "https://secrets.github.com",
			},
			GitHubServerURL: "https://github.com",
		}

		// Store original values
		originalModel := opts.Model
		originalAction := opts.Action
		originalJobID := opts.JobID

		_ = GetVariables(context.Background(), nil, launcherOpts, opts, nil, false)

		// Verify opts was not mutated
		assert.Equal(t, originalModel, opts.Model, "opts.Model should not be mutated")
		assert.Equal(t, originalAction, opts.Action, "opts.Action should not be mutated")
		assert.Equal(t, originalJobID, opts.JobID, "opts.JobID should not be mutated")
	})

	t.Run("GenerateRunName does not mutate opts", func(t *testing.T) {
		opts := &LaunchAgentOpts{
			RunName:     "test run name",
			Action:      "fix",
			PRNumber:    123,
			IssueNumber: 456,
			Agent:       agenticapptest.NewTestCopilot(t),
		}

		originalRunName := opts.RunName
		originalAction := opts.Action

		_ = GenerateRunName(opts)

		assert.Equal(t, originalRunName, opts.RunName, "opts.RunName should not be mutated")
		assert.Equal(t, originalAction, opts.Action, "opts.Action should not be mutated")
	})
}

func TestLaunchAgentOpts_JSONSerialization(t *testing.T) {
	opts := LaunchAgentOpts{
		GitHubRepo:        "owner/repo",
		GitHubRepoID:      12345,
		GitHubRepoName:    "repo",
		GitHubRepoOwner:   "owner",
		GitHubRepoOwnerID: 67890,
		GitHubBaseCommit:  "abc123",
		IssueNumber:       42,
		ProblemStatement:  "Fix the bug",
		ContentFilterMode: "strict",
		RunName:           "test-run",
		JobID:             "job-123",
		Action:            "test-action",
		Push:              true,
		Model:             "gpt-4",
		PRNumber:          100,
		BranchName:        "feature-branch",
		ActorID:           11111,
		ActorLogin:        "testuser",
		GitHubToken:       "ghp_secret_token_that_should_not_be_serialized",
		CommitCount:       5,
		UseSessions:       true,
		SessionID:         "session-456",
		Nonce:             "secret_nonce_that_should_not_be_serialized",
	}

	// Fields expected to be present in the JSON serialization. Used to ensure new
	// fields are added to the object are intended to be included in the database.
	expectedFields := []string{
		"github_repo",
		"github_repo_id",
		"github_repo_name",
		"github_repo_owner",
		"github_repo_owner_id",
		"github_base_commit",
		"issue_number",
		"problem_statement",
		"content_filter_mode",
		"run_name",
		"job_id",
		"job_event_type",
		"action",
		"push",
		"model",
		"pr_number",
		"branch_name",
		"actor_id",
		"actor_login",
		"commit_count",
		"use_sessions",
		"use_async_sessions",
		"session_id",
	}

	// Fields that should not be serialized, marked with json:"-" in the struct
	// definition and should not appear in the JSON output or in the database.
	ignoredFields := []string{
		"github_token",        // This should not be serialized
		"nonce",               // This should not be serialized
		"previous_session_id", // This should not be serialized
	}

	// Serialize to JSON
	jsonData, err := json.Marshal(opts)
	require.NoError(t, err, "Failed to marshal LaunchAgentOpts to JSON")

	// Parse back to map to check field presence
	var jsonMap map[string]any
	err = json.Unmarshal(jsonData, &jsonMap)
	require.NoError(t, err, "Failed to unmarshal JSON to map")

	// Test that ignored fields are not present in the serialized JSON
	for field := range jsonMap {
		require.NotContains(t, ignoredFields, field, "Field `%s` should not be present in JSON", field)
	}

	// Test all expected fields are present in the serialized JSON
	for _, field := range expectedFields {
		require.Contains(t, jsonMap, field, "Expected field `%s` to be present in JSON", field)
	}

	// Finally, ensure new fields that shouldn't be serialized are caught
	for field := range jsonMap {
		require.Contains(t, expectedFields, field, "Unexpected field in JSON: `%s`", field)
	}
}
