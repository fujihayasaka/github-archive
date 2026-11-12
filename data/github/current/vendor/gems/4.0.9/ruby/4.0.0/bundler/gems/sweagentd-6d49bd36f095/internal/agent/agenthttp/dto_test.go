package agenthttp

import (
	"encoding/json"
	"testing"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCustomAgentDTO_MarshalJSON_DualAuthOIDC(t *testing.T) {
	t.Run("emits both auth and oidc keys for object config", func(t *testing.T) {
		dto := customAgentDTO{
			Name: "test-agent",
			MCPServers: map[string]mcpconfig.Server{
				"my-server": {
					Tools: []string{"*"},
					Type:  "http",
					Remote: &mcpconfig.Remote{
						Type: "http",
						URL:  "https://example.com/mcp",
					},
					Auth: &oidcconfig.ConfigEntry{
						Audience: "my-audience",
					},
				},
			},
		}

		data, err := json.Marshal(dto)
		require.NoError(t, err)

		var raw map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(data, &raw))

		var servers map[string]map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(raw["mcp_servers"], &servers))

		srv := servers["my-server"]
		assert.Contains(t, srv, "auth", "should have auth key")
		assert.Contains(t, srv, "oidc", "should have oidc key")
		assert.Equal(t, string(srv["auth"]), string(srv["oidc"]), "auth and oidc should have the same value")

		var authEntry oidcconfig.ConfigEntry
		require.NoError(t, json.Unmarshal(srv["auth"], &authEntry))
		assert.Equal(t, "my-audience", authEntry.Audience)
	})

	t.Run("emits both auth and oidc keys for boolean shorthand", func(t *testing.T) {
		dto := customAgentDTO{
			Name: "test-agent",
			MCPServers: map[string]mcpconfig.Server{
				"my-server": {
					Tools: []string{"*"},
					Type:  "http",
					Remote: &mcpconfig.Remote{
						Type: "http",
						URL:  "https://example.com/mcp",
					},
					Auth:        &oidcconfig.ConfigEntry{},
					OIDCEnabled: true,
				},
			},
		}

		data, err := json.Marshal(dto)
		require.NoError(t, err)

		var raw map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(data, &raw))

		var servers map[string]map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(raw["mcp_servers"], &servers))

		srv := servers["my-server"]
		assert.Equal(t, "true", string(srv["auth"]))
		assert.Equal(t, "true", string(srv["oidc"]))
	})

	t.Run("no auth key when auth is nil", func(t *testing.T) {
		dto := customAgentDTO{
			Name: "test-agent",
			MCPServers: map[string]mcpconfig.Server{
				"my-server": {
					Tools: []string{"*"},
					Type:  "http",
					Remote: &mcpconfig.Remote{
						Type: "http",
						URL:  "https://example.com/mcp",
					},
				},
			},
		}

		data, err := json.Marshal(dto)
		require.NoError(t, err)

		var raw map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(data, &raw))

		var servers map[string]map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(raw["mcp_servers"], &servers))

		srv := servers["my-server"]
		assert.NotContains(t, srv, "auth")
		assert.NotContains(t, srv, "oidc")
	})

	t.Run("omits mcp_servers when empty", func(t *testing.T) {
		dto := customAgentDTO{
			Name: "test-agent",
		}

		data, err := json.Marshal(dto)
		require.NoError(t, err)

		var raw map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(data, &raw))

		_, hasMCP := raw["mcp_servers"]
		assert.False(t, hasMCP, "mcp_servers should be omitted when empty")
	})

	t.Run("preserves other fields alongside mcp_servers", func(t *testing.T) {
		dto := customAgentDTO{
			Name:        "test-agent",
			DisplayName: "Test Agent",
			Description: "A test agent",
			Tools:       []string{"tool1"},
			MCPServers: map[string]mcpconfig.Server{
				"srv": {
					Tools: []string{"*"},
					Type:  "http",
					Remote: &mcpconfig.Remote{
						Type: "http",
						URL:  "https://example.com",
					},
				},
			},
		}

		data, err := json.Marshal(dto)
		require.NoError(t, err)

		var raw map[string]json.RawMessage
		require.NoError(t, json.Unmarshal(data, &raw))

		assert.Contains(t, raw, "name")
		assert.Contains(t, raw, "display_name")
		assert.Contains(t, raw, "description")
		assert.Contains(t, raw, "tools")
		assert.Contains(t, raw, "mcp_servers")
	})
}
