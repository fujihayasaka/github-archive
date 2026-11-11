package launcher

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

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
