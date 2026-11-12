package launcher

import (
	"context"
	"encoding/json"
	"html/template"
	"testing"

	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	jobscustomagent "github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/runnerlabels"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
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
func (m *mockCustomAgent) DisableModelInvocation() bool             { return false }
func (m *mockCustomAgent) UserInvocable() bool                      { return true }
func (m *mockCustomAgent) Model() string                            { return "" }
func (m *mockCustomAgent) Handoffs() []sweagentd.CustomAgentHandoff { return nil }
func (m *mockCustomAgent) Permissions() permissions.Permissions {
	return permissions.New(m.permissions)
}
func (m *mockCustomAgent) Triggers() sweagentd.CustomAgentTriggers { return m.triggers }
func (m *mockCustomAgent) GitHubMCPToolsets() []string             { return nil }
func (m *mockCustomAgent) Skills() []string                        { return nil }
func (m *mockCustomAgent) Scope() string                           { return agentconfig.ScopeRepository }
func (m *mockCustomAgent) ToDB() jobscustomagent.DBRecord          { return jobscustomagent.DBRecord{} }

// TestCustomAgentPermissions tests that custom agent permissions are handled correctly.
// Note: COPILOT_AGENT_PERMISSIONS is now set as part of MCP configuration in applyMCPSettings,
// not in environmentVariables. These tests use applyMCPSettings to validate permission handling.
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

	// Helper to create a mock MCP configuration response
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

	t.Run("uses custom agent permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(nil)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
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
		data := workflowData{}
		_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
		require.NoError(t, err)
		require.NotEmpty(t, permissionsJSON)

		// Parse the permissions JSON
		var perms map[string]string
		err = json.Unmarshal([]byte(permissionsJSON), &perms)
		require.NoError(t, err)

		// Verify permissions are converted from actions style (hyphen) to scopes style (underscore)
		assert.Equal(t, "write", perms["contents"])
		assert.Equal(t, "read", perms["issues"])
		assert.Equal(t, "write", perms["pull_requests"])
		// Metadata should always be read
		assert.Equal(t, "read", perms["metadata"])
	})

	t.Run("uses agent provided permissions when both custom agent and MCP config have permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentRepoConfigCustomPermissions: true,
		})

		// MCP config has its own permissions
		mcpPerms := map[string]string{
			"contents": "read",  // Lower than custom agent
			"actions":  "write", // Not in custom agent
		}
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(mcpPerms)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
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
		data := workflowData{}
		_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
		require.NoError(t, err)
		require.NotEmpty(t, permissionsJSON)

		// Parse the permissions JSON
		var perms map[string]string
		err = json.Unmarshal([]byte(permissionsJSON), &perms)
		require.NoError(t, err)

		// ResolvePermissions uses agentProvided when set, so custom agent permissions should be used
		assert.Equal(t, "write", perms["contents"])
		assert.Equal(t, "read", perms["issues"])
		assert.Equal(t, "write", perms["pull_requests"])
		// MCP permissions should NOT override agent-provided permissions
		assert.NotContains(t, perms, "actions")
	})

	t.Run("permission precedence: custom agent > MCP config > defaults", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentRepoConfigCustomPermissions: true,
		})

		ghTwirp := githubtwirp.NewNoopClient()

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					RuntimeSHA: "deadbeef",
				},
			},
		}

		// Test 1: Custom agent permissions take precedence over MCP config
		t.Run("custom agent overrides MCP config", func(t *testing.T) {
			mcpPerms := map[string]string{
				"contents": "read",
				"actions":  "write",
			}
			ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(mcpPerms)

			agentWithPerms := &mockCustomAgent{
				permissions: map[string]string{
					"contents": "write", // Should override MCP's "read"
					"issues":   "write", // Not in MCP config
				},
			}

			opts := LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agenticapptest.NewTestCopilot(t),
				CustomAgent:       agentWithPerms,
			}
			data := workflowData{}
			_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
			require.NoError(t, err)
			require.NotEmpty(t, permissionsJSON)

			var perms map[string]string
			err = json.Unmarshal([]byte(permissionsJSON), &perms)
			require.NoError(t, err)

			// Custom agent permissions win
			assert.Equal(t, "write", perms["contents"], "custom agent 'write' should override MCP 'read'")
			assert.Equal(t, "write", perms["issues"], "custom agent permissions should be included")
			// MCP permissions should be ignored when custom agent has permissions
			assert.NotContains(t, perms, "actions", "MCP-only permissions should not appear when custom agent has permissions")
		})

		// Test 2: MCP config permissions used when custom agent has no permissions
		t.Run("MCP config used when custom agent has no permissions", func(t *testing.T) {
			mcpPerms := map[string]string{
				"contents": "write",
				"actions":  "read",
				"issues":   "write",
			}
			ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(mcpPerms)

			agentWithoutPerms := &mockCustomAgent{
				permissions: map[string]string{}, // No permissions
			}

			opts := LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agenticapptest.NewTestCopilot(t),
				CustomAgent:       agentWithoutPerms,
			}
			data := workflowData{}
			_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
			require.NoError(t, err)
			require.NotEmpty(t, permissionsJSON)

			var perms map[string]string
			err = json.Unmarshal([]byte(permissionsJSON), &perms)
			require.NoError(t, err)

			// MCP permissions should be used
			assert.Equal(t, "write", perms["contents"], "MCP config should be used when custom agent has no permissions")
			assert.Equal(t, "read", perms["actions"], "MCP config should be used when custom agent has no permissions")
			assert.Equal(t, "write", perms["issues"], "MCP config should be used when custom agent has no permissions")
		})

		// Test 3: Default permissions used when neither custom agent nor MCP have permissions
		t.Run("defaults used when neither custom agent nor MCP have permissions", func(t *testing.T) {
			// MCP config with empty GitHub permissions
			ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
				mcpConfig := mcpconfig.JSON{
					GitHub: &mcpconfig.GitHub{
						Permissions: map[string]string{}, // Empty permissions
					},
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

			agentWithoutPerms := &mockCustomAgent{
				permissions: map[string]string{}, // No permissions
			}

			opts := LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agenticapptest.NewTestCopilot(t),
				CustomAgent:       agentWithoutPerms,
			}
			data := workflowData{}
			_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
			require.NoError(t, err)
			require.NotEmpty(t, permissionsJSON)

			var perms map[string]string
			err = json.Unmarshal([]byte(permissionsJSON), &perms)
			require.NoError(t, err)

			// Default permissions should be used when both custom agent and MCP have empty permissions
			assert.Equal(t, "read", perms["actions"], "default permissions should be used")
			assert.Equal(t, "read", perms["contents"], "default permissions should be used")
			assert.Equal(t, "read", perms["discussions"], "default permissions should be used")
			assert.Equal(t, "read", perms["issues"], "default permissions should be used")
			assert.Equal(t, "read", perms["metadata"], "default permissions should be used")
			assert.Equal(t, "read", perms["pull_requests"], "default permissions should be used")
			// Workflows should not be in defaults
			assert.NotContains(t, perms, "workflows", "workflows should not be in default permissions")
		})
	})

	t.Run("ignores MCP config permissions when repo config custom permissions flag disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentRepoConfigCustomPermissions: false,
		})

		mcpPerms := map[string]string{
			"contents": "write",
			"actions":  "write",
		}
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(mcpPerms)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					RuntimeSHA: "deadbeef",
				},
			},
		}

		agentWithoutPerms := &mockCustomAgent{
			permissions: map[string]string{}, // No permissions
		}

		opts := LaunchAgentOpts{
			ActorID:           actorID,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             agenticapptest.NewTestCopilot(t),
			CustomAgent:       agentWithoutPerms,
		}
		data := workflowData{}
		_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
		require.NoError(t, err)
		require.NotEmpty(t, permissionsJSON)

		var perms map[string]string
		err = json.Unmarshal([]byte(permissionsJSON), &perms)
		require.NoError(t, err)

		// MCP config permissions should be ignored; defaults should be used instead
		assert.Equal(t, "read", perms["contents"], "defaults should be used when repo config custom permissions flag is disabled")
		assert.Equal(t, "read", perms["actions"], "defaults should be used when repo config custom permissions flag is disabled")
		assert.Equal(t, "read", perms["discussions"], "defaults should be used when repo config custom permissions flag is disabled")
		assert.Equal(t, "read", perms["issues"], "defaults should be used when repo config custom permissions flag is disabled")
		assert.Equal(t, "read", perms["metadata"], "defaults should be used when repo config custom permissions flag is disabled")
		assert.Equal(t, "read", perms["pull_requests"], "defaults should be used when repo config custom permissions flag is disabled")
	})

	t.Run("filters out none permissions", func(t *testing.T) {
		mockAgentWithNone := &mockCustomAgent{
			permissions: map[string]string{
				"contents":      "write",
				"issues":        "none",
				"pull-requests": "read",
			},
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(nil)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
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
		data := workflowData{}
		_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
		require.NoError(t, err)
		require.NotEmpty(t, permissionsJSON)

		// Parse the permissions JSON
		var perms map[string]string
		err = json.Unmarshal([]byte(permissionsJSON), &perms)
		require.NoError(t, err)

		// Should include write and read permissions
		assert.Equal(t, "write", perms["contents"])
		assert.Equal(t, "read", perms["pull_requests"])
		// Should NOT include "none" permissions
		assert.NotContains(t, perms, "issues")
	})

	t.Run("downscopes actions write for triggered jobs when triggers flag is enabled", func(t *testing.T) {
		mockAgentWithActionsWrite := &mockCustomAgent{
			permissions: map[string]string{
				"actions":     "write",
				"contents":    "write",
				"deployments": "read",
			},
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
		})
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(nil)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
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
			CustomAgent:       mockAgentWithActionsWrite,
			IsTriggered:       true,
		}
		data := workflowData{}
		_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
		require.NoError(t, err)

		var perms map[string]string
		err = json.Unmarshal([]byte(permissionsJSON), &perms)
		require.NoError(t, err)
		assert.Equal(t, "read", perms["actions"])
		assert.Equal(t, "write", perms["contents"])
		assert.NotContains(t, perms, "deployments")
	})

	t.Run("keeps actions write for non-triggered jobs even when triggers flag is enabled", func(t *testing.T) {
		mockAgentWithActionsWrite := &mockCustomAgent{
			permissions: map[string]string{
				"actions":  "write",
				"contents": "write",
			},
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
		})
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(nil)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
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
			CustomAgent:       mockAgentWithActionsWrite,
			IsTriggered:       false,
		}
		data := workflowData{}
		_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
		require.NoError(t, err)

		var perms map[string]string
		err = json.Unmarshal([]byte(permissionsJSON), &perms)
		require.NoError(t, err)
		assert.Equal(t, "write", perms["actions"])
		assert.Equal(t, "write", perms["contents"])
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
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(nil)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
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
		data := workflowData{}
		_, _, _, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to convert resolved permissions")
	})

	t.Run("converts hyphen to underscore in permission keys", func(t *testing.T) {
		mockAgentWithHyphens := &mockCustomAgent{
			permissions: map[string]string{
				"pull-requests": "write",
			},
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = createMCPMock(nil)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
			ghTwirp:  ghTwirp,
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
		data := workflowData{}
		_, _, permissionsJSON, err := launcher.applyMCPSettings(ctx, &data, &opts, false)
		require.NoError(t, err)
		require.NotEmpty(t, permissionsJSON)

		// Parse the permissions JSON
		var perms map[string]string
		err = json.Unmarshal([]byte(permissionsJSON), &perms)
		require.NoError(t, err)

		// Should convert hyphen to underscore
		assert.Equal(t, "write", perms["pull_requests"])
		// Should NOT contain the hyphenated version
		assert.NotContains(t, perms, "pull-requests")
	})
}

