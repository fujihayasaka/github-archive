package launcher

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewDockerLauncher_OptsNotMutated(t *testing.T) {
	// This test verifies that NewDockerLauncher does not mutate the DockerLauncherOpts
	// when passed as a pointer, ensuring safe pointer passing for efficiency.
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	originalOpts := DockerLauncherOpts{
		ExternalLauncherOpts: ExternalLauncherOpts{
			AgentLauncherOpts: AgentLauncherOpts{
				CopilotAPIURL:         "https://api.github.com",
				AgentCallbackURL:      "https://callback.github.com",
				GitHubCopilotAPIToken: "test-token",
				UploadsURL:            "https://uploads.github.com",
				RuntimeSHA:            "deadbeef",
				DownloadsURL:          "https://downloads.github.com",
				SecretScanningURL:     "https://secrets.github.com",
				ModelOverride:         "test-model",
				AgentDebug:            true,
				MCPEnabled:            true,
			},
			GitHubServerURL:      "https://github.com",
			CAPIHMACKey:          "test-hmac-key",
			CopilotIntegrationID: "test-integration-id",
		},
		AnthropicKeyOpts: AnthropicKeyOpts{
			AnthropicAPIKey: "test-anthropic-key",
		},
		ContainerImage:          "test-image:latest",
		DockerAIPProxy:          true,
		DockerUseHostNetworking: true,
		DockerMapPort:           8080,
	}

	// Make a copy to compare after the function call
	expectedOpts := originalOpts

	// Pass a pointer to NewDockerLauncher
	launcher, err := NewDockerLauncher(obsv, ffClient, nil, nil, &originalOpts)

	// The function should succeed (may fail due to Docker not being available,
	// but that's okay - we want to verify opts aren't mutated before any failure)
	// For this test, we just need to verify opts weren't mutated
	_ = launcher
	_ = err

	// Verify that the original opts were not mutated
	assert.Equal(t, expectedOpts.CopilotAPIURL, originalOpts.CopilotAPIURL, "CopilotAPIURL should not be mutated")
	assert.Equal(t, expectedOpts.AgentCallbackURL, originalOpts.AgentCallbackURL, "AgentCallbackURL should not be mutated")
	assert.Equal(t, expectedOpts.GitHubCopilotAPIToken, originalOpts.GitHubCopilotAPIToken, "GitHubCopilotAPIToken should not be mutated")
	assert.Equal(t, expectedOpts.ContainerImage, originalOpts.ContainerImage, "ContainerImage should not be mutated")
	assert.Equal(t, expectedOpts.DockerAIPProxy, originalOpts.DockerAIPProxy, "DockerAIPProxy should not be mutated")
	assert.Equal(t, expectedOpts.DockerUseHostNetworking, originalOpts.DockerUseHostNetworking, "DockerUseHostNetworking should not be mutated")
	assert.Equal(t, expectedOpts.DockerMapPort, originalOpts.DockerMapPort, "DockerMapPort should not be mutated")
	assert.Equal(t, expectedOpts.MCPEnabled, originalOpts.MCPEnabled, "MCPEnabled should not be mutated")
	assert.Equal(t, expectedOpts.AgentDebug, originalOpts.AgentDebug, "AgentDebug should not be mutated")
	assert.Equal(t, expectedOpts.AnthropicAPIKey, originalOpts.AnthropicAPIKey, "AnthropicAPIKey should not be mutated")
	assert.Equal(t, expectedOpts.GitHubServerURL, originalOpts.GitHubServerURL, "GitHubServerURL should not be mutated")
	assert.Equal(t, expectedOpts.CAPIHMACKey, originalOpts.CAPIHMACKey, "CAPIHMACKey should not be mutated")
	assert.Equal(t, expectedOpts.CopilotIntegrationID, originalOpts.CopilotIntegrationID, "CopilotIntegrationID should not be mutated")
}

