package mcpconfig

import (
	"encoding/json"
	"testing"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestServer_UnmarshalJSON(t *testing.T) {
	tests := []struct {
		name     string
		jsonData string
		expected Server
		wantErr  bool
	}{
		{
			name:     "local server without type",
			jsonData: `{"tools":["*"],"command":"uvx","args":["mcp-server-fetch"]}`,
			expected: Server{
				Tools: []string{"*"},
				Type:  "",
				Local: &Local{
					Command: "uvx",
					Args:    []string{"mcp-server-fetch"},
				},
			},
		},
		{
			name:     "local server with type",
			jsonData: `{"tools":["tool1","tool2"],"type":"local","command":"python","args":["-m","mcp-server-time"],"env":{"VAR1":"value1"}}`,
			expected: Server{
				Tools: []string{"tool1", "tool2"},
				Type:  "local",
				Local: &Local{
					Command: "python",
					Args:    []string{"-m", "mcp-server-time"},
					Env:     map[string]string{"VAR1": "value1"},
				},
			},
		},
		{
			name:     "http server",
			jsonData: `{"tools":["*"],"type":"http","url":"https://example.com/mcp","headers":{"Authorization":"Bearer token"}}`,
			expected: Server{
				Tools: []string{"*"},
				Type:  "http",
				Remote: &Remote{
					Type:    "http",
					URL:     "https://example.com/mcp",
					Headers: map[string]string{"Authorization": "Bearer token"},
				},
			},
		},
		{
			name:     "sse server",
			jsonData: `{"tools":["tool1"],"type":"sse","url":"https://example.com/sse"}`,
			expected: Server{
				Tools: []string{"tool1"},
				Type:  "sse",
				Remote: &Remote{
					Type: "sse",
					URL:  "https://example.com/sse",
				},
			},
		},
		{
			name:     "invalid server type",
			jsonData: `{"tools":["*"],"type":"invalid","command":"test"}`,
			wantErr:  true,
		},
		{
			name:     "malformed json",
			jsonData: `{"tools":["*","command":"test"}`,
			wantErr:  true,
		},
		{
			name:     "no tools specified",
			jsonData: `{"type":"local","command":"test"}`,
			wantErr:  false,
			expected: Server{
				Tools: nil,
				Type:  "local",
				Local: &Local{
					Command: "test",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var server Server
			err := json.Unmarshal([]byte(tt.jsonData), &server)

			if tt.wantErr {
				assert.Error(t, err)
				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected.Tools, server.Tools)
			assert.Equal(t, tt.expected.Type, server.Type)

			if tt.expected.Local != nil {
				require.NotNil(t, server.Local)
				assert.Equal(t, tt.expected.Command, server.Command)
				assert.Equal(t, tt.expected.Args, server.Args)
				assert.Equal(t, tt.expected.Env, server.Env)
			} else {
				assert.Nil(t, server.Local)
			}

			if tt.expected.Remote != nil {
				require.NotNil(t, server.Remote)
				assert.Equal(t, tt.expected.URL, server.URL)
				assert.Equal(t, tt.expected.Headers, server.Headers)
			} else {
				assert.Nil(t, server.Remote)
			}
		})
	}
}

func TestServer_MarshalJSON(t *testing.T) {
	tests := []struct {
		name         string
		server       Server
		expectedJSON string
		wantErr      bool
	}{
		{
			name: "local server with env",
			server: Server{
				Tools: []string{"*"},
				Type:  "local",
				Local: &Local{
					Command: "uvx",
					Args:    []string{"mcp-server-fetch"},
					Env:     map[string]string{"VAR1": "value1"},
				},
			},
			expectedJSON: `{"tools":["*"],"type":"local","command":"uvx","args":["mcp-server-fetch"],"env":{"VAR1":"value1"}}`,
		},
		{
			name: "local server without env",
			server: Server{
				Tools: []string{"tool1"},
				Type:  "local",
				Local: &Local{
					Command: "python",
					Args:    []string{"-m", "mcp-server-time"},
				},
			},
			expectedJSON: `{"tools":["tool1"],"type":"local","command":"python","args":["-m","mcp-server-time"]}`,
		},
		{
			name: "http server with headers",
			server: Server{
				Tools: []string{"*"},
				Type:  "http",
				Remote: &Remote{
					Type:    "http",
					URL:     "https://example.com/mcp",
					Headers: map[string]string{"Authorization": "Bearer token"},
				},
			},
			expectedJSON: `{"tools":["*"],"type":"http","url":"https://example.com/mcp","headers":{"Authorization":"Bearer token"}}`,
		},
		{
			name: "sse server without headers",
			server: Server{
				Tools: []string{"tool1"},
				Type:  "sse",
				Remote: &Remote{
					Type: "sse",
					URL:  "https://example.com/sse",
				},
			},
			expectedJSON: `{"tools":["tool1"],"type":"sse","url":"https://example.com/sse"}`,
		},
		{
			name: "server with neither config",
			server: Server{
				Tools: []string{"*"},
				Type:  "local",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			jsonData, err := json.Marshal(tt.server)

			if tt.wantErr {
				assert.Error(t, err)
				return
			}

			require.NoError(t, err)
			assert.JSONEq(t, tt.expectedJSON, string(jsonData))
		})
	}
}

func TestJSON_UnmarshalJSON(t *testing.T) {
	tests := []struct {
		name         string
		jsonData     string
		expectedJSON JSON
		wantErr      bool
	}{
		{
			name:     "complete MCP configuration",
			jsonData: `{"mcpServers":{"fetch":{"tools":["*"],"type":"local","command":"uvx","args":["mcp-server-fetch"]},"time":{"tools":["*"],"command":"python","args":["-m","mcp-server-time"]},"remote":{"tools":["*"],"type":"http","url":"https://example.com/mcp"}}}`,
			expectedJSON: JSON{
				Servers: map[string]Server{
					"fetch": {
						Tools: []string{"*"},
						Type:  "local",
						Local: &Local{
							Command: "uvx",
							Args:    []string{"mcp-server-fetch"},
						},
					},
					"time": {
						Tools: []string{"*"},
						Type:  "",
						Local: &Local{
							Command: "python",
							Args:    []string{"-m", "mcp-server-time"},
						},
					},
					"remote": {
						Tools: []string{"*"},
						Type:  "http",
						Remote: &Remote{
							Type: "http",
							URL:  "https://example.com/mcp",
						},
					},
				},
			},
		},
		{
			name:     "empty MCP configuration",
			jsonData: `{"mcpServers":{}}`,
			expectedJSON: JSON{
				Servers: map[string]Server{},
			},
		},
		{
			name:     "malformed json",
			jsonData: `{"mcpServers":{"fetch":{"tools":["*"`,
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var mcpJSON JSON
			err := json.Unmarshal([]byte(tt.jsonData), &mcpJSON)

			if tt.wantErr {
				assert.Error(t, err)
				return
			}

			require.NoError(t, err)
			assert.Equal(t, len(tt.expectedJSON.Servers), len(mcpJSON.Servers))

			for name, expectedServer := range tt.expectedJSON.Servers {
				actualServer, exists := mcpJSON.Servers[name]
				require.True(t, exists, "Server %s should exist", name)

				assert.Equal(t, expectedServer.Tools, actualServer.Tools)
				assert.Equal(t, expectedServer.Type, actualServer.Type)

				if expectedServer.Local != nil {
					require.NotNil(t, actualServer.Local)
					assert.Equal(t, expectedServer.Command, actualServer.Command)
					assert.Equal(t, expectedServer.Args, actualServer.Args)
				}

				if expectedServer.Remote != nil {
					require.NotNil(t, actualServer.Remote)
					assert.Equal(t, expectedServer.URL, actualServer.URL)
				}
			}
		})
	}
}

func TestJSON_UnmarshalJSON_SetsOIDCServerName(t *testing.T) {
	t.Run("object auth config gets server name", func(t *testing.T) {
		jsonData := `{"mcpServers":{
			"my-api": {
				"tools": ["*"],
				"type": "http",
				"url": "https://example.com/mcp",
				"auth": {"audience": "aud"}
			}
		}}`
		var mcpJSON JSON
		err := json.Unmarshal([]byte(jsonData), &mcpJSON)
		require.NoError(t, err)
		srv := mcpJSON.Servers["my-api"]
		require.NotNil(t, srv.Auth)
		assert.Equal(t, "my-api", srv.Auth.ServerName())
	})

	t.Run("object oidc alias config gets server name", func(t *testing.T) {
		jsonData := `{"mcpServers":{
			"my-api": {
				"tools": ["*"],
				"type": "http",
				"url": "https://example.com/mcp",
				"oidc": {"audience": "aud"}
			}
		}}`
		var mcpJSON JSON
		err := json.Unmarshal([]byte(jsonData), &mcpJSON)
		require.NoError(t, err)
		srv := mcpJSON.Servers["my-api"]
		require.NotNil(t, srv.Auth)
		assert.Equal(t, "my-api", srv.Auth.ServerName())
	})

	t.Run("boolean true auth config gets server name", func(t *testing.T) {
		jsonData := `{"mcpServers":{
			"bool-srv": {
				"tools": ["*"],
				"type": "http",
				"url": "https://example.com/mcp",
				"auth": true
			}
		}}`
		var mcpJSON JSON
		err := json.Unmarshal([]byte(jsonData), &mcpJSON)
		require.NoError(t, err)
		srv := mcpJSON.Servers["bool-srv"]
		require.NotNil(t, srv.Auth)
		assert.Equal(t, "bool-srv", srv.Auth.ServerName())
	})

	t.Run("server without auth has nil OIDC", func(t *testing.T) {
		jsonData := `{"mcpServers":{
			"plain": {"tools": ["*"], "type": "http", "url": "https://example.com/mcp"}
		}}`
		var mcpJSON JSON
		err := json.Unmarshal([]byte(jsonData), &mcpJSON)
		require.NoError(t, err)
		assert.Nil(t, mcpJSON.Servers["plain"].Auth)
	})

	t.Run("auth takes precedence over oidc when both present", func(t *testing.T) {
		jsonData := `{"mcpServers":{
			"my-api": {
				"tools": ["*"],
				"type": "http",
				"url": "https://example.com/mcp",
				"auth": {"audience": "auth-aud"},
				"oidc": {"audience": "oidc-aud"}
			}
		}}`
		var mcpJSON JSON
		err := json.Unmarshal([]byte(jsonData), &mcpJSON)
		require.NoError(t, err)
		srv := mcpJSON.Servers["my-api"]
		require.NotNil(t, srv.Auth)
		assert.Equal(t, "auth-aud", srv.Auth.Audience)
	})
}

func TestJSON_MarshalJSON(t *testing.T) {
	tests := []struct {
		name         string
		mcpJSON      JSON
		expectedJSON string
		wantErr      bool
	}{
		{
			name: "complete MCP configuration",
			mcpJSON: JSON{
				Servers: map[string]Server{
					"fetch": {
						Tools: []string{"*"},
						Type:  "local",
						Local: &Local{
							Command: "uvx",
							Args:    []string{"mcp-server-fetch"},
						},
					},
					"remote": {
						Tools: []string{"*"},
						Type:  "http",
						Remote: &Remote{
							Type: "http",
							URL:  "https://example.com/mcp",
						},
					},
				},
			},
			expectedJSON: `{"mcpServers":{"fetch":{"tools":["*"],"type":"local","command":"uvx","args":["mcp-server-fetch"]},"remote":{"tools":["*"],"type":"http","url":"https://example.com/mcp"}}}`,
		},
		{
			name: "empty MCP configuration",
			mcpJSON: JSON{
				Servers: map[string]Server{},
			},
			expectedJSON: `{"mcpServers":{}}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			jsonData, err := json.Marshal(tt.mcpJSON)

			if tt.wantErr {
				assert.Error(t, err)
				return
			}

			require.NoError(t, err)
			assert.JSONEq(t, tt.expectedJSON, string(jsonData))
		})
	}
}

func TestServer_RoundTripMarshaling(t *testing.T) {
	tests := []struct {
		name   string
		server Server
	}{
		{
			name: "local server",
			server: Server{
				Tools: []string{"*"},
				Type:  "local",
				Local: &Local{
					Command: "uvx",
					Args:    []string{"mcp-server-fetch"},
					Env:     map[string]string{"VAR1": "value1"},
				},
			},
		},
		{
			name: "http server",
			server: Server{
				Tools: []string{"tool1", "tool2"},
				Type:  "http",
				Remote: &Remote{
					Type:    "http",
					URL:     "https://example.com/mcp",
					Headers: map[string]string{"Authorization": "Bearer token"},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Marshal to JSON
			jsonData, err := json.Marshal(tt.server)
			require.NoError(t, err)

			// Unmarshal back to Server
			var unmarshaled Server
			err = json.Unmarshal(jsonData, &unmarshaled)
			require.NoError(t, err)

			// Compare the original and unmarshaled servers
			assert.Equal(t, tt.server.Tools, unmarshaled.Tools)
			assert.Equal(t, tt.server.Type, unmarshaled.Type)

			if tt.server.Local != nil {
				require.NotNil(t, unmarshaled.Local)
				assert.Equal(t, tt.server.Command, unmarshaled.Command)
				assert.Equal(t, tt.server.Args, unmarshaled.Args)
				assert.Equal(t, tt.server.Env, unmarshaled.Env)
			}

			if tt.server.Remote != nil {
				require.NotNil(t, unmarshaled.Remote)
				assert.Equal(t, tt.server.URL, unmarshaled.URL)
				assert.Equal(t, tt.server.Headers, unmarshaled.Headers)
			}
		})
	}
}

func TestGitHubActionsSyntaxNormalization(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "secrets syntax",
			input:    `${{ secrets.API_TOKEN }}`,
			expected: `$API_TOKEN`,
		},
		{
			name:     "vars syntax",
			input:    `${{ vars.CONFIG_VALUE }}`,
			expected: `$CONFIG_VALUE`,
		},
		{
			name:     "mixed with other text",
			input:    `Bearer ${{ secrets.TOKEN }} for ${{ vars.ENV }}`,
			expected: `Bearer $TOKEN for $ENV`,
		},
		{
			name:     "with whitespace",
			input:    `${{  secrets.API_TOKEN  }}`,
			expected: `$API_TOKEN`,
		},
		{
			name:     "no changes needed",
			input:    `$REGULAR_VAR`,
			expected: `$REGULAR_VAR`,
		},
		// Backwards compat syntax since this was incorrect in the spec initially
		{
			name:     "var syntax",
			input:    `${{ var.CONFIG_VALUE }}`,
			expected: `$CONFIG_VALUE`,
		},
		{
			name:     "mixed with other text",
			input:    `Bearer ${{ secrets.TOKEN }} for ${{ var.ENV }}`,
			expected: `Bearer $TOKEN for $ENV`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := normalizeGitHubActionsSyntax(tt.input)
			if result != tt.expected {
				t.Errorf("normalizeGitHubActionsSyntax(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestLocalServerUnmarshalWithGitHubActions(t *testing.T) {
	jsonData := `{
        "command": "${{ secrets.NODE_PATH }}",
        "args": ["--token", "${{ secrets.API_TOKEN }}", "--config", "${{ vars.CONFIG }}"],
        "env": {
            "API_KEY": "${{ secrets.SECRET_KEY }}",
            "ENVIRONMENT": "${{ vars.DEPLOY_ENV }}"
        },
        "tools": ["*"]
    }`

	var server Server
	err := json.Unmarshal([]byte(jsonData), &server)
	if err != nil {
		t.Fatalf("Failed to unmarshal: %v", err)
	}

	if server.Command != "$NODE_PATH" {
		t.Errorf("Expected command to be normalized to $NODE_PATH, got %s", server.Command)
	}

	expectedArgs := []string{"--token", "$API_TOKEN", "--config", "$CONFIG"}
	for i, arg := range server.Args {
		if arg != expectedArgs[i] {
			t.Errorf("Expected arg[%d] to be %s, got %s", i, expectedArgs[i], arg)
		}
	}

	if server.Env["API_KEY"] != "$SECRET_KEY" {
		t.Errorf("Expected env API_KEY to be normalized to $SECRET_KEY, got %s", server.Env["API_KEY"])
	}
}

func TestRemoteServerUnmarshalWithGitHubActions(t *testing.T) {
	jsonData := `{
        "type": "http",
        "url": "${{ secrets.API_BASE_URL }}/mcp/endpoint",
        "headers": {
            "Authorization": "Bearer ${{ secrets.API_TOKEN }}",
            "X-Environment": "${{ vars.DEPLOY_ENV }}",
            "X-Version": "${{ vars.API_VERSION }}"
        },
        "tools": ["*"]
    }`

	var server Server
	err := json.Unmarshal([]byte(jsonData), &server)
	if err != nil {
		t.Fatalf("Failed to unmarshal: %v", err)
	}

	if server.URL != "$API_BASE_URL/mcp/endpoint" {
		t.Errorf("Expected URL to be normalized to $API_BASE_URL/mcp/endpoint, got %s", server.URL)
	}

	expectedHeaders := map[string]string{
		"Authorization": "Bearer $API_TOKEN",
		"X-Environment": "$DEPLOY_ENV",
		"X-Version":     "$API_VERSION",
	}

	for key, expectedValue := range expectedHeaders {
		if actualValue, exists := server.Headers[key]; !exists {
			t.Errorf("Expected header %s to exist", key)
		} else if actualValue != expectedValue {
			t.Errorf("Expected header %s to be %s, got %s", key, expectedValue, actualValue)
		}
	}

	if server.Type != "http" {
		t.Errorf("Expected type to be http, got %s", server.Type)
	}

	if len(server.Tools) != 1 || server.Tools[0] != "*" {
		t.Errorf("Expected tools to be [\"*\"], got %v", server.Tools)
	}
}

func TestExtractServiceProcessedVariableReferences(t *testing.T) {
	t.Run("extracts refs from oidc fields", func(t *testing.T) {
		cfg := JSON{
			Servers: map[string]Server{
				"srv": {
					Remote: &Remote{Type: "http", URL: "https://$COPILOT_MCP_HOST/mcp"},
					Auth: &oidcconfig.ConfigEntry{
						Audience: "${COPILOT_MCP_AUD:-fallback-aud}",
						ClientID: "$COPILOT_MCP_CLIENT_ID",
						Endpoints: oidcconfig.EndpointsConfig{
							Exchange: "${{ vars.COPILOT_MCP_EXCHANGE_URL }}",
							Revoke:   "https://auth.example.com/revoke",
						},
					},
					Tools: []string{"*"},
				},
			},
		}

		refs := ExtractServiceProcessedVariableReferences(cfg)
		assert.ElementsMatch(t, []string{"COPILOT_MCP_AUD", "COPILOT_MCP_CLIENT_ID", "COPILOT_MCP_EXCHANGE_URL", "COPILOT_MCP_HOST"}, refs)
	})

	t.Run("ignores non-service processed fields", func(t *testing.T) {
		cfg := JSON{
			Servers: map[string]Server{
				"srv": {
					Remote: &Remote{
						Type:    "http",
						URL:     "https://example.com/mcp",
						Headers: map[string]string{"Authorization": "Bearer $COPILOT_MCP_TOKEN"},
					},
					Tools: []string{"*"},
				},
				"local": {
					Type: "local",
					Local: &Local{
						Command: "node",
						Args:    []string{"server.js", "--config", "$COPILOT_MCP_CONFIG"},
					},
					Tools: []string{"*"},
				},
			},
		}

		refs := ExtractServiceProcessedVariableReferences(cfg)
		assert.Empty(t, refs)
	})
}

func TestResolveOIDCVariables(t *testing.T) {
	t.Run("resolves only oidc fields", func(t *testing.T) {
		cfg := JSON{
			Servers: map[string]Server{
				"srv": {
					Remote: &Remote{
						Type: "http",
						URL:  "https://$HOST/mcp",
					},
					Auth: &oidcconfig.ConfigEntry{
						Audience: "${COPILOT_MCP_AUD:-default-audience}",
						Endpoints: oidcconfig.EndpointsConfig{
							Exchange: "${COPILOT_MCP_EXCHANGE_URL:-https://default.example.com/token}",
						},
					},
					Tools: []string{"*"},
				},
			},
		}
		vars := map[string]string{
			"HOST":                     "example.com",
			"COPILOT_MCP_AUD":          "my-audience",
			"COPILOT_MCP_EXCHANGE_URL": "https://auth.example.com/token",
		}

		resolved := ResolveServiceProcessedVariables(cfg, vars)
		srv := resolved.Servers["srv"]

		assert.Equal(t, "https://$HOST/mcp", srv.URL)
		require.NotNil(t, srv.Auth)
		assert.Equal(t, "my-audience", srv.Auth.Audience)
		assert.Equal(t, "https://auth.example.com/token", srv.Auth.Endpoints.Exchange)
	})

	t.Run("uses inline default when variable is missing", func(t *testing.T) {
		cfg := JSON{
			Servers: map[string]Server{
				"srv": {
					Remote: &Remote{Type: "http", URL: "https://example.com/mcp"},
					Auth: &oidcconfig.ConfigEntry{
						Audience: "${COPILOT_MCP_AUD:-default-audience}",
						Endpoints: oidcconfig.EndpointsConfig{
							Exchange: "${COPILOT_MCP_EXCHANGE_URL:-https://default.example.com/token}",
							Revoke:   "${COPILOT_MCP_REVOKE_URL}",
						},
					},
					Tools: []string{"*"},
				},
			},
		}

		resolved := ResolveServiceProcessedVariables(cfg, map[string]string{})
		srv := resolved.Servers["srv"]

		require.NotNil(t, srv.Auth)
		assert.Equal(t, "default-audience", srv.Auth.Audience)
		assert.Equal(t, "https://default.example.com/token", srv.Auth.Endpoints.Exchange)
		assert.Equal(t, "${COPILOT_MCP_REVOKE_URL}", srv.Auth.Endpoints.Revoke)
	})

	t.Run("does not mutate original config", func(t *testing.T) {
		original := JSON{
			Servers: map[string]Server{
				"srv": {
					Remote: &Remote{Type: "http", URL: "https://example.com/mcp"},
					Auth: &oidcconfig.ConfigEntry{
						Audience: "$COPILOT_MCP_AUD",
						Endpoints: oidcconfig.EndpointsConfig{
							Exchange: "${COPILOT_MCP_EXCHANGE_URL}",
						},
					},
					Tools: []string{"*"},
				},
			},
		}

		_ = ResolveServiceProcessedVariables(original, map[string]string{"COPILOT_MCP_AUD": "resolved", "COPILOT_MCP_EXCHANGE_URL": "https://auth.example.com/token"})

		require.NotNil(t, original.Servers["srv"].Auth)
		assert.Equal(t, "$COPILOT_MCP_AUD", original.Servers["srv"].Auth.Audience)
		assert.Equal(t, "${COPILOT_MCP_EXCHANGE_URL}", original.Servers["srv"].Auth.Endpoints.Exchange)
	})
}

func TestOIDCConfig(t *testing.T) {
	// -- Unmarshal: object config --

	t.Run("remote server with all fields", func(t *testing.T) {
		jsonData := `{
		"tools": ["*"],
		"type": "http",
		"url": "https://example.com/mcp",
		"auth": {
			"audience": "my-audience",
			"scope": "read:data write:data",
			"resource": "https://api.example.com",
			"client": "custom-client-id",
			"grantType": "client_credentials",
			"endpoints": {
				"exchange": "https://auth.example.com/token",
				"revoke": "https://auth.example.com/revoke",
				"failure": "https://auth.example.com/failure",
				"base": "https://auth.example.com"
			},
			"secretSuffix": "MY_API",
			"agentOnlySubject": true,
			"publicClient": true,
			"redirectPort": 9090
		}
	}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		require.NotNil(t, server.Auth)
		assert.Equal(t, "my-audience", server.Auth.Audience)
		assert.Equal(t, "read:data write:data", server.Auth.Scope)
		assert.Equal(t, "https://api.example.com", server.Auth.Resource)
		assert.Equal(t, "custom-client-id", server.Auth.ClientID)
		assert.Equal(t, "client_credentials", server.Auth.GrantType)
		assert.Equal(t, "https://auth.example.com/token", server.Auth.Endpoints.Exchange)
		assert.Equal(t, "https://auth.example.com/revoke", server.Auth.Endpoints.Revoke)
		assert.Equal(t, "https://auth.example.com/failure", server.Auth.Endpoints.Failure)
		assert.Equal(t, "https://auth.example.com", server.Auth.Endpoints.Base)
		assert.Equal(t, "MY_API", server.Auth.SecretSuffix)
		assert.True(t, server.Auth.AgentOnlySubject)
		assert.True(t, server.Auth.IsPublicClient())
		assert.Equal(t, 9090, server.Auth.RedirectPort)
	})

	t.Run("remote server with minimal config", func(t *testing.T) {
		jsonData := `{
		"tools": ["*"],
		"type": "http",
		"url": "https://example.com/mcp",
		"auth": {
			"audience": "my-audience"
		}
	}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		require.NotNil(t, server.Auth)
		assert.Equal(t, "my-audience", server.Auth.Audience)
		assert.Empty(t, server.Auth.Scope)
		assert.Empty(t, server.Auth.Resource)
		assert.Empty(t, server.Auth.ClientID)
		assert.Empty(t, server.Auth.GrantType)
		assert.Empty(t, server.Auth.Endpoints.Exchange)
		assert.Empty(t, server.Auth.SecretSuffix)
	})

	t.Run("local server with exchange and secret suffix", func(t *testing.T) {
		jsonData := `{
		"tools": ["*"],
		"command": "node",
		"args": ["server.js"],
		"auth": {
			"audience": "my-audience",
			"endpoints": {
				"exchange": "https://example.com/token",
				"revoke": "https://example.com/revoke"
			},
			"secretSuffix": "MY_API"
		}
	}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		require.NotNil(t, server.Auth)
		assert.Equal(t, "my-audience", server.Auth.Audience)
		assert.Equal(t, "MY_API", server.Auth.SecretSuffix)
	})

	t.Run("local server with base endpoint only via oidc alias", func(t *testing.T) {
		jsonData := `{
		"tools": ["*"],
		"command": "node",
		"args": ["server.js"],
		"oidc": {
			"audience": "my-audience",
			"endpoints": {
				"base": "https://auth.example.com"
			},
			"secretSuffix": "MY_API"
		}
	}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		require.NotNil(t, server.Auth)
		assert.Equal(t, "https://auth.example.com", server.Auth.Endpoints.Base)
		assert.Empty(t, server.Auth.Endpoints.Exchange)
	})

	t.Run("no auth field", func(t *testing.T) {
		jsonData := `{"tools": ["*"], "type": "http", "url": "https://example.com/mcp"}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		assert.Nil(t, server.Auth)
	})

	// -- Unmarshal: validation errors --

	t.Run("local server missing exchange and base returns error", func(t *testing.T) {
		jsonData := `{
		"tools": ["*"],
		"command": "node",
		"args": ["server.js"],
		"auth": {
			"audience": "my-audience",
			"endpoints": {
				"revoke": "https://example.com/revoke"
			},
			"secretSuffix": "MY_API"
		}
	}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "auth.endpoints.base or auth.endpoints.exchange is required for local servers")
	})

	t.Run("local server missing secret suffix is valid", func(t *testing.T) {
		jsonData := `{
		"tools": ["*"],
		"command": "node",
		"args": ["server.js"],
		"auth": {
			"audience": "my-audience",
			"endpoints": {
				"exchange": "https://example.com/token",
				"revoke": "https://example.com/revoke"
			}
		}
	}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		assert.Empty(t, server.Auth.SecretSuffix)
	})

	t.Run("invalid endpoint URL returns error", func(t *testing.T) {
		jsonData := `{
		"tools": ["*"],
		"type": "http",
		"url": "https://example.com/mcp",
		"auth": {
			"audience": "my-audience",
			"endpoints": {
				"exchange": "not-a-url"
			}
		}
	}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "auth.endpoints.exchange is invalid")
	})

	t.Run("variable reference in endpoint URL is allowed during unmarshal", func(t *testing.T) {
		// Variable references like $COPILOT_MCP_EXCHANGE_URL should not fail
		// URL validation during unmarshal because resolution happens later.
		tests := []struct {
			name     string
			jsonData string
		}{
			{
				name: "bare variable in exchange",
				jsonData: `{
					"tools": ["*"], "type": "http", "url": "https://example.com/mcp",
					"auth": {"audience": "aud", "endpoints": {"exchange": "$COPILOT_MCP_EXCHANGE_URL"}}
				}`,
			},
			{
				name: "braced variable in exchange",
				jsonData: `{
					"tools": ["*"], "type": "http", "url": "https://example.com/mcp",
					"auth": {"audience": "aud", "endpoints": {"exchange": "${COPILOT_MCP_EXCHANGE_URL}"}}
				}`,
			},
			{
				name: "actions syntax variable in exchange",
				jsonData: `{
					"tools": ["*"], "type": "http", "url": "https://example.com/mcp",
					"auth": {"audience": "aud", "endpoints": {"exchange": "${{ vars.COPILOT_MCP_EXCHANGE_URL }}"}}
				}`,
			},
			{
				name: "variables in all endpoint fields",
				jsonData: `{
					"tools": ["*"], "type": "http", "url": "https://example.com/mcp",
					"auth": {"audience": "aud", "endpoints": {
						"exchange": "$COPILOT_MCP_EXCHANGE_URL",
						"revoke": "${COPILOT_MCP_REVOKE_URL}",
						"failure": "${{ vars.COPILOT_MCP_FAILURE_URL }}",
						"base": "$COPILOT_MCP_BASE_URL"
					}}
				}`,
			},
			{
				name: "variable endpoint on local server with exchange",
				jsonData: `{
					"tools": ["*"], "command": "node", "args": ["server.js"],
					"auth": {"audience": "aud", "endpoints": {"exchange": "$COPILOT_MCP_EXCHANGE_URL"}}
				}`,
			},
			{
				name: "variable endpoint on local server with base",
				jsonData: `{
					"tools": ["*"], "command": "node", "args": ["server.js"],
					"auth": {"audience": "aud", "endpoints": {"base": "$COPILOT_MCP_BASE_URL"}}
				}`,
			},
		}
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				var server Server
				err := json.Unmarshal([]byte(tt.jsonData), &server)
				require.NoError(t, err)
				require.NotNil(t, server.Auth)
			})
		}
	})

	t.Run("static invalid URL still rejected even with variable in other endpoint", func(t *testing.T) {
		jsonData := `{
			"tools": ["*"], "type": "http", "url": "https://example.com/mcp",
			"auth": {"audience": "aud", "endpoints": {
				"exchange": "$COPILOT_MCP_EXCHANGE_URL",
				"revoke": "not-a-url"
			}}
		}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "auth.endpoints.revoke is invalid")
	})

	// -- Unmarshal: boolean shorthand --

	t.Run("auth true on remote http server", func(t *testing.T) {
		jsonData := `{"tools": ["*"], "type": "http", "url": "https://example.com/mcp", "auth": true}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		assert.True(t, server.OIDCEnabled)
		require.NotNil(t, server.Auth)
		assert.Empty(t, server.Auth.Audience)
	})

	t.Run("oidc true alias on remote http server", func(t *testing.T) {
		jsonData := `{"tools": ["*"], "type": "http", "url": "https://example.com/mcp", "oidc": true}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		assert.True(t, server.OIDCEnabled)
		require.NotNil(t, server.Auth)
	})

	t.Run("auth true on remote sse server", func(t *testing.T) {
		jsonData := `{"tools": ["*"], "type": "sse", "url": "https://example.com/sse", "auth": true}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		assert.True(t, server.OIDCEnabled)
		require.NotNil(t, server.Auth)
	})

	t.Run("auth true on local server returns error", func(t *testing.T) {
		jsonData := `{"tools": ["*"], "command": "node", "args": ["server.js"], "auth": true}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "auth: true is only supported for remote server types")

		jsonData = `{"tools": ["*"], "type": "stdio", "command": "node", "args": ["server.js"], "auth": true}`
		err = json.Unmarshal([]byte(jsonData), &server)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "auth: true is only supported for remote server types")
	})

	t.Run("auth false treated as absent", func(t *testing.T) {
		jsonData := `{"tools": ["*"], "type": "http", "url": "https://example.com/mcp", "auth": false}`
		var server Server
		err := json.Unmarshal([]byte(jsonData), &server)
		require.NoError(t, err)
		assert.False(t, server.OIDCEnabled)
		assert.Nil(t, server.Auth)
	})

	// -- Marshal round-trips --

	t.Run("marshal round-trip remote server with object config", func(t *testing.T) {
		server := Server{
			Tools: []string{"*"},
			Type:  "http",
			Remote: &Remote{
				Type:    "http",
				URL:     "https://example.com/mcp",
				Headers: map[string]string{"X-Custom": "val"},
			},
			Auth: &oidcconfig.ConfigEntry{
				Audience:         "my-audience",
				SecretSuffix:     "MY_API",
				Scope:            "read:data",
				Resource:         "https://api.example.com",
				ClientID:         "custom-client",
				GrantType:        oidcconfig.GrantTypeClientCredentials,
				AgentOnlySubject: true,
			},
		}

		jsonData, err := json.Marshal(server)
		require.NoError(t, err)

		var unmarshaled Server
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.NotNil(t, unmarshaled.Auth)
		assert.Equal(t, "my-audience", unmarshaled.Auth.Audience)
		assert.Equal(t, "MY_API", unmarshaled.Auth.SecretSuffix)
		assert.Equal(t, "read:data", unmarshaled.Auth.Scope)
		assert.Equal(t, "https://api.example.com", unmarshaled.Auth.Resource)
		assert.Equal(t, "custom-client", unmarshaled.Auth.ClientID)
		assert.Equal(t, oidcconfig.GrantTypeClientCredentials, unmarshaled.Auth.GrantType)
		assert.True(t, unmarshaled.Auth.AgentOnlySubject)
	})

	t.Run("marshal round-trip local server", func(t *testing.T) {
		server := Server{
			Tools: []string{"*"},
			Type:  "local",
			Local: &Local{
				Command: "node",
				Args:    []string{"server.js"},
			},
			Auth: &oidcconfig.ConfigEntry{
				Audience: "my-audience",
				Endpoints: oidcconfig.EndpointsConfig{
					Exchange: "https://example.com/token",
					Revoke:   "https://example.com/revoke",
				},
				SecretSuffix: "MY_API",
			},
		}

		jsonData, err := json.Marshal(server)
		require.NoError(t, err)

		var unmarshaled Server
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)
		require.NotNil(t, unmarshaled.Auth)
		assert.Equal(t, "my-audience", unmarshaled.Auth.Audience)
		assert.Equal(t, "https://example.com/token", unmarshaled.Auth.Endpoints.Exchange)
		assert.Equal(t, "https://example.com/revoke", unmarshaled.Auth.Endpoints.Revoke)
		assert.Equal(t, "MY_API", unmarshaled.Auth.SecretSuffix)
	})

	t.Run("marshal round-trip auth boolean shorthand", func(t *testing.T) {
		server := Server{
			Tools: []string{"*"},
			Type:  "http",
			Remote: &Remote{
				Type: "http",
				URL:  "https://example.com/mcp",
			},
			Auth:        &oidcconfig.ConfigEntry{},
			OIDCEnabled: true,
		}

		jsonData, err := json.Marshal(server)
		require.NoError(t, err)
		assert.Contains(t, string(jsonData), `"auth":true`)
		assert.Contains(t, string(jsonData), `"oidc":true`)

		var unmarshaled Server
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)
		assert.True(t, unmarshaled.OIDCEnabled)
		require.NotNil(t, unmarshaled.Auth)
	})

	t.Run("marshal emits both auth and oidc keys for object config", func(t *testing.T) {
		server := Server{
			Tools: []string{"*"},
			Type:  "http",
			Remote: &Remote{
				Type: "http",
				URL:  "https://example.com/mcp",
			},
			Auth: &oidcconfig.ConfigEntry{
				Audience: "my-audience",
			},
		}

		jsonData, err := json.Marshal(server)
		require.NoError(t, err)

		var raw map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(jsonData, &raw))
		assert.Contains(t, raw, "auth", "should have auth key")
		assert.Contains(t, raw, "oidc", "should have oidc backward-compat key")
		assert.Equal(t, string(raw["auth"]), string(raw["oidc"]), "auth and oidc values should match")
	})

	t.Run("marshal remote without auth omits field", func(t *testing.T) {
		server := Server{
			Tools: []string{"*"},
			Type:  "http",
			Remote: &Remote{
				Type: "http",
				URL:  "https://example.com/mcp",
			},
		}

		jsonData, err := json.Marshal(server)
		require.NoError(t, err)
		assert.NotContains(t, string(jsonData), `"auth"`)
		assert.NotContains(t, string(jsonData), `"oidc"`)
	})
}
