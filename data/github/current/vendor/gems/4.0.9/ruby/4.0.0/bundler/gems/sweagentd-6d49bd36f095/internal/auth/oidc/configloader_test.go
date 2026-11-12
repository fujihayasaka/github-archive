package oidc

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/auth/oidc/varfetcher"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
)

// mockAgent implements sweagentd.CustomAgent and mcpConfigProvider for testing.
type mockAgent struct {
	name      string
	mcpConfig mcpconfig.JSON
}

func (m *mockAgent) Name() string                             { return m.name }
func (m *mockAgent) RepoOwnerID() int64                       { return 0 }
func (m *mockAgent) RepoOwner() string                        { return "" }
func (m *mockAgent) RepoID() int64                            { return 0 }
func (m *mockAgent) RepoName() string                         { return "" }
func (m *mockAgent) DisplayName() string                      { return "" }
func (m *mockAgent) Description() string                      { return "" }
func (m *mockAgent) Prompt() string                           { return "" }
func (m *mockAgent) Tools() []string                          { return nil }
func (m *mockAgent) Version() string                          { return "" }
func (m *mockAgent) Target() string                           { return "" }
func (m *mockAgent) ConfigError() string                      { return "" }
func (m *mockAgent) Metadata() map[string]string              { return nil }
func (m *mockAgent) ArgumentHint() string                     { return "" }
func (m *mockAgent) InferenceEnabled() bool                   { return false }
func (m *mockAgent) DisableModelInvocation() bool             { return false }
func (m *mockAgent) UserInvocable() bool                      { return false }
func (m *mockAgent) Model() string                            { return "" }
func (m *mockAgent) Handoffs() []sweagentd.CustomAgentHandoff { return nil }
func (m *mockAgent) Triggers() sweagentd.CustomAgentTriggers  { return sweagentd.CustomAgentTriggers{} }
func (m *mockAgent) GitHubMCPToolsets() []string              { return nil }
func (m *mockAgent) Skills() []string                         { return nil }
func (m *mockAgent) Scope() string                            { return "repo" }
func (m *mockAgent) MCPConfig() mcpconfig.JSON                { return m.mcpConfig }

// Ensure mockAgent satisfies both interfaces at compile time.
var _ sweagentd.CustomAgent = &mockAgent{}
var _ mcpConfigProvider = &mockAgent{}

// mockAgentNoMCP implements only sweagentd.CustomAgent (no MCPConfig method).
type mockAgentNoMCP struct {
	name string
}

func (m *mockAgentNoMCP) Name() string                             { return m.name }
func (m *mockAgentNoMCP) RepoOwnerID() int64                       { return 0 }
func (m *mockAgentNoMCP) RepoOwner() string                        { return "" }
func (m *mockAgentNoMCP) RepoID() int64                            { return 0 }
func (m *mockAgentNoMCP) RepoName() string                         { return "" }
func (m *mockAgentNoMCP) DisplayName() string                      { return "" }
func (m *mockAgentNoMCP) Description() string                      { return "" }
func (m *mockAgentNoMCP) Prompt() string                           { return "" }
func (m *mockAgentNoMCP) Tools() []string                          { return nil }
func (m *mockAgentNoMCP) Version() string                          { return "" }
func (m *mockAgentNoMCP) Target() string                           { return "" }
func (m *mockAgentNoMCP) ConfigError() string                      { return "" }
func (m *mockAgentNoMCP) Metadata() map[string]string              { return nil }
func (m *mockAgentNoMCP) ArgumentHint() string                     { return "" }
func (m *mockAgentNoMCP) InferenceEnabled() bool                   { return false }
func (m *mockAgentNoMCP) DisableModelInvocation() bool             { return false }
func (m *mockAgentNoMCP) UserInvocable() bool                      { return false }
func (m *mockAgentNoMCP) Model() string                            { return "" }
func (m *mockAgentNoMCP) Handoffs() []sweagentd.CustomAgentHandoff { return nil }
func (m *mockAgentNoMCP) Triggers() sweagentd.CustomAgentTriggers {
	return sweagentd.CustomAgentTriggers{}
}
func (m *mockAgentNoMCP) GitHubMCPToolsets() []string { return nil }
func (m *mockAgentNoMCP) Skills() []string            { return nil }
func (m *mockAgentNoMCP) Scope() string               { return "repo" }

var _ sweagentd.CustomAgent = &mockAgentNoMCP{}

func mcpServer(tools []string, oidc *oidcconfig.ConfigEntry) mcpconfig.Server {
	return mcpconfig.Server{
		Tools: tools,
		Auth:  oidc,
	}
}

func TestNewConfigLoader(t *testing.T) {
	obsv := observability.NewNoopExporters()
	loader := NewConfigLoader(nil, nil, nil, obsv, nil)

	assert.NotNil(t, loader)
	assert.False(t, loader.localOnly)
}

func TestNewLocalConfigLoader(t *testing.T) {
	obsv := observability.NewNoopExporters()
	loader := NewLocalConfigLoader(nil, obsv, nil)

	assert.NotNil(t, loader)
	assert.True(t, loader.localOnly)
	assert.Nil(t, loader.spokes)
	assert.Nil(t, loader.ghTwirp)
}

