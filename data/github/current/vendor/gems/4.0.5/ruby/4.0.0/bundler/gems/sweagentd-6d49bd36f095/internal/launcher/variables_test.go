package launcher

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
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

func TestDisableAgentFirewall(t *testing.T) {
	data := workflowData{
		UseMaterializedFirewall:             true,
		MaterializedFirewallEnabled:         true,
		MaterializedFirewallUseDefaultRules: true,
		MaterializedFirewallAllowedRules:    "example.test,api.example.test",
		AgentFirewallEnabledDefault:         true,
	}

	disableAgentFirewall(&data)

	assert.True(t, data.UseMaterializedFirewall, "UseMaterializedFirewall must stay true so the rendered workflow takes the materialized branch with the forced-off values")
	assert.False(t, data.MaterializedFirewallEnabled)
	assert.False(t, data.MaterializedFirewallUseDefaultRules)
	assert.Empty(t, string(data.MaterializedFirewallAllowedRules))
	assert.False(t, data.AgentFirewallEnabledDefault)
}

func TestIsFirewallDisabled(t *testing.T) {
	ctx := context.Background()

	const ccrAppID = int64(100)
	const csAppID = int64(200)
	const otherAppID = int64(300)

	ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 101, "copilot-code-review[bot]", "commit-login", "commit@email.com")
	csApp := agenticapp.NewCodeScanning(csAppID, "code-scanning", 201, "code-scanning[bot]", "commit-login", "commit@email.com")
	copilotApp := agenticapptest.NewTestCopilotWithID(t, otherAppID)
	provider := agenticapp.NewProvider(copilotApp, ccrApp, csApp)

	actors := &LaunchAgentOpts{}

	t.Run("CCR agent with CCR flag enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentCCRDisableFirewall): true,
		})
		assert.True(t, isFirewallDisabled(ctx, ffClient, ccrApp, actors, provider))
	})

	t.Run("CCR enable firewall flag takes precedence over CCR disable flag", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentCCRDisableFirewall): true,
			string(featureflags.CopilotSWEAgentCCREnableFirewall):  true,
		})
		assert.False(t, isFirewallDisabled(ctx, ffClient, ccrApp, actors, provider))
	})

	t.Run("CCR enable firewall flag alone does not disable firewall", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentCCREnableFirewall): true,
		})
		assert.False(t, isFirewallDisabled(ctx, ffClient, ccrApp, actors, provider))
	})

	t.Run("CCR agent with only CS flag enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentCodeScanningDisableFirewall): true,
		})
		assert.False(t, isFirewallDisabled(ctx, ffClient, ccrApp, actors, provider))
	})

	t.Run("Code Scanning agent with CS flag enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentCodeScanningDisableFirewall): true,
		})
		assert.True(t, isFirewallDisabled(ctx, ffClient, csApp, actors, provider))
	})

	t.Run("Code Scanning agent with only CCR flag enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentCCRDisableFirewall): true,
		})
		assert.False(t, isFirewallDisabled(ctx, ffClient, csApp, actors, provider))
	})

	t.Run("agent not implementing FirewallExempt", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentCCRDisableFirewall):          true,
			string(featureflags.CopilotSWEAgentCodeScanningDisableFirewall): true,
		})
		regularApp := agenticapptest.NewTestApp(otherAppID)
		assert.False(t, isFirewallDisabled(ctx, ffClient, regularApp, actors, provider))
	})

	t.Run("no flags enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		assert.False(t, isFirewallDisabled(ctx, ffClient, ccrApp, actors, provider))
		assert.False(t, isFirewallDisabled(ctx, ffClient, csApp, actors, provider))
	})
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
		addAgentVariables(context.Background(), nil, vars, launcherOpts, agentOpts)

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
		addGitHubVariables(context.Background(), nil, vars, extOpts, agentOpts)

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
		addAnthropicKeyVariables(context.Background(), nil, vars, anthropicOpts, nil)

		// Verify anthropic opts were not mutated
		assert.Equal(t, originalAPIKey, anthropicOpts.AnthropicAPIKey, "AnthropicAPIKey should not be mutated")
	})
}

