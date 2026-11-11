package mcpconfig

import (
	"encoding/json"
	"testing"

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