func TestNewDockerLauncher_OptsCopiedIntoLauncher(t *testing.T) {
	// This test verifies that the launcher stores a copy of opts, not a reference.
	// Modifying the original opts after creation should not affect the launcher.
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	opts := &DockerLauncherOpts{
		ExternalLauncherOpts: ExternalLauncherOpts{
			AgentLauncherOpts: AgentLauncherOpts{
				CopilotAPIURL: "https://original-api.github.com",
				AgentDebug:    false,
			},
		},
		ContainerImage: "original-image:latest",
		DockerMapPort:  8080,
	}

	launcher, err := NewDockerLauncher(obsv, ffClient, nil, nil, opts)
	require.NoError(t, err, "NewDockerLauncher should succeed")
	require.NotNil(t, launcher, "launcher should not be nil")

	// Store the original values from the launcher
	originalAPIURL := launcher.opts.CopilotAPIURL
	originalImage := launcher.opts.ContainerImage
	originalPort := launcher.opts.DockerMapPort
	originalDebug := launcher.opts.AgentDebug

	// Mutate the original opts after launcher creation
	opts.CopilotAPIURL = "https://mutated-api.github.com"
	opts.ContainerImage = "mutated-image:latest"
	opts.DockerMapPort = 9999
	opts.AgentDebug = true

	// Verify the launcher's opts were not affected by the mutation
	assert.Equal(t, originalAPIURL, launcher.opts.CopilotAPIURL, "launcher.opts.CopilotAPIURL should not change after opts mutation")
	assert.Equal(t, originalImage, launcher.opts.ContainerImage, "launcher.opts.ContainerImage should not change after opts mutation")
	assert.Equal(t, originalPort, launcher.opts.DockerMapPort, "launcher.opts.DockerMapPort should not change after opts mutation")
	assert.Equal(t, originalDebug, launcher.opts.AgentDebug, "launcher.opts.AgentDebug should not change after opts mutation")

	// Also verify the launcher values are the original values
	assert.Equal(t, "https://original-api.github.com", launcher.opts.CopilotAPIURL)
	assert.Equal(t, "original-image:latest", launcher.opts.ContainerImage)
	assert.Equal(t, 8080, launcher.opts.DockerMapPort)
	assert.Equal(t, false, launcher.opts.AgentDebug)
}

func TestDockerLauncher_SetWorkflowCompletedHandler_DoesNotAffectOriginalOpts(t *testing.T) {
	// This test verifies that SetWorkflowCompletedHandler modifies the launcher's
	// internal copy of opts, not any external reference.
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	opts := &DockerLauncherOpts{
		ContainerImage: "test-image:latest",
	}

	launcher, err := NewDockerLauncher(obsv, ffClient, nil, nil, opts)
	require.NoError(t, err, "NewDockerLauncher should succeed")
	require.NotNil(t, launcher, "launcher should not be nil")

	// Verify the original opts handler is nil
	assert.Nil(t, opts.WorkflowCompletedHandler, "original opts handler should be nil")

	// Create a mock handler
	mockHandler := &mockWorkflowRunCompletedHandler{}

	// Set the handler on the launcher
	launcher.SetWorkflowCompletedHandler(mockHandler)

	// Verify the launcher's handler was set
	assert.NotNil(t, launcher.opts.WorkflowCompletedHandler, "launcher handler should be set")
	assert.Equal(t, mockHandler, launcher.opts.WorkflowCompletedHandler, "launcher handler should be the mock")

	// Verify the original opts handler is still nil (opts was copied, not referenced)
	assert.Nil(t, opts.WorkflowCompletedHandler, "original opts handler should still be nil after SetWorkflowCompletedHandler")
}

func TestDockerLauncher_LauncherType(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)

	opts := &DockerLauncherOpts{
		ContainerImage: "test-image:latest",
	}

	launcher, err := NewDockerLauncher(obsv, ffClient, nil, nil, opts)
	require.NoError(t, err)

	assert.Equal(t, TypeDocker, launcher.LauncherType())
}

type recordingSweagentdAPI struct {
	*githubtwirp.NoopSweagentdAPI

	lastMintUserToServerTokenForRepoRequest *sweagentdTwirp.MintUserToServerTokenForRepoRequest
}

func (r *recordingSweagentdAPI) MintUserToServerTokenForRepo(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error) {
	r.lastMintUserToServerTokenForRepoRequest = req
	return &sweagentdTwirp.MintUserToServerTokenForRepoResponse{Token: "mock-token"}, nil
}

type recordingTwirpClient struct {
	*githubtwirp.NoopClient

	sweagentdAPI sweagentdTwirp.SweagentdAPI
}

func (r *recordingTwirpClient) SweagentdAPI() sweagentdTwirp.SweagentdAPI {
	return r.sweagentdAPI
}

