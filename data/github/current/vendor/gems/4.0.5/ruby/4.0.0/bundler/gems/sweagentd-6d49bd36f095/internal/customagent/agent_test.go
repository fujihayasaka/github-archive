package customagent

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestToDB(t *testing.T) {
	t.Run("converts agent with config to database representation", func(t *testing.T) {
		// Create an agent with a pre-configured config
		metadata := Metadata{
			Name:        "test-agent",
			RepoID:      2,
			RepoOwnerID: 1,
			Version:     "sha-99999999999999999999999999999999999999",
			ConfigError: "All work and no play",
		}

		config := &Config{
			attributes: ConfigAttributes{
				DisplayName:  "Test Agent",
				Description:  "A test agent for unit testing",
				Prompt:       "You are a helpful test agent",
				Tools:        []string{"file_reader", "code_writer"},
				ArgumentHint: "Enter the file path",
				Metadata: map[string]string{
					"owner": "test-owner",
				},
			},
		}

		agent := NewWithConfig(metadata, config)
		result := agent.ToDB()

		expected := customagent.DBRecord{
			Name:        "test-agent",
			RepoOwnerID: 1,
			RepoID:      2,
			DisplayName: "Test Agent",
			Description: "A test agent for unit testing",
			Tools:       []string{"file_reader", "code_writer"},
			Version:     "sha-99999999999999999999999999999999999999",
			ConfigError: "All work and no play",
			Metadata: map[string]string{
				"owner": "test-owner",
			},
		}

		// Compare each field individually since structs with slices cannot be compared directly
		if result.Name != expected.Name {
			t.Errorf("expected Name %s, got %s", expected.Name, result.Name)
		}
		if result.RepoOwnerID != expected.RepoOwnerID {
			t.Errorf("expected RepoOwnerID %d, got %d", expected.RepoOwnerID, result.RepoOwnerID)
		}
		if result.RepoOwner != expected.RepoOwner {
			t.Errorf("expected RepoOwner %s, got %s", expected.RepoOwner, result.RepoOwner)
		}
		if result.RepoID != expected.RepoID {
			t.Errorf("expected RepoID %d, got %d", expected.RepoID, result.RepoID)
		}
		if result.RepoName != expected.RepoName {
			t.Errorf("expected RepoName %s, got %s", expected.RepoName, result.RepoName)
		}
		if result.DisplayName != expected.DisplayName {
			t.Errorf("expected DisplayName %s, got %s", expected.DisplayName, result.DisplayName)
		}
		if result.Description != expected.Description {
			t.Errorf("expected Description %s, got %s", expected.Description, result.Description)
		}
		if len(result.Tools) != len(expected.Tools) {
			t.Errorf("expected %d tools, got %d", len(expected.Tools), len(result.Tools))
		} else {
			for i, tool := range expected.Tools {
				if result.Tools[i] != tool {
					t.Errorf("expected tool %s at index %d, got %s", tool, i, result.Tools[i])
				}
			}
		}
		if result.Version != expected.Version {
			t.Errorf("expected Version %s, got %s", expected.Version, result.Version)
		}
		if result.ConfigError != expected.ConfigError {
			t.Errorf("expected ConfigError %s, got %s", expected.ConfigError, result.ConfigError)
		}
		if len(result.Metadata) != len(expected.Metadata) {
			t.Errorf("expected %d metadata entries, got %d", len(expected.Metadata), len(result.Metadata))
		}
		for k, v := range expected.Metadata {
			if result.Metadata[k] != v {
				t.Errorf("expected metadata[%s] = %s, got %s", k, v, result.Metadata[k])
			}
		}
	})

	t.Run("converts privileged agent with MCP config to database representation", func(t *testing.T) {
		// Create an agent with a pre-configured config
		metadata := Metadata{
			Name:        "test-agent",
			RepoID:      2,
			RepoOwnerID: 1,
			Version:     "sha-99999999999999999999999999999999999999",
		}

		config := &Config{
			attributes: ConfigAttributes{
				DisplayName: "Test Agent",
				Description: "A test agent for unit testing",
				Prompt:      "You are a helpful test agent",
				Tools:       []string{"file_reader", "code_writer"},
				MCPConfig: mcpconfig.JSON{Servers: map[string]mcpconfig.Server{"test": {
					Type: "local",
					Local: &mcpconfig.Local{
						Command: "foo",
						Args:    []string{"bar"},
						Env:     map[string]string{"VAR1": "value1"},
					},
				}}},
			},
		}

		// First test standard agent which should not return MCP config
		agent := NewWithConfig(metadata, config)
		result := agent.ToDB()
		if len(result.MCPServers) != 0 {
			t.Errorf("expected no MCP servers, got %d", len(result.MCPServers))
		}

		// Next test privileged agent which should return MCP config
		agent2 := &PrivilegedAgent{NewWithConfig(metadata, config)}
		result2 := agent2.ToDB()
		if len(result2.MCPServers) != 1 {
			t.Errorf("expected 1 MCP server, got %d", len(result2.MCPServers))
		}
	})

	t.Run("returns error when config cannot be retrieved", func(t *testing.T) {
		ctx := context.Background()

		// Create an agent without config that will try to fetch from repo
		metadata := Metadata{
			Name: "test-agent",
		}

		repo, err := NewRepository(ctx, &mockRepoProvider{}, spokestest.NewClient(t), observability.NewNoopExporters(), metadata.RepoOwner, metadata.RepoName, Directory)
		if err != nil {
			t.Fatalf("failed to create repository: %v", err)
		}

		_, err = FromRepo(context.Background(), metadata, repo, true)
		if err == nil {
			t.Fatal("expected error when creating agent from repo with no config, got nil")
		}
	})
}