func TestAddAdditionalRepositoryVariables(t *testing.T) {
	tests := []struct {
		name     string
		opts     *LaunchAgentOpts
		wantJSON string // empty string means expect "" exactly; otherwise compared with JSONEq
	}{
		{
			name:     "returns empty string when opts is nil",
			opts:     nil,
			wantJSON: "",
		},
		{
			name:     "returns empty string when no additional repos",
			opts:     &LaunchAgentOpts{},
			wantJSON: "",
		},
		{
			name: "serializes single repo as JSON with expected fields",
			opts: &LaunchAgentOpts{
				AdditionalRepositories: []AdditionalRepository{
					{GitHubRepo: "owner/repo", GitHubRepoID: 123, GitHubRepoOwner: "owner", GitHubRepoOwnerID: 456},
				},
			},
			wantJSON: `[{"github_repo":"owner/repo","github_repo_id":123,"github_owner":"owner","github_owner_id":456}]`,
		},
		{
			name: "serializes multiple repos as JSON with expected fields",
			opts: &LaunchAgentOpts{
				AdditionalRepositories: []AdditionalRepository{
					{GitHubRepo: "owner/repo", GitHubRepoID: 123, GitHubRepoOwner: "owner", GitHubRepoOwnerID: 456},
					{GitHubRepo: "other/repo2", GitHubRepoID: 789, GitHubRepoOwner: "other", GitHubRepoOwnerID: 101},
				},
			},
			wantJSON: `[
				{"github_repo":"owner/repo","github_repo_id":123,"github_owner":"owner","github_owner_id":456},
				{"github_repo":"other/repo2","github_repo_id":789,"github_owner":"other","github_owner_id":101}
			]`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := addAdditionalRepositoryVariables(tt.opts)
			if tt.wantJSON == "" {
				assert.Equal(t, "", got)
				return
			}
			assert.JSONEq(t, tt.wantJSON, got)
		})
	}
}

