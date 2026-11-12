package launcher

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	jobscustomagent "github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockCustomAgent is a mock implementation of sweagentd.CustomAgent for testing
type mockCustomAgent struct {
	permissions map[string]string
	triggers    sweagentd.CustomAgentTriggers
}

func (m *mockCustomAgent) Name() string                             { return "mock-agent" }
func (m *mockCustomAgent) RepoOwnerID() int64                       { return 1 }
func (m *mockCustomAgent) RepoOwner() string                        { return "owner" }
func (m *mockCustomAgent) RepoID() int64                            { return 2 }
func (m *mockCustomAgent) RepoName() string                         { return "repo" }
func (m *mockCustomAgent) DisplayName() string                      { return "Mock Agent" }
func (m *mockCustomAgent) Description() string                      { return "A mock agent" }
func (m *mockCustomAgent) Prompt() string                           { return "Test prompt" }
func (m *mockCustomAgent) Tools() []string                          { return []string{"*"} }
func (m *mockCustomAgent) Version() string                          { return "1.0.0" }
func (m *mockCustomAgent) MCPConfig() mcpconfig.JSON                { return mcpconfig.JSON{} }
func (m *mockCustomAgent) Target() string                           { return "" }
func (m *mockCustomAgent) ConfigError() string                      { return "" }
func (m *mockCustomAgent) Metadata() map[string]string              { return nil }
func (m *mockCustomAgent) ArgumentHint() string                     { return "" }
func (m *mockCustomAgent) InferenceEnabled() bool                   { return true }
func (m *mockCustomAgent) Model() string                            { return "" }
func (m *mockCustomAgent) Handoffs() []sweagentd.CustomAgentHandoff { return nil }
func (m *mockCustomAgent) Permissions() map[string]string           { return m.permissions }
func (m *mockCustomAgent) Triggers() sweagentd.CustomAgentTriggers  { return m.triggers }
func (m *mockCustomAgent) Scope() string                            { return jobscustomagent.ScopeRepo }
func (m *mockCustomAgent) ToDB() jobscustomagent.DBRecord           { return jobscustomagent.DBRecord{} }
func TestCustomAgentPermissions(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.NewContext(ctx)
	actorID := int64(12345)
	mockAgent := &mockCustomAgent{
		permissions: map[string]string{
			"contents":      "write",
			"issues":        "read",
			"pull-requests": "write",
		},
	}
	t.Run("uses custom agent permissions when feature flag enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					RuntimeSHA: "deadbeef",
				},
			},
		}
		opts := LaunchAgentOpts{
			ActorID:           actorID,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             agenticapptest.NewTestCopilot(t),
			CustomAgent:       mockAgent,
		}
		envVars, err := launcher.environmentVariables(ctx, &opts, &Variables{})
		require.NoError(t, err)
		// Check that COPILOT_AGENT_PERMISSIONS is set
		assert.Contains(t, envVars, "COPILOT_AGENT_PERMISSIONS")
		// Parse the permissions JSON
		var permissions map[string]string
		err = json.Unmarshal([]byte(envVars["COPILOT_AGENT_PERMISSIONS"]), &permissions)
		require.NoError(t, err)
		// Verify permissions are converted from actions style (hyphen) to scopes style (underscore)
		assert.Equal(t, "write", permissions["contents"])
		assert.Equal(t, "read", permissions["issues"])
		assert.Equal(t, "write", permissions["pull_requests"])
		// Metadata should always be read
		assert.Equal(t, "read", permissions["metadata"])
	})
	t.Run("does not set permissions when feature flag disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: false,
		})
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					RuntimeSHA: "deadbeef",
				},
			},
		}
		opts := LaunchAgentOpts{
			ActorID:           actorID,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             agenticapptest.NewTestCopilot(t),
			CustomAgent:       mockAgent,
		}
		envVars, err := launcher.environmentVariables(ctx, &opts, &Variables{})
		require.NoError(t, err)
		// COPILOT_AGENT_PERMISSIONS should be empty or not set when feature flag is disabled
		permissionsJSON, exists := envVars["COPILOT_AGENT_PERMISSIONS"]
		if exists {
			assert.Empty(t, permissionsJSON, "COPILOT_AGENT_PERMISSIONS should be empty when feature flag is disabled")
		}
	})
	t.Run("uses default permissions when custom agent is nil", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					RuntimeSHA: "deadbeef",
				},
			},
		}
		opts := LaunchAgentOpts{
			ActorID:           actorID,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             agenticapptest.NewTestCopilot(t),
			CustomAgent:       nil,
		}
		envVars, err := launcher.environmentVariables(ctx, &opts, &Variables{})
		require.NoError(t, err)
		// Parse the permissions JSON
		var permissions map[string]string
		err = json.Unmarshal([]byte(envVars["COPILOT_AGENT_PERMISSIONS"]), &permissions)
		require.NoError(t, err)
		// Should use default permissions when custom agent is nil
		assert.Equal(t, "read", permissions["actions"])
		assert.Equal(t, "read", permissions["contents"])
		assert.Equal(t, "read", permissions["issues"])
		assert.Equal(t, "read", permissions["metadata"])
		assert.Equal(t, "read", permissions["pull_requests"])
		assert.NotContains(t, permissions, "workflows")
	})
	t.Run("filters out none permissions", func(t *testing.T) {
		mockAgentWithNone := &mockCustomAgent{
			permissions: map[string]string{
				"contents":      "write",
				"issues":        "none",
				"pull-requests": "read",
			},
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					RuntimeSHA: "deadbeef",
				},
			},
		}
		opts := LaunchAgentOpts{
			ActorID:           actorID,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             agenticapptest.NewTestCopilot(t),
			CustomAgent:       mockAgentWithNone,
		}
		envVars, err := launcher.environmentVariables(ctx, &opts, &Variables{})
		require.NoError(t, err)
		// Parse the permissions JSON
		var permissions map[string]string
		err = json.Unmarshal([]byte(envVars["COPILOT_AGENT_PERMISSIONS"]), &permissions)
		require.NoError(t, err)
		// Should include write and read permissions
		assert.Equal(t, "write", permissions["contents"])
		assert.Equal(t, "read", permissions["pull_requests"])
		// Should NOT include "none" permissions
		assert.NotContains(t, permissions, "issues")
	})
	t.Run("errors out on invalid permissions", func(t *testing.T) {
		mockAgentWithUnknown := &mockCustomAgent{
			permissions: map[string]string{
				"contents":      "write",
				"unknown-scope": "read",
				"another-fake":  "write",
				"pull-requests": "read",
			},
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					RuntimeSHA: "deadbeef",
				},
			},
		}
		opts := LaunchAgentOpts{
			ActorID:           actorID,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             agenticapptest.NewTestCopilot(t),
			CustomAgent:       mockAgentWithUnknown,
		}
		_, err := launcher.environmentVariables(ctx, &opts, &Variables{})
		require.Error(t, err)
	})
	t.Run("converts hyphen to underscore in permission keys", func(t *testing.T) {
		mockAgentWithHyphens := &mockCustomAgent{
			permissions: map[string]string{
				"pull-requests": "write",
			},
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					RuntimeSHA: "deadbeef",
				},
			},
		}
		opts := LaunchAgentOpts{
			ActorID:           actorID,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             agenticapptest.NewTestCopilot(t),
			CustomAgent:       mockAgentWithHyphens,
		}
		envVars, err := launcher.environmentVariables(ctx, &opts, &Variables{})
		require.NoError(t, err)
		// Parse the permissions JSON
		var permissions map[string]string
		err = json.Unmarshal([]byte(envVars["COPILOT_AGENT_PERMISSIONS"]), &permissions)
		require.NoError(t, err)
		// Should convert hyphen to underscore
		assert.Equal(t, "write", permissions["pull_requests"])
		// Should NOT contain the hyphenated version
		assert.NotContains(t, permissions, "pull-requests")
	})
}