func TestFromMCPJSON(t *testing.T) {
	loader := NewLocalConfigLoader(nil, observability.NewNoopExporters(), nil)

	oidcSingle := oidcconfig.ConfigEntry{Audience: "https://example.com"}
	oidcA := oidcconfig.ConfigEntry{Audience: "aud-a"}
	oidcB := oidcconfig.ConfigEntry{Audience: "aud-b"}
	oidcWithScope := oidcconfig.ConfigEntry{Audience: "aud-1", Scope: "read"}
	oidcFull := oidcconfig.ConfigEntry{
		Audience:  "https://api.example.com",
		Scope:     "openid profile",
		Resource:  "https://resource.example.com",
		ClientID:  "client-123",
		GrantType: oidcconfig.GrantTypeClientCredentials,
		Endpoints: oidcconfig.EndpointsConfig{
			Exchange: "https://exchange.example.com/token",
			Revoke:   "https://revoke.example.com/revoke",
		},
		AgentOnlySubject: true,
	}

	tests := []struct {
		name        string
		input       mcpconfig.JSON
		expectedLen int
		validate    func(t *testing.T, result map[string]oidcconfig.ConfigEntry)
	}{
		{
			name:        "empty servers",
			input:       mcpconfig.JSON{Servers: map[string]mcpconfig.Server{}},
			expectedLen: 0,
		},
		{
			name:        "nil servers",
			input:       mcpconfig.JSON{},
			expectedLen: 0,
		},
		{
			name: "no OIDC entries",
			input: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"server-a": mcpServer([]string{"tool1"}, nil),
					"server-b": mcpServer([]string{"tool2"}, nil),
				},
			},
			expectedLen: 0,
		},
		{
			name: "single OIDC entry",
			input: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"my-server": mcpServer([]string{"tool1"}, &oidcSingle),
				},
			},
			expectedLen: 1,
			validate: func(t *testing.T, result map[string]oidcconfig.ConfigEntry) {
				entry, ok := result["my-server"]
				require.True(t, ok)
				assert.Equal(t, "https://example.com", entry.Audience)
				assert.Equal(t, "my-server", entry.ServerName())
			},
		},
		{
			name: "multiple OIDC entries",
			input: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"server-a": mcpServer([]string{"tool1"}, &oidcA),
					"server-b": mcpServer([]string{"tool2"}, &oidcB),
				},
			},
			expectedLen: 2,
			validate: func(t *testing.T, result map[string]oidcconfig.ConfigEntry) {
				assert.Equal(t, "aud-a", result["server-a"].Audience)
				assert.Equal(t, "aud-b", result["server-b"].Audience)
			},
		},
		{
			name: "mixed servers",
			input: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"with-oidc":    mcpServer([]string{"tool1"}, &oidcWithScope),
					"without-oidc": mcpServer([]string{"tool2"}, nil),
				},
			},
			expectedLen: 1,
			validate: func(t *testing.T, result map[string]oidcconfig.ConfigEntry) {
				entry := result["with-oidc"]
				assert.Equal(t, "aud-1", entry.Audience)
				assert.Equal(t, "read", entry.Scope)
			},
		},
		{
			name: "preserves all fields",
			input: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"full-server": mcpServer([]string{"tool1"}, &oidcFull),
				},
			},
			expectedLen: 1,
			validate: func(t *testing.T, result map[string]oidcconfig.ConfigEntry) {
				entry := result["full-server"]
				assert.Equal(t, "https://api.example.com", entry.Audience)
				assert.Equal(t, "openid profile", entry.Scope)
				assert.Equal(t, "https://resource.example.com", entry.Resource)
				assert.Equal(t, "client-123", entry.ClientID)
				assert.Equal(t, oidcconfig.GrantTypeClientCredentials, entry.GrantType)
				assert.Equal(t, "https://exchange.example.com/token", entry.Endpoints.Exchange)
				assert.Equal(t, "https://revoke.example.com/revoke", entry.Endpoints.Revoke)
				assert.True(t, entry.AgentOnlySubject)
				assert.Equal(t, "full-server", entry.ServerName())
			},
		},
		{
			name: "derives base URL from remote server URL",
			input: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"remote-srv": {
						Type:   "http",
						Remote: &mcpconfig.Remote{URL: "https://api.example.com/v1/mcp"},
						Tools:  []string{"tool1"},
						Auth:   &oidcconfig.ConfigEntry{Audience: "aud-remote"},
					},
				},
			},
			expectedLen: 1,
			validate: func(t *testing.T, result map[string]oidcconfig.ConfigEntry) {
				entry := result["remote-srv"]
				assert.Equal(t, "aud-remote", entry.Audience)
				assert.Equal(t, "https://api.example.com/v1/mcp", entry.Endpoints.Base)
			},
		},
		{
			name: "preserves explicit base URL over server URL",
			input: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"remote-srv": {
						Type:   "http",
						Remote: &mcpconfig.Remote{URL: "https://api.example.com/v1/mcp"},
						Tools:  []string{"tool1"},
						Auth: &oidcconfig.ConfigEntry{
							Audience:  "aud-remote",
							Endpoints: oidcconfig.EndpointsConfig{Base: "https://auth.example.com"},
						},
					},
				},
			},
			expectedLen: 1,
			validate: func(t *testing.T, result map[string]oidcconfig.ConfigEntry) {
				entry := result["remote-srv"]
				assert.Equal(t, "https://auth.example.com", entry.Endpoints.Base)
			},
		},
		{
			name: "no base URL for local server without explicit base",
			input: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"local-srv": {
						Type:  "stdio",
						Local: &mcpconfig.Local{Command: "node"},
						Tools: []string{"tool1"},
						Auth: &oidcconfig.ConfigEntry{
							Audience: "aud-local",
							Endpoints: oidcconfig.EndpointsConfig{
								Exchange: "https://auth.example.com/token",
							},
						},
					},
				},
			},
			expectedLen: 1,
			validate: func(t *testing.T, result map[string]oidcconfig.ConfigEntry) {
				entry := result["local-srv"]
				assert.Empty(t, entry.Endpoints.Base)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := loader.fromMCPJSON(tt.input)
			require.NoError(t, err)

			if tt.expectedLen == 0 {
				assert.Empty(t, result)
			} else {
				require.Len(t, result, tt.expectedLen)
			}

			if tt.validate != nil {
				tt.validate(t, result)
			}
		})
	}

	t.Run("invalid remote server URL returns error", func(t *testing.T) {
		_, err := loader.fromMCPJSON(mcpconfig.JSON{Servers: map[string]mcpconfig.Server{
			"remote-srv": {
				Type:   "http",
				Remote: &mcpconfig.Remote{URL: "://bad url"},
				Tools:  []string{"tool1"},
				Auth:   &oidcconfig.ConfigEntry{Audience: "aud-remote"},
			},
		}})

		if err == nil {
			t.Fatal("expected invalid remote MCP server URL error")
		}
		if !errors.Is(err, ErrInvalidURL) {
			t.Fatalf("expected ErrInvalidURL, got %v", err)
		}
		if !strings.Contains(err.Error(), "remote-srv") {
			t.Fatalf("expected error to mention server name, got %v", err)
		}
	})

	t.Run("invalid auth validation errors use auth path prefix", func(t *testing.T) {
		_, err := loader.fromMCPJSON(mcpconfig.JSON{Servers: map[string]mcpconfig.Server{
			"remote-srv": {
				Type:   "http",
				Remote: &mcpconfig.Remote{URL: "https://mcp.example.com"},
				Tools:  []string{"tool1"},
				Auth:   &oidcconfig.ConfigEntry{Audience: "aud-remote", RedirectPort: -1},
			},
		}})

		require.Error(t, err)
		assert.Contains(t, err.Error(), "auth.redirectPort")
	})
}

// mcpEnabledEmptyResponse returns a mock that reports MCP enabled with no servers.
func mcpEnabledEmptyResponse() func(context.Context, *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
	return func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdv1.MCPConfigurationForRepositoryResponse{
			IsMcpEnabled:         true,
			McpConfigurationJson: "",
		}, nil
	}
}

// newNoopTwirpClient creates a NoopClient with the given mock for MCPConfigurationForRepository.
func newNoopTwirpClient(mock func(context.Context, *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error)) *githubtwirp.NoopClient {
	client := githubtwirp.NewNoopClient()
	client.NoopSweagentdAPI.MockMCPConfigurationForRepository = mock
	return client
}