func TestAddGitHubVariablesAdditionalRepositories(t *testing.T) {
	primaryOpts := func(extra ...AdditionalRepository) *LaunchAgentOpts {
		return &LaunchAgentOpts{
			GitHubRepo:             "owner/repo",
			GitHubRepoOwner:        "owner",
			GitHubRepoID:           1,
			GitHubRepoOwnerID:      2,
			AdditionalRepositories: extra,
		}
	}

	tests := []struct {
		name             string
		opts             *LaunchAgentOpts
		wantAdditional   string // expected ADDITIONAL_GITHUB_REPOSITORIES value; "" means must be present and empty
		wantAdditionalEq bool   // when true, compare with JSONEq
	}{
		{
			name:           "ADDITIONAL_GITHUB_REPOSITORIES empty when no additional repos",
			opts:           primaryOpts(),
			wantAdditional: "",
		},
		{
			name: "ADDITIONAL_GITHUB_REPOSITORIES contains JSON when set",
			opts: primaryOpts(AdditionalRepository{
				GitHubRepo: "extra/repo", GitHubRepoID: 9, GitHubRepoOwner: "extra", GitHubRepoOwnerID: 10,
			}),
			wantAdditional:   `[{"github_repo":"extra/repo","github_repo_id":9,"github_owner":"extra","github_owner_id":10}]`,
			wantAdditionalEq: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			vars := &Variables{}
			addGitHubVariables(context.Background(), nil, vars, &ExternalLauncherOpts{}, tt.opts)

			// Primary repo vars must always be present and unchanged regardless of additional repos.
			assert.Equal(t, "owner/repo", (*vars)["GITHUB_REPOSITORY"].Value)
			assert.Equal(t, "1", (*vars)["GITHUB_REPOSITORY_ID"].Value)
			assert.Equal(t, "owner", (*vars)["GITHUB_REPOSITORY_OWNER"].Value)
			assert.Equal(t, "2", (*vars)["GITHUB_REPOSITORY_OWNER_ID"].Value)

			v, ok := (*vars)["ADDITIONAL_GITHUB_REPOSITORIES"]
			require.True(t, ok, "ADDITIONAL_GITHUB_REPOSITORIES should always be present")
			if tt.wantAdditionalEq {
				assert.JSONEq(t, tt.wantAdditional, v.Value)
			} else {
				assert.Equal(t, tt.wantAdditional, v.Value)
			}
		})
	}
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

		vars := GetVariables(context.Background(), nil, launcherOpts, agentOpts, nil)

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

		kvs := GetVariablesStrings(context.Background(), nil, launcherOpts, agentOpts, nil)

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

		vars := GetVariables(context.Background(), ffClient, launcherOpts, agentOpts, nil)

		// With feature flag enabled, runtime version should include app slug
		assert.Equal(t, "runtime-copilot-abc123sha", vars["COPILOT_AGENT_RUNTIME_VERSION"].Value)
	})

	t.Run("GetVariables with runtime entry point uses matching release asset", func(t *testing.T) {
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
			ActorID:           123,
			Agent:             agenticapptest.NewTestCopilot(t),
		}
		tests := []struct {
			name                   string
			runtimeFeatureFlag     string
			expectedRuntimeVersion string
		}{
			{
				name:                   "CCA v3",
				runtimeFeatureFlag:     featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App,
				expectedRuntimeVersion: "runtime-cca-v3-abc123sha",
			},
			{
				name:                   "CCA v2",
				runtimeFeatureFlag:     featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2,
				expectedRuntimeVersion: "runtime-cca-abc123sha",
			},
			{
				name:                   "Claude",
				runtimeFeatureFlag:     featureflags.CopilotSWEAgentRuntimeEntryPointClaude,
				expectedRuntimeVersion: "runtime-claude-abc123sha",
			},
			{
				name:                   "Codex",
				runtimeFeatureFlag:     featureflags.CopilotSWEAgentRuntimeEntryPointCodex,
				expectedRuntimeVersion: "runtime-codex-abc123sha",
			},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				ffClient := featureflags.NewNoopClient(map[string]bool{
					featureflags.CopilotSWEAgentUseReleaseAssets: true,
					tt.runtimeFeatureFlag:                        true,
				})

				vars := GetVariables(context.Background(), ffClient, launcherOpts, agentOpts, nil)

				assert.Equal(t, tt.expectedRuntimeVersion, vars["COPILOT_AGENT_RUNTIME_VERSION"].Value)
			})
		}
	})

	t.Run("GetVariables with feature flag enabled uses EngineSlug for runtime version", func(t *testing.T) {
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
		cs := agenticapp.NewCodeScanning(123, agenticapp.CodeScanningComputeSlug, 456, agenticapp.CodeScanningComputeSlug+"[bot]", "commit-login", "commit@email.com")
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
			Agent:             cs,
		}

		vars := GetVariables(context.Background(), ffClient, launcherOpts, agentOpts, nil)

		// CodeScanning's EngineSlug returns CopilotCodeReview slug, not its own ComputeSlug
		assert.Equal(t, "runtime-copilot-pull-request-reviewer-abc123sha", vars["COPILOT_AGENT_RUNTIME_VERSION"].Value)
	})

	t.Run("GetVariables with third-party agent uses selected Copilot runtime version", func(t *testing.T) {
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
		thirdParty := agenticapp.NewThirdParty(456, "third-party-agent", "", 789, "third-party-agent[bot]", "commit-login", "commit@email.com", nil, nil)
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
			ActorID:           123,
			Agent:             thirdParty,
		}
		tests := []struct {
			name                   string
			featureFlags           map[string]bool
			expectedRuntimeVersion string
		}{
			{
				name: "default Copilot runtime",
				featureFlags: map[string]bool{
					featureflags.CopilotSWEAgentUseReleaseAssets: true,
				},
				expectedRuntimeVersion: "runtime-copilot-abc123sha",
			},
			{
				name: "CCA v3 runtime",
				featureFlags: map[string]bool{
					featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
					featureflags.CopilotSWEAgentUseReleaseAssets:          true,
				},
				expectedRuntimeVersion: "runtime-cca-v3-abc123sha",
			},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				ffClient := featureflags.NewNoopClient(tt.featureFlags)
				vars := GetVariables(context.Background(), ffClient, launcherOpts, agentOpts, nil)

				assert.Equal(t, tt.expectedRuntimeVersion, vars["COPILOT_AGENT_RUNTIME_VERSION"].Value)
			})
		}
	})
}