func TestDockerLauncher_ApplyMCPSettingsTriggeredPermissionRestrictions(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	actorID := int64(12345)

	createMCPMock := func(mcpPerms map[string]string) func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
			mcpConfig := mcpconfig.JSON{}
			if len(mcpPerms) > 0 {
				mcpConfig.GitHub = &mcpconfig.GitHub{
					Permissions: mcpPerms,
				}
			}
			configJSON, err := json.Marshal(mcpConfig)
			if err != nil {
				t.Fatalf("failed to marshal MCP config in test: %v", err)
			}
			return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled:         true,
				McpConfigurationJson: string(configJSON),
			}, nil
		}
	}

	tests := []struct {
		name                 string
		permissions          map[string]string
		isTriggered          bool
		expectedActionsValue string
		expectDeployments    bool
	}{
		{
			name: "triggered jobs are downscoped before token minting",
			permissions: map[string]string{
				"actions":     "write",
				"contents":    "write",
				"deployments": "read",
			},
			isTriggered:          true,
			expectedActionsValue: "read",
			expectDeployments:    false,
		},
		{
			name: "non-triggered jobs keep actions write",
			permissions: map[string]string{
				"actions":  "write",
				"contents": "write",
			},
			isTriggered:          false,
			expectedActionsValue: "write",
			expectDeployments:    false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			api := &recordingSweagentdAPI{
				NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{},
			}
			api.MockMCPConfigurationForRepository = createMCPMock(nil)

			ghTwirp := &recordingTwirpClient{
				NoopClient:   githubtwirp.NewNoopClient(),
				sweagentdAPI: api,
			}

			launcher := &DockerLauncher{
				obsv:     observability.NewNoopExporters(),
				ffClient: featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentCustomAgentTriggers: true}),
				ghTwirp:  ghTwirp,
			}

			envVars, err := launcher.applyMCPSettings(ctx, &LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agenticapptest.NewTestCopilot(t),
				CustomAgent: &mockCustomAgent{
					permissions: tt.permissions,
				},
				IsTriggered: tt.isTriggered,
				SessionID:   "session-123",
			})
			require.NoError(t, err)
			assert.Contains(t, envVars, "GITHUB_PERSONAL_ACCESS_TOKEN=mock-token")

			require.NotNil(t, api.lastMintUserToServerTokenForRepoRequest)
			assert.Equal(t, tt.expectedActionsValue, api.lastMintUserToServerTokenForRepoRequest.Permissions["actions"])
			assert.Equal(t, "write", api.lastMintUserToServerTokenForRepoRequest.Permissions["contents"])
			if tt.expectDeployments {
				assert.Contains(t, api.lastMintUserToServerTokenForRepoRequest.Permissions, "deployments")
			} else {
				assert.NotContains(t, api.lastMintUserToServerTokenForRepoRequest.Permissions, "deployments")
			}
		})
	}
}

func TestDockerLauncher_ApplyMCPSettingsMCPPermissionGateExpandsDefaults(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	actorID := int64(12345)

	// MCP returns no agent / repo permissions — the gate FF should cause
	// the launcher to mint a token with MCPWriteDefault instead of Default.
	mcpMock := func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		mcpConfig := mcpconfig.JSON{}
		configJSON, err := json.Marshal(mcpConfig)
		if err != nil {
			panic(fmt.Sprintf("failed to marshal MCP config in test: %v", err))
		}
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
			IsMcpEnabled:         true,
			McpConfigurationJson: string(configJSON),
		}, nil
	}

	tests := []struct {
		name                string
		ffEnabled           bool
		thirdPartyAgent     bool
		expectedContents    string
		expectedDiscussions string
		expectedIssues      string
		expectedPRs         string
		expectedActions     string
	}{
		{
			name:                "FF off — read-only defaults (Default)",
			ffEnabled:           false,
			expectedContents:    "read",
			expectedDiscussions: "read",
			expectedIssues:      "read",
			expectedPRs:         "read",
			expectedActions:     "read",
		},
		{
			name:                "FF on — read-write defaults (MCPWriteDefault)",
			ffEnabled:           true,
			expectedContents:    "write",
			expectedDiscussions: "write",
			expectedIssues:      "write",
			expectedPRs:         "write",
			expectedActions:     "write",
		},
		{
			name:                "FF on but third-party agent — read-only defaults (gate scoped to CCA)",
			ffEnabled:           true,
			thirdPartyAgent:     true,
			expectedContents:    "read",
			expectedDiscussions: "read",
			expectedIssues:      "read",
			expectedPRs:         "read",
			expectedActions:     "read",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			api := &recordingSweagentdAPI{
				NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{},
			}
			api.MockMCPConfigurationForRepository = mcpMock

			ghTwirp := &recordingTwirpClient{
				NoopClient:   githubtwirp.NewNoopClient(),
				sweagentdAPI: api,
			}

			launcher := &DockerLauncher{
				obsv: observability.NewNoopExporters(),
				ffClient: featureflags.NewNoopClient(map[string]bool{
					featureflags.CopilotSWEAgentMCPPermissionGate: tt.ffEnabled,
				}),
				ghTwirp:     ghTwirp,
				appProvider: agenticapptest.NewTestProvider(t),
			}

			var agent sweagentd.AgenticApp = agenticapptest.NewTestCopilot(t)
			if tt.thirdPartyAgent {
				agent = agenticapp.NewClaude(999, "claude-app", 1000, "claude-bot", "commit-login", "commit@email.com")
			}

			_, err := launcher.applyMCPSettings(ctx, &LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agent,
				// No CustomAgent permissions provider — agent perms remain Unset.
				SessionID: "session-123",
			})
			require.NoError(t, err)

			require.NotNil(t, api.lastMintUserToServerTokenForRepoRequest)
			perms := api.lastMintUserToServerTokenForRepoRequest.Permissions
			assert.Equal(t, tt.expectedContents, perms["contents"])
			assert.Equal(t, tt.expectedDiscussions, perms["discussions"])
			assert.Equal(t, tt.expectedIssues, perms["issues"])
			assert.Equal(t, tt.expectedPRs, perms["pull_requests"])
			assert.Equal(t, tt.expectedActions, perms["actions"])
			// Metadata is always read.
			assert.Equal(t, "read", perms["metadata"])
		})
	}
}

