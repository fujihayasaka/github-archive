package launcher

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFirewallFeatureFlagging(t *testing.T) {
	ctx := context.Background()
	ffClientEnabled := featureflags.NewNoopClient(map[string]bool{copilotSWEAgentFirewallFFName: true})
	ffClientDisabled := featureflags.NewNoopClient(map[string]bool{copilotSWEAgentFirewallFFName: false})

	// FF enabled, config is disabled
	assert.True(t, isFirewallEnabledByDefault(ctx, ffClientEnabled, &AgentLauncherOpts{AgentFirewallEnabledDefault: false}))
	// FF enabled, config is enabled
	assert.True(t, isFirewallEnabledByDefault(ctx, ffClientEnabled, &AgentLauncherOpts{AgentFirewallEnabledDefault: true}))
	// FF disabled, config is disabled
	assert.False(t, isFirewallEnabledByDefault(ctx, ffClientDisabled, &AgentLauncherOpts{AgentFirewallEnabledDefault: false}))
	// FF enabled, config is enabled
	assert.True(t, isFirewallEnabledByDefault(ctx, ffClientDisabled, &AgentLauncherOpts{AgentFirewallEnabledDefault: true}))
}

func TestValidateRequiredVariables(t *testing.T) {
	tests := []struct {
		name      string
		vars      Variables
		wantError bool
		errorMsg  string
	}{
		{
			name: "all required variables present",
			vars: Variables{
				"COPILOT_API_URL":            {Value: "https://api.example.com", Required: true},
				"COPILOT_AGENT_ACTION":       {Value: "test-action", Required: true},
				"COPILOT_AGENT_BASE_COMMIT":  {Value: "abc123", Required: true},
				"COPILOT_AGENT_BRANCH_NAME":  {Value: "main", Required: true},
				"COPILOT_AGENT_CALLBACK_URL": {Value: "https://callback.example.com", Required: true},
				"COPILOT_AGENT_COMMIT_LOGIN": {Value: "testuser", Required: true},
				"COPILOT_AGENT_COMMIT_EMAIL": {Value: "test@example.com", Required: true},
				"COPILOT_AGENT_ISSUE_NUMBER": {Value: "123", Required: true},
				"COPILOT_AGENT_JOB_ID":       {Value: "job-456", Required: true},
				"COPILOT_AGENT_PROMPT":       {Value: "test prompt", Required: true},
				"COPILOT_JOB_NONCE":          {Value: "nonce-789", Required: true},
				"GITHUB_UPLOADS_URL":         {Value: "https://uploads.example.com", Required: true},
				"OPTIONAL_VAR":               {Value: "optional-value"},
			},
			wantError: false,
		},
		{
			name: "required variable with empty value",
			vars: Variables{
				"COPILOT_API_URL":            {Value: "https://api.example.com", Required: true},
				"COPILOT_AGENT_ACTION":       {Value: "test-action", Required: true},
				"COPILOT_AGENT_BASE_COMMIT":  {Value: "", Required: true}, // Empty required value
				"COPILOT_AGENT_BRANCH_NAME":  {Value: "main", Required: true},
				"COPILOT_AGENT_CALLBACK_URL": {Value: "https://callback.example.com", Required: true},
				"COPILOT_AGENT_COMMIT_LOGIN": {Value: "testuser", Required: true},
				"COPILOT_AGENT_COMMIT_EMAIL": {Value: "test@example.com", Required: true},
				"COPILOT_AGENT_ISSUE_NUMBER": {Value: "123", Required: true},
				"COPILOT_AGENT_JOB_ID":       {Value: "job-456", Required: true},
				"COPILOT_AGENT_PROMPT":       {Value: "test prompt", Required: true},
				"COPILOT_JOB_NONCE":          {Value: "nonce-789", Required: true},
				"GITHUB_UPLOADS_URL":         {Value: "https://uploads.example.com", Required: true},
			},
			wantError: true,
			errorMsg:  "missing required runtime variables: [COPILOT_AGENT_BASE_COMMIT]",
		},
		{
			name: "empty required variable",
			vars: Variables{
				"COPILOT_API_URL":            {Value: "https://api.example.com", Required: true},
				"COPILOT_AGENT_ACTION":       {Value: "test-action", Required: true},
				"COPILOT_AGENT_BASE_COMMIT":  {Value: "abc123", Required: true},
				"COPILOT_AGENT_BRANCH_NAME":  {Value: "", Required: true}, // Empty required value
				"COPILOT_AGENT_CALLBACK_URL": {Value: "https://callback.example.com", Required: true},
				"COPILOT_AGENT_COMMIT_LOGIN": {Value: "testuser", Required: true},
				"COPILOT_AGENT_COMMIT_EMAIL": {Value: "test@example.com", Required: true},
				"COPILOT_AGENT_ISSUE_NUMBER": {Value: "123", Required: true},
				"COPILOT_AGENT_JOB_ID":       {Value: "job-456", Required: true},
				"COPILOT_AGENT_PROMPT":       {Value: "test prompt", Required: true},
				"COPILOT_JOB_NONCE":          {Value: "nonce-789", Required: true},
				"GITHUB_UPLOADS_URL":         {Value: "https://uploads.example.com", Required: true},
			},
			wantError: true,
			errorMsg:  "missing required runtime variables: [COPILOT_AGENT_BRANCH_NAME]",
		},
		{
			name: "multiple empty required variables",
			vars: Variables{
				"COPILOT_API_URL":            {Value: "https://api.example.com", Required: true},
				"COPILOT_AGENT_ACTION":       {Value: "test-action", Required: true},
				"COPILOT_AGENT_BASE_COMMIT":  {Value: "", Required: true}, // Empty required value
				"COPILOT_AGENT_BRANCH_NAME":  {Value: "", Required: true}, // Empty required value
				"COPILOT_AGENT_CALLBACK_URL": {Value: "https://callback.example.com", Required: true},
				"COPILOT_AGENT_COMMIT_LOGIN": {Value: "testuser", Required: true},
				"COPILOT_AGENT_COMMIT_EMAIL": {Value: "test@example.com", Required: true},
				"COPILOT_AGENT_ISSUE_NUMBER": {Value: "", Required: true}, // Empty required value
				"COPILOT_AGENT_JOB_ID":       {Value: "job-456", Required: true},
				"COPILOT_AGENT_PROMPT":       {Value: "test prompt", Required: true},
				"COPILOT_JOB_NONCE":          {Value: "nonce-789", Required: true},
				"GITHUB_UPLOADS_URL":         {Value: "https://uploads.example.com", Required: true},
			},
			wantError: true,
			errorMsg:  "", // Will be checked manually for content
		},
		{
			name: "no required variables",
			vars: Variables{
				"OPTIONAL_VAR1": {Value: "value1"},
				"OPTIONAL_VAR2": {Value: "value2"},
				"EMPTY_VAR":     {Value: ""}, // Empty but not required
			},
			wantError: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateRequiredVariables(tt.vars)
			if tt.wantError {
				require.Error(t, err)
				if tt.errorMsg != "" {
					assert.Equal(t, tt.errorMsg, err.Error())
				} else if tt.name == "multiple empty required variables" {
					// For multiple missing variables, check that all expected variables are mentioned
					// since the order is non-deterministic due to Go map iteration
					errStr := err.Error()
					assert.Contains(t, errStr, "missing required runtime variables:")
					assert.Contains(t, errStr, "COPILOT_AGENT_BASE_COMMIT")
					assert.Contains(t, errStr, "COPILOT_AGENT_BRANCH_NAME")
					assert.Contains(t, errStr, "COPILOT_AGENT_ISSUE_NUMBER")
				}
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestPointerParametersDoNotMutate(t *testing.T) {
	ctx := context.Background()
	ffClient := featureflags.NewNoopClient(nil)

	t.Run("isFirewallEnabledByDefault does not mutate opts", func(t *testing.T) {
		opts := &AgentLauncherOpts{
			AgentFirewallEnabledDefault: false,
			CopilotAPIURL:               "https://api.example.com",
			RuntimeSHA:                  "abc123",
		}

		// Store a copy to compare
		originalFirewallDefault := opts.AgentFirewallEnabledDefault
		originalAPIURL := opts.CopilotAPIURL
		originalRuntimeSHA := opts.RuntimeSHA

		// Call the function
		_ = isFirewallEnabledByDefault(ctx, ffClient, opts)

		// Verify none of the fields were mutated
		assert.Equal(t, originalFirewallDefault, opts.AgentFirewallEnabledDefault, "AgentFirewallEnabledDefault should not be mutated")
		assert.Equal(t, originalAPIURL, opts.CopilotAPIURL, "CopilotAPIURL should not be mutated")
		assert.Equal(t, originalRuntimeSHA, opts.RuntimeSHA, "RuntimeSHA should not be mutated")
	})

	t.Run("isOnlineEvaluationDisabled does not mutate opts", func(t *testing.T) {
		opts := &AgentLauncherOpts{
			OnlineEvaluationDisabled: false,
			CopilotAPIURL:            "https://api.example.com",
			RuntimeSHA:               "abc123",
		}
		actors := &LaunchAgentOpts{
			ActorID:           123,
			GitHubRepoID:      456,
			GitHubRepoOwnerID: 789,
		}

		// Store a copy to compare
		originalOnlineEvalDisabled := opts.OnlineEvaluationDisabled
		originalAPIURL := opts.CopilotAPIURL

		// Call the function
		_ = isOnlineEvaluationDisabled(ctx, ffClient, opts, actors)

		// Verify none of the fields were mutated
		assert.Equal(t, originalOnlineEvalDisabled, opts.OnlineEvaluationDisabled, "OnlineEvaluationDisabled should not be mutated")
		assert.Equal(t, originalAPIURL, opts.CopilotAPIURL, "CopilotAPIURL should not be mutated")
	})

	t.Run("addAgentVariables does not mutate launcher opts", func(t *testing.T) {
		launcherOpts := &AgentLauncherOpts{
			CopilotAPIURL:     "https://api.example.com",
			RuntimeSHA:        "abc123",
			AgentCallbackURL:  "https://callback.example.com",
			UploadsURL:        "https://uploads.example.com",
			DownloadsURL:      "https://downloads.example.com",
			SecretScanningURL: "https://secrets.example.com",
			ModelOverride:     "test-model",
		}
		agentOpts := &LaunchAgentOpts{
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

		// Store copies to compare
		originalAPIURL := launcherOpts.CopilotAPIURL
		originalRuntimeSHA := launcherOpts.RuntimeSHA
		originalModelOverride := launcherOpts.ModelOverride

		vars := &Variables{}
		addAgentVariables(context.Background(), nil, vars, launcherOpts, agentOpts, false)

		// Verify launcher opts were not mutated
		assert.Equal(t, originalAPIURL, launcherOpts.CopilotAPIURL, "CopilotAPIURL should not be mutated")
		assert.Equal(t, originalRuntimeSHA, launcherOpts.RuntimeSHA, "RuntimeSHA should not be mutated")
		assert.Equal(t, originalModelOverride, launcherOpts.ModelOverride, "ModelOverride should not be mutated")
	})

	t.Run("addGitHubVariables does not mutate external opts", func(t *testing.T) {
		extOpts := &ExternalLauncherOpts{
			AgentLauncherOpts: AgentLauncherOpts{
				CopilotAPIURL: "https://api.example.com",
				RuntimeSHA:    "abc123",
			},
			GitHubServerURL:      "https://github.example.com",
			CAPIHMACKey:          "secret-key",
			CopilotIntegrationID: "integration-id",
		}
		agentOpts := &LaunchAgentOpts{
			GitHubRepo:        "owner/repo",
			GitHubRepoID:      456,
			GitHubRepoOwner:   "owner",
			GitHubRepoOwnerID: 789,
			GitHubToken:       "token-123",
		}

		// Store copies to compare
		originalServerURL := extOpts.GitHubServerURL
		originalHMACKey := extOpts.CAPIHMACKey
		originalIntegrationID := extOpts.CopilotIntegrationID

		vars := &Variables{}
		addGitHubVariables(context.Background(), nil, vars, extOpts, agentOpts, false)

		// Verify external opts were not mutated
		assert.Equal(t, originalServerURL, extOpts.GitHubServerURL, "GitHubServerURL should not be mutated")
		assert.Equal(t, originalHMACKey, extOpts.CAPIHMACKey, "CAPIHMACKey should not be mutated")
		assert.Equal(t, originalIntegrationID, extOpts.CopilotIntegrationID, "CopilotIntegrationID should not be mutated")
	})

	t.Run("addAnthropicKeyVariables does not mutate anthropic opts", func(t *testing.T) {
		anthropicOpts := &AnthropicKeyOpts{
			AnthropicAPIKey: "anthropic-api-key-123",
		}

		// Store copy to compare
		originalAPIKey := anthropicOpts.AnthropicAPIKey

		vars := &Variables{}
		addAnthropicKeyVariables(context.Background(), nil, vars, anthropicOpts, nil, false)

		// Verify anthropic opts were not mutated
		assert.Equal(t, originalAPIKey, anthropicOpts.AnthropicAPIKey, "AnthropicAPIKey should not be mutated")
	})
}

func TestGetVariablesProducesExpectedOutput(t *testing.T) {
	// This test verifies that GetVariables produces the expected output
	// after the pointer refactoring, confirming no behavior changes.
	t.Run("GetVariables with DockerLauncherOpts produces correct variables", func(t *testing.T) {
		launcherOpts := DockerLauncherOpts{
			ExternalLauncherOpts: ExternalLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL:     "https://api.example.com",
					RuntimeSHA:        "abc123sha",
					AgentCallbackURL:  "https://callback.example.com",
					UploadsURL:        "https://uploads.example.com",
					DownloadsURL:      "https://downloads.example.com",
					SecretScanningURL: "https://secrets.example.com",
					ModelOverride:     "override-model",
					MCPEnabled:        true,
				},
				GitHubServerURL:      "https://github.example.com",
				CAPIHMACKey:          "hmac-key",
				CopilotIntegrationID: "integration-123",
			},
			AnthropicKeyOpts: AnthropicKeyOpts{
				AnthropicAPIKey: "anthropic-key",
			},
		}
		agentOpts := &LaunchAgentOpts{
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
			GitHubRepoOwnerID: 789,
			GitHubRepoID:      456,
			GitHubToken:       "github-token",
			Agent:             agenticapptest.NewTestCopilot(t),
		}

		vars := GetVariables(context.Background(), nil, launcherOpts, agentOpts, nil, false)

		// Verify key variables are present and have correct values
		assert.Equal(t, "https://api.example.com", vars["COPILOT_API_URL"].Value)
		assert.Equal(t, "runtime-abc123sha", vars["COPILOT_AGENT_RUNTIME_VERSION"].Value)
		assert.Equal(t, "https://callback.example.com", vars["COPILOT_AGENT_CALLBACK_URL"].Value)
		assert.Equal(t, "override-model", vars["COPILOT_AGENT_MODEL"].Value, "ModelOverride should be used")
		assert.Equal(t, "fix", vars["COPILOT_AGENT_ACTION"].Value)
		assert.Equal(t, "job-123", vars["COPILOT_AGENT_JOB_ID"].Value)
		assert.Equal(t, "main", vars["COPILOT_AGENT_BRANCH_NAME"].Value)
		assert.Equal(t, "abc123", vars["COPILOT_AGENT_BASE_COMMIT"].Value)
		assert.Equal(t, "42", vars["COPILOT_AGENT_ISSUE_NUMBER"].Value)
		assert.Equal(t, "true", vars["COPILOT_MCP_ENABLED"].Value)

		// Verify GitHub variables from ExternalLauncherOpts
		assert.Equal(t, "https://github.example.com", vars["GITHUB_SERVER_URL"].Value)
		assert.Equal(t, "owner/repo", vars["GITHUB_REPOSITORY"].Value)
		assert.Equal(t, "owner", vars["GITHUB_REPOSITORY_OWNER"].Value)
		assert.Equal(t, "456", vars["GITHUB_REPOSITORY_ID"].Value)
		assert.Equal(t, "789", vars["GITHUB_REPOSITORY_OWNER_ID"].Value)
		assert.Equal(t, "hmac-key", vars["CAPI_HMAC_KEY"].Value)
		assert.Equal(t, "integration-123", vars["GITHUB_COPILOT_INTEGRATION_ID"].Value)

		// Verify Anthropic variables
		assert.Equal(t, "anthropic-key", vars["ANTHROPIC_API_KEY"].Value)
	})

	t.Run("GetVariablesStrings returns expected format", func(t *testing.T) {
		launcherOpts := ExternalLauncherOpts{
			AgentLauncherOpts: AgentLauncherOpts{
				CopilotAPIURL:     "https://api.example.com",
				RuntimeSHA:        "abc123sha",
				AgentCallbackURL:  "https://callback.example.com",
				UploadsURL:        "https://uploads.example.com",
				DownloadsURL:      "https://downloads.example.com",
				SecretScanningURL: "https://secrets.example.com",
			},
			GitHubServerURL:      "https://github.example.com",
			CAPIHMACKey:          "hmac-key",
			CopilotIntegrationID: "integration-123",
		}
		agentOpts := &LaunchAgentOpts{
			Model:             "test-model",
			ProblemStatement:  "test problem",
			Action:            "fix",
			JobID:             "job-123",
			BranchName:        "main",
			GitHubBaseCommit:  "abc123",
			IssueNumber:       42,
			Nonce:             "test-nonce",
			GitHubRepo:        "owner/repo",
			GitHubRepoOwner:   "owner",
			GitHubRepoOwnerID: 789,
			GitHubRepoID:      456,
			GitHubToken:       "github-token",
			Agent:             agenticapptest.NewTestCopilot(t),
		}

		kvs := GetVariablesStrings(context.Background(), nil, launcherOpts, agentOpts, nil, false)

		// Convert to map for easier testing
		kvsMap := make(map[string]string)
		for _, kv := range kvs {
			parts := splitFirstEquals(kv)
			if len(parts) == 2 {
				kvsMap[parts[0]] = parts[1]
			}
		}

		// Verify key variables are present in the correct format
		assert.Equal(t, "https://api.example.com", kvsMap["COPILOT_API_URL"])
		assert.Equal(t, "runtime-abc123sha", kvsMap["COPILOT_AGENT_RUNTIME_VERSION"])
		assert.Equal(t, "https://github.example.com", kvsMap["GITHUB_SERVER_URL"])
	})

	t.Run("GetVariables with feature flag enabled produces app-specific runtime version", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseReleaseAssets: true,
		})
		launcherOpts := DockerLauncherOpts{
			ExternalLauncherOpts: ExternalLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL:     "https://api.example.com",
					RuntimeSHA:        "abc123sha",
					AgentCallbackURL:  "https://callback.example.com",
					UploadsURL:        "https://uploads.example.com",
					DownloadsURL:      "https://downloads.example.com",
					SecretScanningURL: "https://secrets.example.com",
				},
				GitHubServerURL:      "https://github.example.com",
				CAPIHMACKey:          "hmac-key",
				CopilotIntegrationID: "integration-123",
			},
		}
		agentOpts := &LaunchAgentOpts{
			Model:             "test-model",
			ProblemStatement:  "test problem",
			Action:            "fix",
			JobID:             "job-123",
			BranchName:        "main",
			GitHubBaseCommit:  "abc123",
			IssueNumber:       42,
			Nonce:             "test-nonce",
			GitHubRepo:        "owner/repo",
			GitHubRepoOwner:   "owner",
			GitHubRepoOwnerID: 789,
			GitHubRepoID:      456,
			GitHubToken:       "github-token",
			Agent:             agenticapptest.NewTestCopilot(t),
		}

		vars := GetVariables(context.Background(), ffClient, launcherOpts, agentOpts, nil, false)

		// With feature flag enabled, runtime version should include app slug
		assert.Equal(t, "runtime-copilot-abc123sha", vars["COPILOT_AGENT_RUNTIME_VERSION"].Value)
	})
}

// splitFirstEquals splits a string on the first "=" only
func splitFirstEquals(s string) []string {
	idx := -1
	for i, c := range s {
		if c == '=' {
			idx = i
			break
		}
	}
	if idx == -1 {
		return []string{s}
	}
	return []string{s[:idx], s[idx+1:]}
}