func TestRepoMCPConfig(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	type wantEntry struct {
		audience         string
		scope            string
		resource         string
		clientID         string
		grantType        string
		exchangeURL      string
		baseURL          string
		agentOnlySubject bool
	}

	tests := []struct {
		name            string
		isMcpEnabled    bool
		mcpJSON         string
		twirpErr        error
		wantEnabled     bool
		wantConfigs     map[string]wantEntry
		wantErrContains string
	}{
		{
			name:         "MCP enabled with OIDC servers",
			isMcpEnabled: true,
			mcpJSON: `{
				"mcpServers": {
					"my-server": {
						"type": "http",
						"url": "https://mcp.example.com",
						"tools": ["tool1"],
						"oidc": {"audience": "https://example.com"}
					}
				}
			}`,
			wantEnabled: true,
			wantConfigs: map[string]wantEntry{
				"my-server": {audience: "https://example.com", baseURL: "https://mcp.example.com"},
			},
		},
		{
			name: "MCP disabled",
		},
		{
			name:         "MCP enabled with empty JSON string",
			isMcpEnabled: true,
			wantEnabled:  true,
		},
		{
			name:         "MCP enabled with no OIDC servers",
			isMcpEnabled: true,
			mcpJSON: `{
				"mcpServers": {
					"plain-server": {
						"type": "http",
						"url": "https://mcp.example.com",
						"tools": ["tool1"]
					}
				}
			}`,
			wantEnabled: true,
		},
		{
			name:         "MCP enabled with mixed servers",
			isMcpEnabled: true,
			mcpJSON: `{
				"mcpServers": {
					"oidc-server": {
						"type": "http",
						"url": "https://mcp.example.com",
						"tools": ["t1"],
						"oidc": {
							"audience": "https://api.example.com",
							"scope": "openid",
							"client": "client-123",
							"grantType": "client_credentials"
						}
					},
					"plain-server": {
						"type": "http",
						"url": "https://plain.example.com",
						"tools": ["t2"]
					}
				}
			}`,
			wantEnabled: true,
			wantConfigs: map[string]wantEntry{
				"oidc-server": {
					audience:  "https://api.example.com",
					scope:     "openid",
					clientID:  "client-123",
					grantType: oidcconfig.GrantTypeClientCredentials,
					baseURL:   "https://mcp.example.com",
				},
			},
		},
		{
			name:            "MCP enabled with malformed JSON",
			isMcpEnabled:    true,
			mcpJSON:         `{invalid json`,
			wantErrContains: "failed to parse MCP configuration JSON",
		},
		{
			name:            "twirp API error",
			twirpErr:        assert.AnError,
			wantErrContains: "failed to fetch MCP configuration",
		},
		{
			name:         "MCP enabled with multiple OIDC entries preserving all fields",
			isMcpEnabled: true,
			mcpJSON: `{
				"mcpServers": {
					"server-a": {
						"type": "http",
						"url": "https://a.example.com",
						"tools": ["t1"],
						"oidc": {
							"audience": "aud-a",
							"scope": "scope-a",
							"endpoints": {
								"exchange": "https://exchange-a.example.com/token"
							},
							"agentOnlySubject": true
						}
					},
					"server-b": {
						"type": "http",
						"url": "https://b.example.com",
						"tools": ["t2"],
						"oidc": {
							"audience": "aud-b",
							"resource": "https://resource-b.example.com",
							"grantType": "urn:ietf:params:oauth:grant-type:token-exchange"
						}
					}
				}
			}`,
			wantEnabled: true,
			wantConfigs: map[string]wantEntry{
				"server-a": {
					audience:         "aud-a",
					scope:            "scope-a",
					exchangeURL:      "https://exchange-a.example.com/token",
					baseURL:          "https://a.example.com",
					agentOnlySubject: true,
				},
				"server-b": {
					audience:  "aud-b",
					resource:  "https://resource-b.example.com",
					grantType: oidcconfig.GrantTypeTokenExchange,
					baseURL:   "https://b.example.com",
				},
			},
		},
		{
			name:         "MCP enabled with nil servers map in JSON",
			isMcpEnabled: true,
			mcpJSON:      `{}`,
			wantEnabled:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			twirpMock := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
				if tt.twirpErr != nil {
					return nil, tt.twirpErr
				}
				return &sweagentdv1.MCPConfigurationForRepositoryResponse{
					IsMcpEnabled:         tt.isMcpEnabled,
					McpConfigurationJson: tt.mcpJSON,
				}, nil
			}

			loader := NewConfigLoader(
				nil,
				spokestest.NewClient(t),
				newNoopTwirpClient(twirpMock),
				obsv,
				nil,
			)

			rawCfg, enabled, err := loader.loadRepoMCPConfigRaw(ctx, 123, 456)

			if tt.wantErrContains != "" {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.wantErrContains)
				assert.False(t, enabled)
				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.wantEnabled, enabled)

			if !enabled || len(tt.wantConfigs) == 0 {
				return
			}

			configs, err := loader.fromMCPJSON(rawCfg)
			require.NoError(t, err)
			require.Len(t, configs, len(tt.wantConfigs))

			for serverName, want := range tt.wantConfigs {
				entry, ok := configs[serverName]
				require.True(t, ok, "expected server %s not found", serverName)
				assert.Equal(t, serverName, entry.ServerName())
				assert.Equal(t, want.audience, entry.Audience)
				assert.Equal(t, want.scope, entry.Scope)
				assert.Equal(t, want.resource, entry.Resource)
				assert.Equal(t, want.clientID, entry.ClientID)
				assert.Equal(t, want.grantType, entry.GrantType)
				assert.Equal(t, want.exchangeURL, entry.Endpoints.Exchange)
				assert.Equal(t, want.baseURL, entry.Endpoints.Base)
				assert.Equal(t, want.agentOnlySubject, entry.AgentOnlySubject)
			}
		})
	}
}