type mockWorkflowRunCompletedHandler struct {
	called bool
}

func (m *mockWorkflowRunCompletedHandler) OnWorkflowRunCompleted(_ context.Context, _ WorkflowRunCompletedEvent) error {
	m.called = true
	return nil
}

func TestRegistryAuthJSONEncoding(t *testing.T) {
	// This test verifies that the registry auth JSON encoding produces valid JSON
	// and that the format using %q matches the expected output.
	tests := []struct {
		name     string
		username string
		password string
	}{
		{
			name:     "simple credentials",
			username: "testuser",
			password: "testpass",
		},
		{
			name:     "credentials with special chars",
			username: "user@example.com",
			password: "p@ss!word#123",
		},
		{
			name:     "empty credentials",
			username: "",
			password: "",
		},
		{
			name:     "credentials with spaces",
			username: "user name",
			password: "pass word",
		},
		{
			name:     "credentials with quotes",
			username: `user"name`,
			password: `pass"word`,
		},
		{
			name:     "credentials with backslashes",
			username: `user\name`,
			password: `pass\word`,
		},
		{
			name:     "credentials with unicode",
			username: "用户名", //nolint:gosmopolitan // Testing unicode handling
			password: "密码",  //nolint:gosmopolitan // Testing unicode handling
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			// Generate the JSON using the current %q format
			jsonBytes := fmt.Appendf(nil, `{ "username": %q, "password": %q }`, tc.username, tc.password)

			// Verify it's valid JSON by unmarshaling
			var result map[string]string
			err := json.Unmarshal(jsonBytes, &result)
			require.NoError(t, err, "generated JSON should be valid: %s", string(jsonBytes))

			// Verify the values are correct
			assert.Equal(t, tc.username, result["username"], "username should match")
			assert.Equal(t, tc.password, result["password"], "password should match")
		})
	}
}

func TestRegistryAuthJSONEncoding_MatchesOldFormat(t *testing.T) {
	// This test verifies that for simple strings (without special characters),
	// the new %q format produces equivalent JSON to the old "%s" format.
	// For strings with special characters, %q correctly escapes them while the old format would not.
	tests := []struct {
		name     string
		username string
		password string
	}{
		{
			name:     "simple alphanumeric",
			username: "testuser",
			password: "testpass123",
		},
		{
			name:     "with dots and hyphens",
			username: "user.name",
			password: "pass-word",
		},
		{
			name:     "typical docker registry credentials",
			username: "myregistry.azurecr.io",
			password: "supersecrettoken",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			// Generate JSON using the new %q format
			newJSON := fmt.Appendf(nil, `{ "username": %q, "password": %q }`, tc.username, tc.password)

			// For simple strings without quotes/backslashes, the old format would produce:
			// This simulates what the old format would have produced
			oldJSON := fmt.Appendf(nil, "{ \"username\": \"%s\", \"password\": \"%s\" }", tc.username, tc.password)

			// Both should produce identical output for simple strings
			assert.JSONEq(t, string(oldJSON), string(newJSON), "new format should match old format for simple strings")

			// Verify both are valid JSON
			var newResult, oldResult map[string]string
			require.NoError(t, json.Unmarshal(newJSON, &newResult))
			require.NoError(t, json.Unmarshal(oldJSON, &oldResult))

			// Values should be identical
			assert.Equal(t, oldResult["username"], newResult["username"])
			assert.Equal(t, oldResult["password"], newResult["password"])
		})
	}
}

