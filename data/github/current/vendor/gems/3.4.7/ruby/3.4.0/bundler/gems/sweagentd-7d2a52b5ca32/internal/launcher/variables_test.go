package launcher

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/stretchr/testify/assert"
)

func TestFirewallFeatureFlagging(t *testing.T) {
	ctx := context.Background()
	ffClientEnabled := featureflags.NewNoopClient(map[string]bool{copilotSWEAgentFirewallFFName: true})
	ffClientDisabled := featureflags.NewNoopClient(map[string]bool{copilotSWEAgentFirewallFFName: false})

	// FF enabled, config is disabled
	assert.True(t, isFirewallEnabledByDefault(ctx, ffClientEnabled, AgentLauncherOpts{AgentFirewallEnabledDefault: false}))
	// FF enabled, config is enabled
	assert.True(t, isFirewallEnabledByDefault(ctx, ffClientEnabled, AgentLauncherOpts{AgentFirewallEnabledDefault: true}))
	// FF disabled, config is disabled
	assert.False(t, isFirewallEnabledByDefault(ctx, ffClientDisabled, AgentLauncherOpts{AgentFirewallEnabledDefault: false}))
	// FF enabled, config is enabled
	assert.True(t, isFirewallEnabledByDefault(ctx, ffClientDisabled, AgentLauncherOpts{AgentFirewallEnabledDefault: true}))

}

func TestValidateRequiredVariables(t *testing.T) {
	tests := []struct {
		name      string
		vars      variables
		wantError bool
		errorMsg  string
	}{
		{
			name: "all required variables present",
			vars: variables{
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
			vars: variables{
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
			vars: variables{
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
			vars: variables{
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
			vars: variables{
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
				assert.Error(t, err)
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
