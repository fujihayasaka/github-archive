package mcp

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdAPITwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const MCPConfigFixture = `{"mcpServers":{"fetch":{"tools":["*"],"type":"local","command":"uvx","args":["mcp-server-fetch"]},"time":{"tools":["*"],"command":"python","args":["-m","mcp-server-time"]}}}`
const emptyConfigFixture = `{"mcpServers":{}}`

func TestConfigure(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name                  string
		mcpClientResponse     *sweagentdAPITwirp.MCPConfigurationForRepositoryResponse
		mcpClientError        error
		expectedEnabled       bool
		expectedValidConfig   bool
		expectedConfig        string
		expectedError         bool
		expectedErrorContains string
		customAgent           sweagentd.CustomAgent
	}{
		{
			name: "MCP disabled",
			mcpClientResponse: &sweagentdAPITwirp.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled:         false,
				McpConfigurationJson: MCPConfigFixture,
			},
			expectedEnabled:     false,
			expectedValidConfig: true,
			expectedError:       false,
			expectedConfig:      MCPConfigFixture,
		},
		{
			name: "MCP enabled",
			mcpClientResponse: &sweagentdAPITwirp.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled:         true,
				McpConfigurationJson: MCPConfigFixture,
			},
			expectedEnabled:     true,
			expectedValidConfig: true,
			expectedError:       false,
			expectedConfig:      MCPConfigFixture,
		},
		{
			name:                  "API error",
			mcpClientError:        errors.New("server error"),
			expectedEnabled:       false,
			expectedValidConfig:   false,
			expectedError:         true,
			expectedErrorContains: "failed to get MCP configuration from dotcom",
		},
		{
			name: "empty config string",
			mcpClientResponse: &sweagentdAPITwirp.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled:         true,
				McpConfigurationJson: "",
			},
			expectedEnabled:     true,
			expectedValidConfig: true,
			expectedError:       false,
			expectedConfig:      emptyConfigFixture,
		},
		{
			name: "oversized config",
			mcpClientResponse: &sweagentdAPITwirp.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled: true,
				// Create an oversized config by repeating a large tool name
				McpConfigurationJson: func() string {
					largeToolName := strings.Repeat("x", 15000)
					//nolint:gocritic // sprintfQuotedString: intentionally using %s for JSON string construction
					return fmt.Sprintf(`{"mcpServers":{"huge_server":{"type":"local","command":"test","args":["arg"],"tools":["%s"]}}}`, largeToolName)
				}(),
			},
			expectedEnabled:       true,
			expectedValidConfig:   false,
			expectedError:         true,
			expectedErrorContains: "failed to encode MCP configuration",
		},
		{
			name: "invalid JSON",
			mcpClientResponse: &sweagentdAPITwirp.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled:         true,
				McpConfigurationJson: `{"invalid": json}`,
			},
			expectedEnabled:       false,
			expectedValidConfig:   false,
			expectedError:         true,
			expectedErrorContains: "failed to parse MCP configuration",
		},
		{
			name: "merges custom agent MCP servers with repository config",
			mcpClientResponse: &sweagentdAPITwirp.MCPConfigurationForRepositoryResponse{
				IsMcpEnabled:         true,
				McpConfigurationJson: `{"mcpServers":{"fetch":{"tools":["*"],"type":"local","command":"uvx","args":["mcp-server-fetch"]}}}`,
			},
			customAgent: &customagent.PrivilegedAgent{
				Agent: customagent.NewWithConfig(customagent.Metadata{
					Name:      "test-customagent",
					RepoOwner: "repo owner",
					RepoName:  "repo name",
				}, customagent.NewConfigWithAttributes(customagent.ConfigAttributes{
					Tools: []string{},
					MCPConfig: mcpconfig.JSON{
						Servers: map[string]mcpconfig.Server{
							"org-server": {
								Tools: []string{"tool1", "tool2"},
								Local: &mcpconfig.Local{
									Command: "test-command",
									Args:    []string{"arg1"},
								},
							},
						},
					},
				})),
			},
			expectedEnabled:     true,
			expectedValidConfig: true,
			expectedError:       false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ghTwirp := &githubtwirp.NoopClient{
				NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
					MockMCPConfigurationForRepository: func(ctx context.Context, req *sweagentdAPITwirp.MCPConfigurationForRepositoryRequest) (*sweagentdAPITwirp.MCPConfigurationForRepositoryResponse, error) {
						if tt.mcpClientError != nil {
							return nil, tt.mcpClientError
						}

						return &sweagentdAPITwirp.MCPConfigurationForRepositoryResponse{
							McpConfigurationJson: tt.mcpClientResponse.McpConfigurationJson,
							IsMcpEnabled:         tt.mcpClientResponse.GetIsMcpEnabled(),
						}, nil
					},
				},
			}

			agent := tt.customAgent
			if agent == nil {
				agent = customagent.NewWithConfig(customagent.Metadata{
					Name:      "test-customagent",
					RepoOwner: "repo owner",
					RepoName:  "repo name",
				}, customagent.NewConfigWithAttributes(customagent.ConfigAttributes{
					Tools: []string{},
				}))
			}

			params := ConfigureParams{
				RepositoryID: 456,
				UserID:       123,
				CustomAgent:  agent,
				GHTwirp:      ghTwirp,
			}

			result, err := Configure(ctx, params)

			if tt.expectedError {
				assert.Error(t, err)
				if tt.expectedErrorContains != "" {
					assert.Contains(t, err.Error(), tt.expectedErrorContains)
				}
				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expectedEnabled, result.Enabled)

			if tt.expectedEnabled {
				decoded, decodeErr := base64.StdEncoding.DecodeString(result.Encoded)
				require.NoError(t, decodeErr)

				if tt.expectedValidConfig && tt.expectedConfig != "" {
					require.Equal(t, tt.expectedConfig, string(decoded))
				}

				var decodedConfig mcpconfig.JSON
				unmarshalErr := json.Unmarshal(decoded, &decodedConfig)
				require.NoError(t, unmarshalErr)
				assert.NotNil(t, decodedConfig.Servers)

				// For the custom agent merge test, verify both servers are present
				if tt.name == "merges custom agent MCP servers with repository config" {
					assert.Contains(t, decodedConfig.Servers, "fetch", "should contain fetch server from repository config")
					assert.Contains(t, decodedConfig.Servers, "org-server", "should contain org-server from custom agent")
					assert.Len(t, decodedConfig.Servers, 2, "should have exactly 2 servers after merge")
				}
			}
		})
	}
}