func TestRegistryAuthJSONEncoding_HandlesSpecialCharsBetter(t *testing.T) {
	// This test demonstrates that %q properly escapes special characters
	// that would have broken the old "%s" format.
	tests := []struct {
		name     string
		username string
		password string
	}{
		{
			name:     "password with quotes",
			username: "user",
			password: `my"password`,
		},
		{
			name:     "password with backslash",
			username: "user",
			password: `my\password`,
		},
		{
			name:     "password with newline",
			username: "user",
			password: "my\npassword",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			// Generate JSON using the new %q format
			newJSON := fmt.Appendf(nil, `{ "username": %q, "password": %q }`, tc.username, tc.password)

			// The new format should produce valid JSON
			var result map[string]string
			err := json.Unmarshal(newJSON, &result)
			require.NoError(t, err, "new format should produce valid JSON: %s", string(newJSON))

			// Values should be correctly decoded
			assert.Equal(t, tc.username, result["username"])
			assert.Equal(t, tc.password, result["password"])

			// The old format would have produced invalid JSON for these cases
			// (but we don't test it because it would fail)
		})
	}
}

func TestLoadMCPDevEnv_FileNotPresent(t *testing.T) {
	// Ensure the file doesn't exist by running in a temp dir
	t.Chdir(t.TempDir())

	envVars, err := loadMCPDevEnv()
	require.NoError(t, err)
	assert.Nil(t, envVars)
}

func TestLoadMCPDevEnv_ReadsKeyValuePairs(t *testing.T) {
	dir := t.TempDir()
	t.Chdir(dir)

	content := "COPILOT_MCP_SECRET_KEY=super-secret\nCOPILOT_MCP_ANOTHER_VAR=hello-world\n"
	err := os.WriteFile(mcpDevEnvFile, []byte(content), 0o600)
	require.NoError(t, err)

	envVars, err := loadMCPDevEnv()
	require.NoError(t, err)

	slices.Sort(envVars)
	assert.Equal(t, []string{"COPILOT_MCP_ANOTHER_VAR=hello-world", "COPILOT_MCP_SECRET_KEY=super-secret"}, envVars)
}

func TestLoadMCPDevEnv_EmptyFile(t *testing.T) {
	dir := t.TempDir()
	t.Chdir(dir)

	err := os.WriteFile(mcpDevEnvFile, []byte(""), 0o600)
	require.NoError(t, err)

	envVars, err := loadMCPDevEnv()
	require.NoError(t, err)
	assert.Empty(t, envVars)
}

func TestLoadMCPDevEnv_MalformedFile(t *testing.T) {
	dir := t.TempDir()
	t.Chdir(dir)

	err := os.WriteFile(mcpDevEnvFile, []byte("'bad_line\n"), 0o600)
	require.NoError(t, err)

	_, err = loadMCPDevEnv()
	assert.Error(t, err)
}