func TestFromSettingsJSON(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("valid settings.json with single OIDC entry", func(t *testing.T) {
		settingsJSON := `{
			"oidcConfig": [
				{
					"secretSuffix": "MY_SECRET",
					"audience": "https://example.com"
				}
			]
		}`
		spkClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(123, platformConfigPath, []byte(settingsJSON)),
		)

		loader := NewConfigLoader(
			nil,
			spkClient,
			githubtwirp.NewNoopClient(),
			obsv,
			nil,
		)

		cfg, err := loader.loadFromSettingsJSON(ctx, 123)
		require.NoError(t, err)
		require.NotNil(t, cfg)
		require.Len(t, cfg.OIDCConfig, 1)
		assert.Equal(t, "MY_SECRET", cfg.OIDCConfig[0].SecretSuffix)
		assert.Equal(t, "https://example.com", cfg.OIDCConfig[0].Audience)
	})

	t.Run("valid settings.json with multiple OIDC entries", func(t *testing.T) {
		settingsJSON := `{
			"oidcConfig": [
				{
					"secretSuffix": "TOKEN_A",
					"audience": "https://a.example.com",
					"scope": "read"
				},
				{
					"secretSuffix": "TOKEN_B",
					"audience": "https://b.example.com",
					"grantType": "client_credentials",
					"client": "client-id-b"
				}
			]
		}`
		spkClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(200, platformConfigPath, []byte(settingsJSON)),
		)

		loader := NewConfigLoader(
			nil,
			spkClient,
			githubtwirp.NewNoopClient(),
			obsv,
			nil,
		)

		cfg, err := loader.loadFromSettingsJSON(ctx, 200)
		require.NoError(t, err)
		require.NotNil(t, cfg)
		require.Len(t, cfg.OIDCConfig, 2)

		assert.Equal(t, "TOKEN_A", cfg.OIDCConfig[0].SecretSuffix)
		assert.Equal(t, "https://a.example.com", cfg.OIDCConfig[0].Audience)
		assert.Equal(t, "read", cfg.OIDCConfig[0].Scope)

		assert.Equal(t, "TOKEN_B", cfg.OIDCConfig[1].SecretSuffix)
		assert.Equal(t, "https://b.example.com", cfg.OIDCConfig[1].Audience)
		assert.Equal(t, oidcconfig.GrantTypeClientCredentials, cfg.OIDCConfig[1].GrantType)
		assert.Equal(t, "client-id-b", cfg.OIDCConfig[1].ClientID)
	})

	t.Run("settings.json not found returns empty config", func(t *testing.T) {
		spkClient := spokestest.NewClient(t) // no blobs configured

		loader := NewConfigLoader(
			nil,
			spkClient,
			githubtwirp.NewNoopClient(),
			obsv,
			nil,
		)

		cfg, err := loader.loadFromSettingsJSON(ctx, 999)
		require.NoError(t, err)
		require.NotNil(t, cfg)
		assert.Empty(t, cfg.OIDCConfig)
	})

	t.Run("spokes returns nil data", func(t *testing.T) {
		spkClient := spokestest.NewClient(t,
			spokestest.WithMockReadBlob(func(_ context.Context, _ uint64, _ string) ([]byte, string, error) {
				return nil, "", nil
			}),
		)

		loader := NewConfigLoader(
			nil,
			spkClient,
			githubtwirp.NewNoopClient(),
			obsv,
			nil,
		)

		cfg, err := loader.loadFromSettingsJSON(ctx, 123)
		require.NoError(t, err)
		require.NotNil(t, cfg)
		assert.Empty(t, cfg.OIDCConfig)
	})

	t.Run("invalid JSON returns empty config with error", func(t *testing.T) {
		spkClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(123, platformConfigPath, []byte(`{not valid json`)),
		)

		loader := NewConfigLoader(
			nil,
			spkClient,
			githubtwirp.NewNoopClient(),
			obsv,
			nil,
		)

		cfg, err := loader.loadFromSettingsJSON(ctx, 123)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to parse OIDC config from settings.json")
		require.NotNil(t, cfg)
		assert.Empty(t, cfg.OIDCConfig)
	})

	t.Run("invalid config missing secretSuffix returns empty config with error", func(t *testing.T) {
		settingsJSON := `{
			"oidcConfig": [
				{
					"audience": "https://example.com"
				}
			]
		}`
		spkClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(123, platformConfigPath, []byte(settingsJSON)),
		)

		loader := NewConfigLoader(
			nil,
			spkClient,
			githubtwirp.NewNoopClient(),
			obsv,
			nil,
		)

		cfg, err := loader.loadFromSettingsJSON(ctx, 123)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to parse OIDC config from settings.json")
		require.NotNil(t, cfg)
		assert.Empty(t, cfg.OIDCConfig)
	})

	t.Run("spokes non-NotFound error propagates", func(t *testing.T) {
		spkClient := spokestest.NewClient(t,
			spokestest.WithMockReadBlob(func(_ context.Context, _ uint64, _ string) ([]byte, string, error) {
				return nil, "", assert.AnError
			}),
		)

		loader := NewConfigLoader(
			nil,
			spkClient,
			githubtwirp.NewNoopClient(),
			obsv,
			nil,
		)

		cfg, err := loader.loadFromSettingsJSON(ctx, 123)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to read settings.json")
		assert.Nil(t, cfg)
	})

	t.Run("valid settings.json preserves all fields", func(t *testing.T) {
		settingsJSON := `{
			"oidcConfig": [
				{
					"secretSuffix": "FULL",
					"audience": "https://api.example.com",
					"scope": "openid profile",
					"resource": "https://resource.example.com",
					"client": "client-123",
					"grantType": "client_credentials",
					"endpoints": {
						"exchange": "https://exchange.example.com/token",
						"revoke": "https://revoke.example.com/revoke"
					},
					"agentOnlySubject": true
				}
			]
		}`
		spkClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(123, platformConfigPath, []byte(settingsJSON)),
		)

		loader := NewConfigLoader(
			nil,
			spkClient,
			githubtwirp.NewNoopClient(),
			obsv,
			nil,
		)

		cfg, err := loader.loadFromSettingsJSON(ctx, 123)
		require.NoError(t, err)
		require.NotNil(t, cfg)
		require.Len(t, cfg.OIDCConfig, 1)

		entry := cfg.OIDCConfig[0]
		assert.Equal(t, "FULL", entry.SecretSuffix)
		assert.Equal(t, "https://api.example.com", entry.Audience)
		assert.Equal(t, "openid profile", entry.Scope)
		assert.Equal(t, "https://resource.example.com", entry.Resource)
		assert.Equal(t, "client-123", entry.ClientID)
		assert.Equal(t, oidcconfig.GrantTypeClientCredentials, entry.GrantType)
		assert.Equal(t, "https://exchange.example.com/token", entry.Endpoints.Exchange)
		assert.Equal(t, "https://revoke.example.com/revoke", entry.Endpoints.Revoke)
		assert.True(t, entry.AgentOnlySubject)
	})
}