func TestEncodeConfig(t *testing.T) {
	tests := []struct {
		name          string
		config        mcpconfig.JSON
		expectedError bool
		errorContains string
	}{
		{
			name: "valid config",
			config: func() mcpconfig.JSON {
				cfg, _ := parseConfig(`{"mcpServers":{"fetch":{"type":"local","command":"uvx","args":["mcp-server-fetch"],"tools":["*"]}}}`)
				return cfg
			}(),
			expectedError: false,
		},
		{
			name: "empty config",
			config: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{},
			},
			expectedError: false,
		},
		{
			name: "oversized config",
			config: func() mcpconfig.JSON {
				largeToolName := strings.Repeat("x", 15000)
				//nolint:gocritic // sprintfQuotedString: intentionally using %s for JSON string construction
				jsonStr := fmt.Sprintf(`{"mcpServers":{"huge_server":{"type":"local","command":"test","args":["arg"],"tools":["%s"]}}}`, largeToolName)
				cfg, _ := parseConfig(jsonStr)
				return cfg
			}(),
			expectedError: true,
			errorContains: "exceeds maximum",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			encoded, err := encodeConfig(tt.config)

			if tt.expectedError {
				assert.Error(t, err)
				if tt.errorContains != "" {
					assert.Contains(t, err.Error(), tt.errorContains)
				}
				return
			}

			require.NoError(t, err)
			assert.NotEmpty(t, encoded)

			decoded, err := base64.StdEncoding.DecodeString(encoded)
			require.NoError(t, err)

			var decodedConfig mcpconfig.JSON
			err = json.Unmarshal(decoded, &decodedConfig)
			require.NoError(t, err)
			assert.Equal(t, tt.config, decodedConfig)
		})
	}
}

func TestConfigurationRequest_Validation(t *testing.T) {
	ctx := context.Background()

	ghTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			MockMCPConfigurationForRepository: func(ctx context.Context, req *sweagentdAPITwirp.MCPConfigurationForRepositoryRequest) (*sweagentdAPITwirp.MCPConfigurationForRepositoryResponse, error) {
				assert.Equal(t, uint64(123), req.RepositoryId)
				assert.Equal(t, uint64(456), req.UserId)

				return &sweagentdAPITwirp.MCPConfigurationForRepositoryResponse{
					IsMcpEnabled:         true,
					McpConfigurationJson: MCPConfigFixture,
				}, nil
			},
		},
	}

	agent := customagent.NewWithConfig(customagent.Metadata{
		Name:      "test-customagent",
		RepoOwner: "repo owner",
		RepoName:  "repo name",
	}, customagent.NewConfigWithAttributes(customagent.ConfigAttributes{
		Tools: []string{},
	}))

	params := ConfigureParams{
		RepositoryID: 123,
		UserID:       456,
		GHTwirp:      ghTwirp,
		CustomAgent:  agent,
	}

	result, err := Configure(ctx, params)
	require.NoError(t, err)
	assert.True(t, result.Enabled)
	assert.NotEmpty(t, result.Encoded)
}

func TestParseConfig(t *testing.T) {
	tests := []struct {
		name           string
		configStr      string
		expectedError  bool
		expectedResult mcpconfig.JSON
	}{
		{
			name:      "empty string becomes default",
			configStr: "",
			expectedResult: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{},
			},
		},
		{
			name:      "valid JSON",
			configStr: `{"mcpServers":{"fetch":{"tools":["*"],"command":"hi"}}}`,
			expectedResult: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{
					"fetch": {Tools: []string{"*"}},
				},
			},
		},
		{
			name:          "invalid JSON",
			configStr:     `{"invalid": json}`,
			expectedError: true,
		},
		{
			name:      "missing mcpServers field",
			configStr: `{"otherField": "value"}`,
			expectedResult: mcpconfig.JSON{
				Servers: map[string]mcpconfig.Server{},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := parseConfig(tt.configStr)

			if tt.expectedError {
				assert.Error(t, err)
				return
			}

			require.NoError(t, err)
			assert.NotNil(t, result.Servers)

			if len(tt.expectedResult.Servers) > 0 {
				assert.Equal(t, len(tt.expectedResult.Servers), len(result.Servers))
				for serverName, expectedConfig := range tt.expectedResult.Servers {
					actualConfig, exists := result.Servers[serverName]
					require.True(t, exists, "expected server %s to exist", serverName)
					assert.Equal(t, expectedConfig.Tools, actualConfig.Tools)
				}
			} else {
				assert.Equal(t, tt.expectedResult, result)
			}
		})
	}
}
