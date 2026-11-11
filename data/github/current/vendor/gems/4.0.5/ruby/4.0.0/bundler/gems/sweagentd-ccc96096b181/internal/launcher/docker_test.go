package launcher

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
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
	launcher, err := NewDockerLauncher(obsv, ffClient, &originalOpts)

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

	launcher, err := NewDockerLauncher(obsv, ffClient, opts)
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

	launcher, err := NewDockerLauncher(obsv, ffClient, opts)
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

	launcher, err := NewDockerLauncher(obsv, ffClient, opts)
	require.NoError(t, err)

	assert.Equal(t, TypeDocker, launcher.LauncherType())
}

// mockWorkflowRunCompletedHandler is a mock implementation for testing
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