func TestLoad(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentOIDCSettingsJSON: true})

	oidcEntry := func(audience string) *oidcconfig.ConfigEntry {
		return &oidcconfig.ConfigEntry{Audience: audience}
	}

	mcpDisabledResponse := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdv1.MCPConfigurationForRepositoryResponse{
			IsMcpEnabled: false,
		}, nil
	}

	mcpRepoResponse := func(json string) func(context.Context, *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
		return func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled:         true,
				McpConfigurationJson: json,
			}, nil
		}
	}

	tests := []struct {
		name            string
		agent           sweagentd.CustomAgent
		spokesOpts      []spokestest.ClientOption
		twirpMock       func(context.Context, *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error)
		repoID          int64
		actorID         int64
		wantAudiences   []string
		wantServerNames map[string]string // audience -> server name
		wantErrContains string
	}{
		{
			name: "nil agent with no repo config",
		},
		{
			name:  "agent without MCP config",
			agent: &mockAgentNoMCP{name: "no-mcp"},
		},
		{
			name: "agent with MCP config only",
			agent: &mockAgent{
				name: "oidc-agent",
				mcpConfig: mcpconfig.JSON{
					Servers: map[string]mcpconfig.Server{
						"agent-server": mcpServer([]string{"tool1"}, oidcEntry("aud-agent")),
					},
				},
			},
			wantAudiences:   []string{"aud-agent"},
			wantServerNames: map[string]string{"aud-agent": "agent-server"},
		},
		{
			name: "agent with multiple OIDC servers",
			agent: &mockAgent{
				name: "multi",
				mcpConfig: mcpconfig.JSON{
					Servers: map[string]mcpconfig.Server{
						"server-a": mcpServer([]string{"t1"}, oidcEntry("aud-a")),
						"server-b": mcpServer([]string{"t2"}, oidcEntry("aud-b")),
					},
				},
			},
			wantAudiences: []string{"aud-a", "aud-b"},
		},
		{
			name: "agent with mixed servers only returns OIDC entries",
			agent: &mockAgent{
				name: "mixed",
				mcpConfig: mcpconfig.JSON{
					Servers: map[string]mcpconfig.Server{
						"oidc-server": mcpServer([]string{"t1"}, oidcEntry("aud-only")),
						"plain":       mcpServer([]string{"t2"}, nil),
					},
				},
			},
			wantAudiences: []string{"aud-only"},
		},
		{
			name: "agent with empty MCP config",
			agent: &mockAgent{
				name:      "empty",
				mcpConfig: mcpconfig.JSON{},
			},
		},
		{
			name: "MCP disabled returns empty even with agent config",
			agent: &mockAgent{
				name: "agent",
				mcpConfig: mcpconfig.JSON{
					Servers: map[string]mcpconfig.Server{
						"agent-server": mcpServer([]string{"t1"}, oidcEntry("aud-agent")),
					},
				},
			},
			twirpMock: mcpDisabledResponse,
		},
		{
			name: "repo MCP config merged with agent MCP config",
			agent: &mockAgent{
				name: "agent",
				mcpConfig: mcpconfig.JSON{
					Servers: map[string]mcpconfig.Server{
						"agent-server": mcpServer([]string{"t1"}, oidcEntry("aud-agent")),
					},
				},
			},
			twirpMock: mcpRepoResponse(`{
				"mcpServers": {
					"repo-server": {
						"type": "http",
						"url": "https://repo.example.com",
						"tools": ["t1"],
						"oidc": {"audience": "aud-repo"}
					}
				}
			}`),
			wantAudiences: []string{"aud-repo", "aud-agent"},
		},
		{
			name: "agent overrides repo MCP config for same server name",
			agent: &mockAgent{
				name: "agent",
				mcpConfig: mcpconfig.JSON{
					Servers: map[string]mcpconfig.Server{
						"shared-server": mcpServer([]string{"t1"}, oidcEntry("aud-agent-override")),
					},
				},
			},
			twirpMock: mcpRepoResponse(`{
				"mcpServers": {
					"shared-server": {
						"type": "http",
						"url": "https://repo.example.com",
						"tools": ["t1"],
						"oidc": {"audience": "aud-repo-original"}
					}
				}
			}`),
			wantAudiences: []string{"aud-agent-override"},
		},
		{
			name: "settings.json config merged with MCP config",
			agent: &mockAgent{
				name: "agent",
				mcpConfig: mcpconfig.JSON{
					Servers: map[string]mcpconfig.Server{
						"agent-server": mcpServer([]string{"t1"}, oidcEntry("aud-agent")),
					},
				},
			},
			spokesOpts: []spokestest.ClientOption{
				spokestest.WithRepoBlob(10, platformConfigPath, []byte(`{
					"oidcConfig": [
						{
							"secretSuffix": "SETTINGS_TOKEN",
							"audience": "aud-settings"
						}
					]
				}`)),
			},
			repoID:        10,
			actorID:       20,
			wantAudiences: []string{"aud-agent", "aud-settings"},
		},
		{
			name: "twirp error propagates from Load",
			twirpMock: func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
				return nil, assert.AnError
			},
			wantErrContains: "failed to get repo (non-file) MCP OIDC config",
		},
		{
			name: "spokes error propagates from Load",
			spokesOpts: []spokestest.ClientOption{
				spokestest.WithMockReadBlob(func(_ context.Context, _ uint64, _ string) ([]byte, string, error) {
					return nil, "", assert.AnError
				}),
			},
			wantErrContains: "failed to load OIDC config from settings.json",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repoID, actorID := tt.repoID, tt.actorID
			if repoID == 0 {
				repoID = 1
			}
			if actorID == 0 {
				actorID = 2
			}

			twirpMock := tt.twirpMock
			if twirpMock == nil {
				twirpMock = mcpEnabledEmptyResponse()
			}

			loader := NewConfigLoader(
				ffClient,
				spokestest.NewClient(t, tt.spokesOpts...),
				newNoopTwirpClient(twirpMock),
				obsv,
				nil,
			)

			entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: repoID, ActorID: actorID, Agent: tt.agent}, nil)

			if tt.wantErrContains != "" {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.wantErrContains)
				assert.Nil(t, entries)
				return
			}

			require.NoError(t, err)
			require.Len(t, entries, len(tt.wantAudiences))

			audiences := map[string]string{}
			for _, e := range entries {
				audiences[e.Audience] = e.ServerName()
			}
			for _, aud := range tt.wantAudiences {
				_, found := audiences[aud]
				assert.True(t, found, "expected audience %s not found", aud)
			}
			for aud, wantServer := range tt.wantServerNames {
				assert.Equal(t, wantServer, audiences[aud], "server name mismatch for audience %s", aud)
			}
		})
	}
}

func TestFromRepoMCPJSONFileRaw(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("file not found returns empty config", func(t *testing.T) {
		loader := NewConfigLoader(
			featureflags.NewNoopClient(nil),
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		rawCfg, err := loader.loadRepoMCPJSONFileRaw(ctx, 1)
		require.NoError(t, err)
		assert.Nil(t, rawCfg.Servers)
	})

	t.Run("local-only returns empty config", func(t *testing.T) {
		loader := NewLocalConfigLoader(featureflags.NewNoopClient(nil), obsv, nil)
		rawCfg, err := loader.loadRepoMCPJSONFileRaw(ctx, 1)
		require.NoError(t, err)
		assert.Nil(t, rawCfg.Servers)
	})

	t.Run("valid mcp.json with OIDC servers", func(t *testing.T) {
		mcpJSON := `{
			"mcpServers": {
				"my-server": {
					"type": "http",
					"url": "https://example.com/mcp",
					"tools": ["tool1"],
					"oidc": {"audience": "aud-from-file"}
				}
			}
		}`
		loader := NewConfigLoader(
			featureflags.NewNoopClient(nil),
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(mcpJSON))),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		rawCfg, err := loader.loadRepoMCPJSONFileRaw(ctx, 1)
		require.NoError(t, err)
		require.Len(t, rawCfg.Servers, 1)

		result, err := loader.fromMCPJSON(rawCfg)
		require.NoError(t, err)
		require.Len(t, result, 1)
		assert.Equal(t, "aud-from-file", result["my-server"].Audience)
	})

	t.Run("mcp.json with no OIDC entries returns empty map", func(t *testing.T) {
		mcpJSON := `{
			"mcpServers": {
				"plain-server": {
					"type": "http",
					"url": "https://example.com/mcp",
					"tools": ["tool1"]
				}
			}
		}`
		loader := NewConfigLoader(
			featureflags.NewNoopClient(nil),
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(mcpJSON))),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		rawCfg, err := loader.loadRepoMCPJSONFileRaw(ctx, 1)
		require.NoError(t, err)

		result, err := loader.fromMCPJSON(rawCfg)
		require.NoError(t, err)
		assert.Empty(t, result)
	})

	t.Run("mcp.json with no tools does not error", func(t *testing.T) {
		mcpJSON := `{
			"mcpServers": {
				"my-server": {
					"type": "http",
					"url": "https://c.example.com",
					"oidc": {"audience": "aud-from-file"}
				}
			}
		}`

		loader := NewConfigLoader(
			featureflags.NewNoopClient(nil),
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(mcpJSON))),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		rawCfg, err := loader.loadRepoMCPJSONFileRaw(ctx, 1)
		require.NoError(t, err)

		result, err := loader.fromMCPJSON(rawCfg)
		require.NoError(t, err)
		require.Len(t, result, 1)
		assert.Contains(t, result, "my-server")
	})

	t.Run("invalid JSON returns error", func(t *testing.T) {
		loader := NewConfigLoader(
			featureflags.NewNoopClient(nil),
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(`not valid json`))),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		_, err := loader.loadRepoMCPJSONFileRaw(ctx, 1)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to unmarshal .mcp.json")
	})

	t.Run("spokes read error returns error", func(t *testing.T) {
		loader := NewConfigLoader(
			featureflags.NewNoopClient(nil),
			spokestest.NewClient(t, spokestest.WithMockReadBlob(func(_ context.Context, _ uint64, _ string) ([]byte, string, error) {
				return nil, "", assert.AnError
			})),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		_, err := loader.loadRepoMCPJSONFileRaw(ctx, 1)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to read .mcp.json")
	})
}