func TestValidationToolSettingsVariables(t *testing.T) {
	t.Run("validation tool settings are passed through as env vars when flag is enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentValidationToolSettings: true,
		})
		agentOpts := &LaunchAgentOpts{
			Model:                  "test-model",
			ProblemStatement:       "test problem",
			Action:                 "fix",
			JobID:                  "job-123",
			BranchName:             "main",
			GitHubBaseCommit:       "abc123",
			IssueNumber:            42,
			Nonce:                  "test-nonce",
			UseCodeQL:              true,
			UseCCR:                 false,
			UseSecretScanning:      true,
			UseDependencyVulnCheck: false,
			Agent:                  agenticapptest.NewTestCopilot(t),
		}
		launcherOpts := &AgentLauncherOpts{
			CopilotAPIURL:     "https://api.example.com",
			RuntimeSHA:        "abc123sha",
			AgentCallbackURL:  "https://callback.example.com",
			UploadsURL:        "https://uploads.example.com",
			DownloadsURL:      "https://downloads.example.com",
			SecretScanningURL: "https://secrets.example.com",
		}

		vars := &Variables{}
		addAgentVariables(context.Background(), ffClient, vars, launcherOpts, agentOpts)

		assert.Equal(t, "true", (*vars)["COPILOT_AGENT_USE_CODEQL"].Value)
		assert.Equal(t, "false", (*vars)["COPILOT_AGENT_USE_CCR"].Value)
		assert.Equal(t, "true", (*vars)["COPILOT_AGENT_USE_SECRET_SCANNING"].Value)
		assert.Equal(t, "false", (*vars)["COPILOT_AGENT_USE_DEPENDENCY_VULN"].Value)
	})

	t.Run("validation tool settings default to false when not set and flag is enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentValidationToolSettings: true,
		})
		agentOpts := &LaunchAgentOpts{
			Model:            "test-model",
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
			CopilotAPIURL:     "https://api.example.com",
			RuntimeSHA:        "abc123sha",
			AgentCallbackURL:  "https://callback.example.com",
			UploadsURL:        "https://uploads.example.com",
			DownloadsURL:      "https://downloads.example.com",
			SecretScanningURL: "https://secrets.example.com",
		}

		vars := &Variables{}
		addAgentVariables(context.Background(), ffClient, vars, launcherOpts, agentOpts)

		assert.Equal(t, "false", (*vars)["COPILOT_AGENT_USE_CODEQL"].Value)
		assert.Equal(t, "false", (*vars)["COPILOT_AGENT_USE_CCR"].Value)
		assert.Equal(t, "false", (*vars)["COPILOT_AGENT_USE_SECRET_SCANNING"].Value)
		assert.Equal(t, "false", (*vars)["COPILOT_AGENT_USE_DEPENDENCY_VULN"].Value)
	})

	t.Run("validation tool settings are not set when flag is disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentValidationToolSettings: false,
		})
		agentOpts := &LaunchAgentOpts{
			Model:                  "test-model",
			ProblemStatement:       "test problem",
			Action:                 "fix",
			JobID:                  "job-123",
			BranchName:             "main",
			GitHubBaseCommit:       "abc123",
			IssueNumber:            42,
			Nonce:                  "test-nonce",
			UseCodeQL:              true,
			UseCCR:                 false,
			UseSecretScanning:      true,
			UseDependencyVulnCheck: false,
			Agent:                  agenticapptest.NewTestCopilot(t),
		}
		launcherOpts := &AgentLauncherOpts{
			CopilotAPIURL:     "https://api.example.com",
			RuntimeSHA:        "abc123sha",
			AgentCallbackURL:  "https://callback.example.com",
			UploadsURL:        "https://uploads.example.com",
			DownloadsURL:      "https://downloads.example.com",
			SecretScanningURL: "https://secrets.example.com",
		}

		vars := &Variables{}
		addAgentVariables(context.Background(), ffClient, vars, launcherOpts, agentOpts)

		_, codeqlExists := (*vars)["COPILOT_AGENT_USE_CODEQL"]
		_, ccrExists := (*vars)["COPILOT_AGENT_USE_CCR"]
		_, secretScanExists := (*vars)["COPILOT_AGENT_USE_SECRET_SCANNING"]
		_, depVulnExists := (*vars)["COPILOT_AGENT_USE_DEPENDENCY_VULN"]
		assert.False(t, codeqlExists, "COPILOT_AGENT_USE_CODEQL should not be set when flag is disabled")
		assert.False(t, ccrExists, "COPILOT_AGENT_USE_CCR should not be set when flag is disabled")
		assert.False(t, secretScanExists, "COPILOT_AGENT_USE_SECRET_SCANNING should not be set when flag is disabled")
		assert.False(t, depVulnExists, "COPILOT_AGENT_USE_DEPENDENCY_VULN should not be set when flag is disabled")
	})
}

func TestActorTypeVariable(t *testing.T) {
	tests := []struct {
		name          string
		actorType     string
		expectedValue string
	}{
		{
			name:          "org actor type is passed through",
			actorType:     "org",
			expectedValue: "org",
		},
		{
			name:          "user actor type is passed through",
			actorType:     "user",
			expectedValue: "user",
		},
		{
			name:          "empty actor type produces empty value",
			actorType:     "",
			expectedValue: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			agentOpts := &LaunchAgentOpts{
				Model:            "test-model",
				ProblemStatement: "test problem",
				Action:           "fix",
				JobID:            "job-123",
				BranchName:       "main",
				GitHubBaseCommit: "abc123",
				IssueNumber:      42,
				Nonce:            "test-nonce",
				ActorType:        tt.actorType,
				Agent:            agenticapptest.NewTestCopilot(t),
			}
			launcherOpts := &AgentLauncherOpts{
				CopilotAPIURL:     "https://api.example.com",
				RuntimeSHA:        "abc123sha",
				AgentCallbackURL:  "https://callback.example.com",
				UploadsURL:        "https://uploads.example.com",
				DownloadsURL:      "https://downloads.example.com",
				SecretScanningURL: "https://secrets.example.com",
			}

			vars := &Variables{}
			addAgentVariables(context.Background(), nil, vars, launcherOpts, agentOpts)

			assert.Equal(t, tt.expectedValue, (*vars)["COPILOT_AGENT_ACTOR_TYPE"].Value)
		})
	}
}