func TestWriteAgentInputsEventFile(t *testing.T) {
	vars := Variables{
		"COPILOT_AGENT_JOB_ID":       {Value: "job-123", Required: true},
		"COPILOT_AGENT_CALLBACK_URL": {Value: "https://callback.example.com", Required: true},
		"COPILOT_JOB_NONCE":          {Value: "nonce-abc", Required: true},
		"COPILOT_API_URL":            {Value: "https://api.example.com", Required: true},
	}

	path, err := writeAgentInputsEventFile(vars)
	require.NoError(t, err)
	defer os.Remove(path)

	// Verify file exists with restrictive permissions
	info, err := os.Stat(path)
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0o600), info.Mode().Perm(), "event file should have 0600 permissions")

	// Read and parse the event file
	data, err := os.ReadFile(path)
	require.NoError(t, err)

	var event struct {
		Inputs map[string]string `json:"inputs"`
	}
	err = json.Unmarshal(data, &event)
	require.NoError(t, err)

	// Verify COPILOT_AGENT_INPUTS is present
	inputsJSON, ok := event.Inputs["COPILOT_AGENT_INPUTS"]
	assert.True(t, ok, "event should contain COPILOT_AGENT_INPUTS")

	// Parse the inner JSON
	var inputs map[string]string
	err = json.Unmarshal([]byte(inputsJSON), &inputs)
	require.NoError(t, err)

	assert.Equal(t, "job-123", inputs["COPILOT_AGENT_JOB_ID"])
	assert.Equal(t, "https://callback.example.com", inputs["COPILOT_AGENT_CALLBACK_URL"])
	assert.Equal(t, "nonce-abc", inputs["COPILOT_JOB_NONCE"])
	assert.Equal(t, "https://api.example.com", inputs["COPILOT_API_URL"])
}

func TestWriteAgentInputsEventFile_EmptyVars(t *testing.T) {
	vars := Variables{}

	path, err := writeAgentInputsEventFile(vars)
	require.NoError(t, err)
	defer os.Remove(path)

	data, err := os.ReadFile(path)
	require.NoError(t, err)

	var event struct {
		Inputs map[string]string `json:"inputs"`
	}
	err = json.Unmarshal(data, &event)
	require.NoError(t, err)

	// Even with empty vars, the structure should be valid
	inputsJSON, ok := event.Inputs["COPILOT_AGENT_INPUTS"]
	assert.True(t, ok)

	var inputs map[string]string
	err = json.Unmarshal([]byte(inputsJSON), &inputs)
	require.NoError(t, err)
	assert.Empty(t, inputs)
}

func TestDockerRuntimeEntryPoint_CCAv3DoesNotOverridePartnerAgents(t *testing.T) {
	ctx := context.Background()

	t.Run("claude agent uses claude runtime even when cca v3 flag is enabled", func(t *testing.T) {
		launcher := &DockerLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			}),
		}
		claude := agenticapp.NewClaude(1, "claude-app", 2, "claude-bot", "commit-login", "commit@email.com")
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             claude,
		}
		entryPoint := launcher.getRuntimeEntryPoint(ctx, opts)
		assert.Equal(t, "dist-claude/index.js", entryPoint)
	})

	t.Run("codex agent uses codex runtime even when cca v3 flag is enabled", func(t *testing.T) {
		launcher := &DockerLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			}),
		}
		codex := agenticapp.NewCodex(1, "codex-app", 2, "codex-bot", "commit-login", "commit@email.com")
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             codex,
		}
		entryPoint := launcher.getRuntimeEntryPoint(ctx, opts)
		assert.Equal(t, "dist-codex/index.js", entryPoint)
	})

	t.Run("third-party agent uses cca v3 runtime when cca v3 flag is enabled", func(t *testing.T) {
		launcher := &DockerLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			}),
		}
		thirdParty := agenticapp.NewThirdParty(1, "third-party-agent", "", 2, "third-party-agent-bot", "commit-login", "commit@email.com", nil, nil)
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             thirdParty,
		}
		entryPoint := launcher.getRuntimeEntryPoint(ctx, opts)
		assert.Equal(t, "dist-cca-v3/index.js", entryPoint)
	})

	t.Run("third-party agent uses default Copilot runtime when cca v3 flag is disabled", func(t *testing.T) {
		launcher := &DockerLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: false,
			}),
		}
		thirdParty := agenticapp.NewThirdParty(1, "third-party-agent", "", 2, "third-party-agent-bot", "commit-login", "commit@email.com", nil, nil)
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             thirdParty,
		}
		entryPoint := launcher.getRuntimeEntryPoint(ctx, opts)
		assert.Equal(t, "dist/index.js", entryPoint)
	})

	t.Run("third-party agent uses default Copilot runtime when cca v3 opt-out flag is enabled", func(t *testing.T) {
		launcher := &DockerLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App:       true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3AppOptOut: true,
			}),
		}
		thirdParty := agenticapp.NewThirdParty(1, "third-party-agent", "", 2, "third-party-agent-bot", "commit-login", "commit@email.com", nil, nil)
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             thirdParty,
		}
		entryPoint := launcher.getRuntimeEntryPoint(ctx, opts)
		assert.Equal(t, "dist/index.js", entryPoint)
	})
}