func TestLoad_RepoMCPJSON(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClientDisabled := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentOIDCSettingsJSON: true,
	})
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentOIDCSettingsJSON:       true,
		featureflags.CopilotSWEAgentOIDCUseRepoRootMCPJSON: true,
	})

	t.Run("repo mcp.json is ignored when repo-root MCPJSON flag is disabled", func(t *testing.T) {
		mcpJSON := `{
			"mcpServers": {
				"file-server": {
					"type": "http",
					"url": "https://file.example.com",
					"tools": ["t1"],
					"oidc": {"audience": "aud-file"}
				}
			}
		}`
		loader := NewConfigLoader(
			ffClientDisabled,
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(mcpJSON))),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2}, nil)
		require.NoError(t, err)
		assert.Empty(t, entries)
	})

	t.Run("repo mcp.json OIDC entries are merged", func(t *testing.T) {
		mcpJSON := `{
			"mcpServers": {
				"file-server": {
					"type": "http",
					"url": "https://file.example.com",
					"tools": ["t1"],
					"oidc": {"audience": "aud-file"}
				}
			}
		}`
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(mcpJSON))),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-file", entries[0].Audience)
	})

	t.Run("repo mcp.json overwrites platform MCP server with same name", func(t *testing.T) {
		mcpJSON := `{
			"mcpServers": {
				"shared": {
					"type": "http",
					"url": "https://file.example.com",
					"tools": ["t1"],
					"oidc": {"audience": "aud-file-wins"}
				}
			}
		}`
		platformResp := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: true,
				McpConfigurationJson: `{
					"mcpServers": {
						"shared": {
							"type": "http",
							"url": "https://platform.example.com",
							"tools": ["t1"],
							"oidc": {"audience": "aud-platform-loses"}
						}
					}
				}`,
			}, nil
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(mcpJSON))),
			newNoopTwirpClient(platformResp),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-file-wins", entries[0].Audience)
	})

	t.Run("repo mcp.json error is warn-and-continue", func(t *testing.T) {
		// Platform MCP has a server; repo .mcp.json has a spokes error (via mock)
		// The platform entry should still be returned.
		platformResp := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: true,
				McpConfigurationJson: `{
					"mcpServers": {
						"platform-srv": {
							"type": "http",
							"url": "https://platform.example.com",
							"tools": ["t1"],
							"oidc": {"audience": "aud-platform"}
						}
					}
				}`,
			}, nil
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t, spokestest.WithMockReadBlob(func(_ context.Context, _ uint64, path string) ([]byte, string, error) {
				if path == ".mcp.json" {
					return nil, "", assert.AnError
				}
				return nil, "", nil
			})),
			newNoopTwirpClient(platformResp),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-platform", entries[0].Audience)
	})
}