func TestBuildServerFromFlat(t *testing.T) {
	tests := []struct {
		name     string
		flat     customagent.MCPServer
		expected mcpconfig.Server
	}{
		{
			name: "local server with empty type",
			flat: customagent.MCPServer{
				Name:    "fetch",
				Type:    "",
				Tools:   []string{"*"},
				Command: "uvx",
				Args:    []string{"mcp-server-fetch"},
				Env:     map[string]string{"VAR1": "value1"},
			},
			expected: mcpconfig.Server{
				Type:  "",
				Tools: []string{"*"},
				Local: &mcpconfig.Local{
					Command: "uvx",
					Args:    []string{"mcp-server-fetch"},
					Env:     map[string]string{"VAR1": "value1"},
				},
			},
		},
		{
			name: "local server with explicit type",
			flat: customagent.MCPServer{
				Name:    "time",
				Type:    "local",
				Tools:   []string{"get_time", "set_timer"},
				Command: "python",
				Args:    []string{"-m", "mcp-server-time"},
			},
			expected: mcpconfig.Server{
				Type:  "local",
				Tools: []string{"get_time", "set_timer"},
				Local: &mcpconfig.Local{
					Command: "python",
					Args:    []string{"-m", "mcp-server-time"},
				},
			},
		},
		{
			name: "http server",
			flat: customagent.MCPServer{
				Name:    "remote",
				Type:    "http",
				Tools:   []string{"*"},
				URL:     "https://example.com/mcp",
				Headers: map[string]string{"Authorization": "Bearer token"},
			},
			expected: mcpconfig.Server{
				Type:  "http",
				Tools: []string{"*"},
				Remote: &mcpconfig.Remote{
					URL:     "https://example.com/mcp",
					Headers: map[string]string{"Authorization": "Bearer token"},
				},
			},
		},
		{
			name: "sse server",
			flat: customagent.MCPServer{
				Name:  "sse",
				Type:  "sse",
				Tools: []string{"tool1"},
				URL:   "https://example.com/sse",
			},
			expected: mcpconfig.Server{
				Type:  "sse",
				Tools: []string{"tool1"},
				Remote: &mcpconfig.Remote{
					URL: "https://example.com/sse",
				},
			},
		},
		{
			name: "invalid server type",
			flat: customagent.MCPServer{
				Name:  "invalid",
				Type:  "invalid",
				Tools: []string{"*"},
			},
			expected: mcpconfig.Server{
				Type:  "invalid",
				Tools: []string{"*"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := makeMCPServer(tt.flat)

			assert.Equal(t, tt.expected.Type, result.Type)
			assert.Equal(t, tt.expected.Tools, result.Tools)

			if tt.expected.Local != nil {
				require.NotNil(t, result.Local)
				assert.Equal(t, tt.expected.Command, result.Command)
				assert.Equal(t, tt.expected.Args, result.Args)
				assert.Equal(t, tt.expected.Env, result.Env)
			} else {
				assert.Nil(t, result.Local)
			}

			if tt.expected.Remote != nil {
				require.NotNil(t, result.Remote)
				assert.Equal(t, tt.expected.URL, result.URL)
				assert.Equal(t, tt.expected.Headers, result.Headers)
			} else {
				assert.Nil(t, result.Remote)
			}
		})
	}
}