func TestSignCommitsVariable(t *testing.T) {
	t.Run("sign commits env var is true when enabled", func(t *testing.T) {
		agentOpts := &LaunchAgentOpts{
			Model:            "test-model",
			ProblemStatement: "test problem",
			Action:           "fix",
			JobID:            "job-123",
			BranchName:       "main",
			GitHubBaseCommit: "abc123",
			IssueNumber:      42,
			Nonce:            "test-nonce",
			SignCommits:      true,
			Agent:            agenticapptest.NewTestCopilot(t),
		}
		launcherOpts := &AgentLauncherOpts{
			CopilotAPIURL:     "https://api.example.com",
			RuntimeSHA:        "abc123sha",
			AgentCallbackURL:  "https://callback.example.com",
			UploadsURL:        "https://uploads.example.com",
			DownloadsURL:      "https://downloads.example.com",
			SecretScanningURL: "https://secrets.example.com",
		}

		vars := &Variables{}
		addAgentVariables(context.Background(), nil, vars, launcherOpts, agentOpts)

		assert.Equal(t, "true", (*vars)["COPILOT_AGENT_SIGN_COMMITS"].Value)
	})

	t.Run("sign commits env var defaults to false", func(t *testing.T) {
		agentOpts := &LaunchAgentOpts{
			Model:            "test-model",
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
			CopilotAPIURL:     "https://api.example.com",
			RuntimeSHA:        "abc123sha",
			AgentCallbackURL:  "https://callback.example.com",
			UploadsURL:        "https://uploads.example.com",
			DownloadsURL:      "https://downloads.example.com",
			SecretScanningURL: "https://secrets.example.com",
		}

		vars := &Variables{}
		addAgentVariables(context.Background(), nil, vars, launcherOpts, agentOpts)

		assert.Equal(t, "false", (*vars)["COPILOT_AGENT_SIGN_COMMITS"].Value)
	})
}

func TestVerificationTokenAndTokenVarName(t *testing.T) {
	t.Run("GITHUB_VERIFICATION_TOKEN and GITHUB_TOKEN_VARNAME are set correctly", func(t *testing.T) {
		agentOpts := &LaunchAgentOpts{
			Model:            "test-model",
			ProblemStatement: "test problem",
			Action:           "fix",
			JobID:            "job-456",
			BranchName:       "main",
			GitHubBaseCommit: "abc123",
			IssueNumber:      42,
			Nonce:            "my-unique-nonce",
			Agent:            agenticapptest.NewTestCopilot(t),
		}
		launcherOpts := &AgentLauncherOpts{
			CopilotAPIURL:     "https://api.example.com",
			RuntimeSHA:        "abc123sha",
			AgentCallbackURL:  "https://callback.example.com",
			UploadsURL:        "https://uploads.example.com",
			DownloadsURL:      "https://downloads.example.com",
			SecretScanningURL: "https://secrets.example.com",
		}

		vars := &Variables{}
		addAgentVariables(context.Background(), nil, vars, launcherOpts, agentOpts)

		assert.Equal(t, "my-unique-nonce", (*vars)["GITHUB_VERIFICATION_TOKEN"].Value)
		assert.Equal(t, "GITHUB_COPILOT_API_TOKEN", (*vars)["GITHUB_TOKEN_VARNAME"].Value)
	})
}

func TestCopilotAgentVariable(t *testing.T) {
	agentOpts := &LaunchAgentOpts{
		Model:            "test-model",
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
		CopilotAPIURL:     "https://api.example.com",
		RuntimeSHA:        "abc123sha",
		AgentCallbackURL:  "https://callback.example.com",
		UploadsURL:        "https://uploads.example.com",
		DownloadsURL:      "https://downloads.example.com",
		SecretScanningURL: "https://secrets.example.com",
	}

	vars := &Variables{}
	addAgentVariables(context.Background(), nil, vars, launcherOpts, agentOpts)

	assert.Equal(t, "true", (*vars)["COPILOT_AGENT"].Value,
		"COPILOT_AGENT must always be set to \"true\" in a CCA context")
}

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