func TestLoad_PluginMCPConfigs(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentOIDCSettingsJSON: true})

	oidcEntry := func(audience string) *oidcconfig.ConfigEntry {
		return &oidcconfig.ConfigEntry{Audience: audience}
	}

	t.Run("plugin MCP configs merge into results", func(t *testing.T) {
		pluginConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"plugin-srv": mcpServer([]string{"t1"}, oidcEntry("aud-plugin")),
			}},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AdditionalMCPConfigs: pluginConfigs}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-plugin", entries[0].Audience)
	})

	t.Run("multiple plugin configs all contribute entries", func(t *testing.T) {
		pluginConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"plugin-a": mcpServer([]string{"t1"}, oidcEntry("aud-a")),
			}},
			{Servers: map[string]mcpconfig.Server{
				"plugin-b": mcpServer([]string{"t2"}, oidcEntry("aud-b")),
			}},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AdditionalMCPConfigs: pluginConfigs}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 2)
		audiences := map[string]bool{}
		for _, e := range entries {
			audiences[e.Audience] = true
		}
		assert.True(t, audiences["aud-a"])
		assert.True(t, audiences["aud-b"])
	})

	t.Run("plugin config overwrites repo mcp.json server with same name", func(t *testing.T) {
		mcpJSON := `{
			"mcpServers": {
				"shared": {
					"type": "http",
					"url": "https://repo.example.com",
					"tools": ["t1"],
					"oidc": {"audience": "aud-repo-loses"}
				}
			}
		}`
		pluginConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"shared": mcpServer([]string{"t1"}, oidcEntry("aud-plugin-wins")),
			}},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(mcpJSON))),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AdditionalMCPConfigs: pluginConfigs}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-plugin-wins", entries[0].Audience)
	})

	t.Run("agent config overwrites plugin config with same name", func(t *testing.T) {
		pluginConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"shared": mcpServer([]string{"t1"}, oidcEntry("aud-plugin-loses")),
			}},
		}
		agent := &mockAgent{
			name: "test-agent",
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"shared": mcpServer([]string{"t1"}, oidcEntry("aud-agent-wins")),
				},
			},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AdditionalMCPConfigs: pluginConfigs, Agent: agent, AgentFromApp: true}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-agent-wins", entries[0].Audience)
	})

	t.Run("first plugin config applied when same server name specified", func(t *testing.T) {
		pluginConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"shared": mcpServer([]string{"t1"}, oidcEntry("aud-first-wins")),
			}},
			{Servers: map[string]mcpconfig.Server{
				"shared": mcpServer([]string{"t1"}, oidcEntry("aud-second-loses")),
			}},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AdditionalMCPConfigs: pluginConfigs}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-first-wins", entries[0].Audience)
	})

	t.Run("MCP disabled ignores plugin configs and repo mcp.json", func(t *testing.T) {
		mcpDisabled := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: false,
			}, nil
		}
		pluginConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"plugin-srv": mcpServer([]string{"t1"}, oidcEntry("aud-plugin-ignored")),
			}},
		}
		agent := &mockAgent{
			name: "agent",
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"agent-srv": mcpServer([]string{"t1"}, oidcEntry("aud-agent-ignored")),
				},
			},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(`{
				"mcpServers": {
					"file-srv": {"type":"http","url":"https://x.com","tools":["t"],"oidc":{"audience":"aud-file-ignored"}}
				}
			}`))),
			newNoopTwirpClient(mcpDisabled),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AdditionalMCPConfigs: pluginConfigs, Agent: agent, AgentFromApp: true}, nil)
		require.NoError(t, err)
		// settings.json is not present, so only non-MCP config (empty) is returned
		assert.Empty(t, entries)
	})

	t.Run("MCP disabled still returns settings.json config", func(t *testing.T) {
		mcpDisabled := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: false,
			}, nil
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t, spokestest.WithRepoBlob(10, platformConfigPath, []byte(`{
				"oidcConfig": [
					{"secretSuffix": "MY_TOKEN", "audience": "aud-settings"}
				]
			}`))),
			newNoopTwirpClient(mcpDisabled),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 10, ActorID: 2}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-settings", entries[0].Audience)
	})

	t.Run("plugin config with error is skipped and others still merge", func(t *testing.T) {
		// First plugin has valid config, second has a server with invalid OIDC config
		// The second plugin error should be logged and skipped.
		// Note: FromMCPJSON errors come from newMCPConfigEntry which is very permissive,
		// so we use a nil Servers map in the second config to verify it's safely handled.
		pluginConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"good-plugin": mcpServer([]string{"t1"}, oidcEntry("aud-good")),
			}},
			{Servers: nil}, // empty/nil servers is safe, no error
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AdditionalMCPConfigs: pluginConfigs}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "aud-good", entries[0].Audience)
	})

	t.Run("agent from app marks agent MCP entries with agentic app identity", func(t *testing.T) {
		agent := &mockAgent{
			name: "app-agent",
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"my-server": mcpServer([]string{"t1"}, oidcEntry("aud-app-agent")),
				},
			},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, Agent: agent, AgentFromApp: true}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.True(t, entries[0].UseAgenticAppIdentity(), "agent from app should have UseAgenticAppIdentity=true")
	})

	t.Run("standalone agent does not mark MCP entries with agentic app identity", func(t *testing.T) {
		agent := &mockAgent{
			name: "standalone-agent",
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"my-server": mcpServer([]string{"t1"}, oidcEntry("aud-standalone")),
				},
			},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, Agent: agent}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.False(t, entries[0].UseAgenticAppIdentity(), "standalone agent should have UseAgenticAppIdentity=false")
	})

	t.Run("app MCP configs are marked with agentic app identity", func(t *testing.T) {
		appConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"app-server": mcpServer([]string{"t1"}, oidcEntry("aud-app-plugin")),
			}},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AppMCPConfigs: appConfigs}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.True(t, entries[0].UseAgenticAppIdentity(), "app MCP config should have UseAgenticAppIdentity=true")
	})

	t.Run("additional MCP configs are not marked with agentic app identity", func(t *testing.T) {
		pluginConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"repo-server": mcpServer([]string{"t1"}, oidcEntry("aud-repo-plugin")),
			}},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			nil,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AdditionalMCPConfigs: pluginConfigs}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.False(t, entries[0].UseAgenticAppIdentity(), "additional MCP config should have UseAgenticAppIdentity=false")
	})
}

// trackingVariableFetcher returns a VariableFetcher that records every batch of
// variable names it was asked to fetch and resolves them from the provided map.
func trackingVariableFetcher(values map[string]string, calls *[][]string) varfetcher.VariableFetcher {
	return func(_ context.Context, _ sweagentd.AgenticApp, _ int64, names []string) (map[string]string, error) {
		cp := make([]string, len(names))
		copy(cp, names)
		*calls = append(*calls, cp)
		result := make(map[string]string, len(names))
		for _, n := range names {
			if v, ok := values[n]; ok {
				result[n] = v
			}
		}
		return result, nil
	}
}