func TestShellTokenEnabled(t *testing.T) {
	ctx := context.Background()
	actorID := int64(12345)

	copilotGitHubTokenLine := `GITHUB_COPILOT_GITHUB_TOKEN: "${{ secrets.GITHUB_COPILOT_GITHUB_TOKEN }}"`
	copilotAPITokenShellLine := `GITHUB_COPILOT_GITHUB_TOKEN: "${{ secrets.GITHUB_COPILOT_API_TOKEN }}"`

	tests := []struct {
		name                               string
		featureFlags                       map[string]bool
		expectCopilotGitHubTokenInWorkflow bool
		expectShellUsesGitHubToken         bool
	}{
		{
			name:                               "shell uses API token by default",
			featureFlags:                       map[string]bool{},
			expectCopilotGitHubTokenInWorkflow: true,
			expectShellUsesGitHubToken:         false,
		},
		{
			name: "shell token with permissions flag - shell gets full token",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentShellTokenPermissions: true,
			},
			expectCopilotGitHubTokenInWorkflow: true,
			expectShellUsesGitHubToken:         true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(tt.featureFlags)
			launcher := &ActionsLauncher{
				ffClient: ffClient,
				obsv:     observability.NewNoopExporters(),
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
				},
			}

			opts := &LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agenticapptest.NewTestCopilot(t),
			}

			data := workflowData{
				RunName:          "Test workflow",
				MCPEnabled:       true,
				TokenSecretNames: getGitHubTokenSecretNames(ctx, ffClient, opts),
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML(runnerlabels.UbuntuLatestLabel),
					"timeout-minutes": template.HTML("59"),
				},
			}

			content, err := launcher.workflowContent(ctx, &data, workflowTemplate, nil)
			require.NoError(t, err, "workflowContent should not return an error")

			if tt.expectCopilotGitHubTokenInWorkflow {
				if tt.expectShellUsesGitHubToken {
					assert.Contains(t, content, copilotGitHubTokenLine, "workflow content should contain GITHUB_COPILOT_GITHUB_TOKEN with full token secret")
				} else {
					assert.Contains(t, content, copilotAPITokenShellLine, "workflow content should contain GITHUB_COPILOT_GITHUB_TOKEN with API token secret")
				}
			} else {
				assert.NotContains(t, content, copilotGitHubTokenLine, "workflow content should not contain GITHUB_COPILOT_GITHUB_TOKEN with full token")
				assert.NotContains(t, content, copilotAPITokenShellLine, "workflow content should not contain GITHUB_COPILOT_GITHUB_TOKEN with API token")
			}
		})
	}
}