func TestLoad_VariableResolution(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentOIDCSettingsJSON:       true,
		featureflags.CopilotSWEAgentOIDCUseRepoRootMCPJSON: true,
	})

	oidcEntry := func(audience string) *oidcconfig.ConfigEntry {
		return &oidcconfig.ConfigEntry{Audience: audience}
	}

	t.Run("variables resolved in repo MCP config before processing", func(t *testing.T) {
		var calls [][]string
		fetcher := trackingVariableFetcher(map[string]string{
			"COPILOT_MCP_AUD": "resolved-audience",
		}, &calls)

		repoResp := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: true,
				McpConfigurationJson: `{
					"mcpServers": {
						"repo-srv": {
							"type": "http",
							"url": "https://repo.example.com",
							"tools": ["t1"],
							"oidc": {"audience": "${{ vars.COPILOT_MCP_AUD }}"}
						}
					}
				}`,
			}, nil
		}
		loader := NewConfigLoader(ffClient, spokestest.NewClient(t), newNoopTwirpClient(repoResp), obsv, fetcher)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "resolved-audience", entries[0].Audience)
	})

	t.Run("variables resolved in repo .mcp.json before processing", func(t *testing.T) {
		var calls [][]string
		fetcher := trackingVariableFetcher(map[string]string{
			"COPILOT_MCP_FILE_AUD": "file-resolved",
		}, &calls)

		mcpJSON := `{
			"mcpServers": {
				"file-srv": {
					"type": "http",
					"url": "https://file.example.com",
					"tools": ["t1"],
					"oidc": {"audience": "${COPILOT_MCP_FILE_AUD}"}
				}
			}
		}`
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t, spokestest.WithRepoBlob(1, ".mcp.json", []byte(mcpJSON))),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			fetcher,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "file-resolved", entries[0].Audience)
	})

	t.Run("variables resolved in additional and app MCP configs", func(t *testing.T) {
		var calls [][]string
		fetcher := trackingVariableFetcher(map[string]string{
			"COPILOT_MCP_EXTRA_AUD": "extra-resolved",
			"COPILOT_MCP_APP_AUD":   "app-resolved",
		}, &calls)

		additionalConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"extra-srv": {
					Remote: &mcpconfig.Remote{Type: "http", URL: "https://extra.example.com"},
					Type:   "http",
					Tools:  []string{"t1"},
					Auth:   oidcEntry("$COPILOT_MCP_EXTRA_AUD"),
				},
			}},
		}
		appConfigs := []mcpconfig.JSON{
			{Servers: map[string]mcpconfig.Server{
				"app-srv": {
					Remote: &mcpconfig.Remote{Type: "http", URL: "https://app.example.com"},
					Type:   "http",
					Tools:  []string{"t1"},
					Auth:   oidcEntry("$COPILOT_MCP_APP_AUD"),
				},
			}},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			fetcher,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, AppMCPConfigs: appConfigs, AdditionalMCPConfigs: additionalConfigs}, nil)
		require.NoError(t, err)

		audiences := map[string]bool{}
		for _, e := range entries {
			audiences[e.Audience] = true
		}
		assert.True(t, audiences["extra-resolved"], "additional config variable should be resolved")
		assert.True(t, audiences["app-resolved"], "app config variable should be resolved")
	})

	t.Run("variables resolved in agent MCP config", func(t *testing.T) {
		var calls [][]string
		fetcher := trackingVariableFetcher(map[string]string{
			"COPILOT_MCP_AGENT_AUD": "agent-resolved",
		}, &calls)

		agent := &mockAgent{
			name: "var-agent",
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"agent-srv": {
						Remote: &mcpconfig.Remote{Type: "http", URL: "https://agent.example.com"},
						Type:   "http",
						Tools:  []string{"t1"},
						Auth:   oidcEntry("${{ vars.COPILOT_MCP_AGENT_AUD }}"),
					},
				},
			},
		}
		loader := NewConfigLoader(
			ffClient,
			spokestest.NewClient(t),
			newNoopTwirpClient(mcpEnabledEmptyResponse()),
			obsv,
			fetcher,
		)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, Agent: agent}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "agent-resolved", entries[0].Audience)
	})

	t.Run("variables fall back to inline defaults when missing", func(t *testing.T) {
		var calls [][]string
		fetcher := trackingVariableFetcher(map[string]string{}, &calls)

		repoResp := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: true,
				McpConfigurationJson: `{
					"mcpServers": {
						"repo-srv": {
							"type": "http",
							"url": "https://repo.example.com",
							"tools": ["t1"],
							"oidc": {"audience": "${COPILOT_MCP_AUD:-default-audience}"}
						}
					}
				}`,
			}, nil
		}

		loader := NewConfigLoader(ffClient, spokestest.NewClient(t), newNoopTwirpClient(repoResp), obsv, fetcher)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "default-audience", entries[0].Audience)
		require.Len(t, calls, 1, "fetcher should still be called so fetched values can override defaults")
		assert.Equal(t, []string{"COPILOT_MCP_AUD"}, calls[0])
	})

	t.Run("shared variable fetched once across multiple sources", func(t *testing.T) {
		var calls [][]string
		fetcher := trackingVariableFetcher(map[string]string{
			"COPILOT_MCP_SHARED": "shared-value",
		}, &calls)

		// Repo MCP config and agent both reference the same variable
		repoResp := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: true,
				McpConfigurationJson: `{
					"mcpServers": {
						"repo-srv": {
							"type": "http",
							"url": "https://repo.example.com",
							"tools": ["t1"],
							"oidc": {"audience": "$COPILOT_MCP_SHARED"}
						}
					}
				}`,
			}, nil
		}
		agent := &mockAgent{
			name: "dup-agent",
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"agent-srv": {
						Remote: &mcpconfig.Remote{Type: "http", URL: "https://agent.example.com"},
						Type:   "http",
						Tools:  []string{"t1"},
						Auth:   oidcEntry("$COPILOT_MCP_SHARED"),
					},
				},
			},
		}
		loader := NewConfigLoader(ffClient, spokestest.NewClient(t), newNoopTwirpClient(repoResp), obsv, fetcher)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, Agent: agent}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 2)

		for _, e := range entries {
			assert.Equal(t, "shared-value", e.Audience, "both sources should have the resolved value")
		}
		// The fetcher should have been called exactly once for the initial batch
		// (fetchVariables collects all configs); resolve uses the cache without
		// additional fetches.
		require.Len(t, calls, 1, "variable should be fetched in a single batch call")
		assert.Equal(t, []string{"COPILOT_MCP_SHARED"}, calls[0], "variable should appear only once in the fetch request")
	})

	t.Run("source precedence preserved after variable resolution", func(t *testing.T) {
		var calls [][]string
		fetcher := trackingVariableFetcher(map[string]string{
			"COPILOT_MCP_REPO_AUD":  "repo-resolved",
			"COPILOT_MCP_AGENT_AUD": "agent-resolved",
		}, &calls)

		// Both repo MCP and agent define "shared-server" with different variable references.
		// Agent should win per precedence rules.
		repoResp := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: true,
				McpConfigurationJson: `{
					"mcpServers": {
						"shared-server": {
							"type": "http",
							"url": "https://repo.example.com",
							"tools": ["t1"],
							"oidc": {"audience": "$COPILOT_MCP_REPO_AUD"}
						}
					}
				}`,
			}, nil
		}
		agent := &mockAgent{
			name: "prec-agent",
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"shared-server": {
						Remote: &mcpconfig.Remote{Type: "http", URL: "https://agent.example.com"},
						Type:   "http",
						Tools:  []string{"t1"},
						Auth:   oidcEntry("$COPILOT_MCP_AGENT_AUD"),
					},
				},
			},
		}
		loader := NewConfigLoader(ffClient, spokestest.NewClient(t), newNoopTwirpClient(repoResp), obsv, fetcher)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, Agent: agent}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "agent-resolved", entries[0].Audience, "agent config should override repo config after resolution")
	})

	t.Run("fetcher error propagates from Load", func(t *testing.T) {
		failingFetcher := func(_ context.Context, _ sweagentd.AgenticApp, _ int64, _ []string) (map[string]string, error) {
			return nil, errors.New("fetcher boom")
		}
		repoResp := func(_ context.Context, _ *sweagentdv1.MCPConfigurationForRepositoryRequest) (*sweagentdv1.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdv1.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: true,
				McpConfigurationJson: `{
					"mcpServers": {
						"srv": {
							"type": "http",
							"url": "https://x.com",
							"tools": ["t"],
							"oidc": {"audience": "$COPILOT_MCP_X"}
						}
					}
				}`,
			}, nil
		}
		loader := NewConfigLoader(ffClient, spokestest.NewClient(t), newNoopTwirpClient(repoResp), obsv, failingFetcher)
		_, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2}, nil)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to fetch MCP config variables")
	})

	t.Run("no fetch when configs have no variable references", func(t *testing.T) {
		var calls [][]string
		fetcher := trackingVariableFetcher(map[string]string{}, &calls)

		agent := &mockAgent{
			name: "static-agent",
			mcpConfig: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"static-srv": mcpServer([]string{"t1"}, oidcEntry("literal-audience")),
				},
			},
		}
		loader := NewConfigLoader(ffClient, spokestest.NewClient(t), newNoopTwirpClient(mcpEnabledEmptyResponse()), obsv, fetcher)
		entries, err := loader.Load(ctx, ResolveConfigurationParams{RepoID: 1, ActorID: 2, Agent: agent}, nil)
		require.NoError(t, err)
		require.Len(t, entries, 1)
		assert.Equal(t, "literal-audience", entries[0].Audience)
		assert.Empty(t, calls, "fetcher should not be called when there are no variable references")
	})
}
