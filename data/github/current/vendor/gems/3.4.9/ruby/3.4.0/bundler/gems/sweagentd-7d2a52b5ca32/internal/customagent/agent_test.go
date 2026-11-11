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
			RepoOwner:   "github",
			RepoOwnerID: 1,
			RepoName:    "test-repo",
			Version:     "sha-99999999999999999999999999999999999999",
			ConfigError: "All work and no play",
		}

		config := &Config{
			attributes: ConfigAttributes{
				DisplayName: "Test Agent",
				Description: "A test agent for unit testing",
				Prompt:      "You are a helpful test agent",
				Tools:       []string{"file_reader", "code_writer"},
			},
		}

		agent := NewWithConfig(metadata, config)
		result := agent.ToDB()

		expected := customagent.DBRecord{
			Name:        "test-agent",
			RepoOwnerID: 1,
			RepoOwner:   "github",
			RepoID:      2,
			RepoName:    "test-repo",
			DisplayName: "Test Agent",
			Description: "A test agent for unit testing",
			Prompt:      "You are a helpful test agent",
			Tools:       []string{"file_reader", "code_writer"},
			Version:     "sha-99999999999999999999999999999999999999",
			ConfigError: "All work and no play",
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
		if result.Prompt != expected.Prompt {
			t.Errorf("expected Prompt %s, got %s", expected.Prompt, result.Prompt)
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
	})

	t.Run("converts privileged agent with MCP config to database representation", func(t *testing.T) {
		// Create an agent with a pre-configured config
		metadata := Metadata{
			Name:        "test-agent",
			RepoID:      2,
			RepoOwner:   "github",
			RepoOwnerID: 1,
			RepoName:    "test-repo",
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
			Name:      "test-agent",
			RepoOwner: "github",
			RepoName:  "test-repo",
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

func TestFromDB(t *testing.T) {
	t.Run("converts database representation to agent", func(t *testing.T) {
		db := customagent.DBRecord{
			Name:        "db-agent",
			RepoOwnerID: 1,
			RepoOwner:   "github",
			RepoID:      2,
			RepoName:    "db-repo",
			DisplayName: "Database Agent",
			Description: "An agent from the database",
			Prompt:      "You are a database agent",
			Tools:       []string{"db_reader", "query_writer"},
			ConfigError: "All work and no play",
		}

		agent := FromDB(db)

		if agent.Name() != "db-agent" {
			t.Errorf("expected name 'db-agent', got %s", agent.Name())
		}

		if agent.RepoOwnerID() != 1 {
			t.Errorf("expected RepoOwnerID '1', got %d", agent.RepoOwnerID())
		}

		if agent.RepoOwner() != "github" {
			t.Errorf("expected RepoOwner 'github', got %s", agent.RepoOwner())
		}

		if agent.RepoID() != 2 {
			t.Errorf("expected RepoID '2', got %d", agent.RepoID())
		}

		if agent.RepoName() != "db-repo" {
			t.Errorf("expected RepoName 'db-repo', got %s", agent.RepoName())
		}

		// Verify the config was set correctly
		if agent.DisplayName() != "Database Agent" {
			t.Errorf("expected DisplayName 'Database Agent', got %s", agent.DisplayName())
		}

		if agent.Description() != "An agent from the database" {
			t.Errorf("expected Description 'An agent from the database', got %s", agent.Description())
		}

		if agent.Prompt() != "You are a database agent" {
			t.Errorf("expected Prompt 'You are a database agent', got %s", agent.Prompt())
		}

		if len(agent.Tools()) != 2 || agent.Tools()[0] != "db_reader" || agent.Tools()[1] != "query_writer" {
			t.Errorf("expected Tools ['db_reader', 'query_writer'], got %v", agent.Tools())
		}

		if agent.ConfigError() != "All work and no play" {
			t.Errorf("expected ConfigError 'All work and no play', got %s", agent.ConfigError())
		}
	})

	t.Run("converts privileged database representation with MCP Config to agent", func(t *testing.T) {
		db := customagent.DBRecord{
			Name:        "db-agent",
			RepoOwnerID: 1,
			RepoOwner:   "github",
			RepoID:      2,
			RepoName:    "db-repo",
			DisplayName: "Database Agent",
			Description: "An agent from the database",
			Prompt:      "You are a database agent",
			Tools:       []string{"db_reader", "query_writer"},
			MCPServers:  []customagent.MCPServer{{Name: "test", Type: "local"}},
		}

		// Then test privileged agent which should return MCP config
		agent2 := FromDB(db)
		if _, ok := agent2.(*PrivilegedAgent); !ok {
			t.Errorf("expected PrivilegedAgent, got %T", agent2)
		}
		if len(agent2.MCPConfig().Servers) != 1 {
			t.Errorf("expected 1 MCP server, got %d", len(agent2.MCPConfig().Servers))
		}

		// Next test unprivileged agent which has no MCP config in the database
		db.MCPServers = nil
		agent := FromDB(db)
		if _, ok := agent.(*PrivilegedAgent); ok {
			t.Error("expected standard Agent, got PrivilegedAgent")
		}
		if len(agent.MCPConfig().Servers) != 0 {
			t.Errorf("expected no MCP servers, got %d", len(agent.MCPConfig().Servers))
		}
	})

	t.Run("sets defaults when DB record is empty", func(t *testing.T) {
		db := customagent.DBRecord{}

		agent := FromDB(db)

		// Verify the config was set correctly
		if agent.Name() != DefaultAgentName {
			t.Errorf("expected name '%s', got %s", DefaultAgentName, agent.Name())
		}
		if agent.DisplayName() != DefaultAgentDisplayName {
			t.Errorf("expected empty DisplayName, got %s", agent.DisplayName())
		}

		if agent.Tools()[0] != "*" {
			t.Errorf("expected default tool '*', got %v", agent.Tools())
		}

		if agent.RepoOwner() != "" {
			t.Errorf("expected empty RepoOwner, got %s", agent.RepoOwner())
		}

		if agent.RepoName() != "" {
			t.Errorf("expected empty RepoName, got %s", agent.RepoName())
		}
		if agent.Version() != "" {
			t.Errorf("expected empty Version, got %s", agent.Version())
		}
		if agent.Description() != "" {
			t.Errorf("expected empty Description, got %s", agent.Description())
		}
		if agent.Prompt() != "" {
			t.Errorf("expected empty Prompt, got %s", agent.Prompt())
		}
	})

	t.Run("ensures tools is not nil", func(t *testing.T) {
		db := Copilot(1, 2, "foo", "bar").ToDB()
		db.Tools = nil // Simulate legacy data with nil tools
		agent := FromDB(db)
		if agent.Tools()[0] != "*" {
			t.Errorf("expected default agent tools to be ['*'], got %v", agent.Tools())
		}

		// Now with a non-copilot example
		db = customagent.DBRecord{Name: "not-copilot", RepoOwner: "foo", RepoName: "bar", Tools: nil}
		agent = FromDB(db)
		if agent.Tools()[0] != "*" {
			t.Errorf("expected custom agent tools to be ['*'], got %v", agent.Tools())
		}
	})

	t.Run("ensures default agent tools is not empty", func(t *testing.T) {
		db := Copilot(1, 2, "foo", "bar").ToDB()
		db.Tools = []string{} // Simulate legacy data with empty tools
		agent := FromDB(db)
		if agent.Tools()[0] != "*" {
			t.Errorf("expected default tool '*', got %v", agent.Tools())
		}
	})
}

func TestToDBAndBack(t *testing.T) {
	t.Run("roundtrip conversion preserves data", func(t *testing.T) {
		// Create original agent
		metadata := Metadata{
			Name:        "roundtrip-agent",
			RepoOwnerID: 1,
			RepoOwner:   "github",
			RepoID:      2,
			RepoName:    "roundtrip-repo",
			Version:     "sha-99999999999999999999999999999999999999",
			ConfigError: "All work and no play",
		}

		config := &Config{
			attributes: ConfigAttributes{
				DisplayName: "Roundtrip Agent",
				Description: "An agent for roundtrip testing",
				Prompt:      "You are a roundtrip test agent",
				Tools:       []string{"tool1", "tool2", "tool3"},
			},
		}

		originalAgent := NewWithConfig(metadata, config)

		// Convert to DB
		db := originalAgent.ToDB()

		// Convert back to Agent
		roundtripAgent := FromDB(db)

		// Verify data is preserved
		if roundtripAgent.Name() != originalAgent.Name() {
			t.Errorf("expected name %s, got %s", originalAgent.Name(), roundtripAgent.Name())
		}

		if roundtripAgent.RepoOwnerID() != originalAgent.RepoOwnerID() {
			t.Errorf("expected RepoOwnerID %d, got %d", originalAgent.RepoOwnerID(), roundtripAgent.RepoOwnerID())
		}

		if roundtripAgent.RepoOwner() != originalAgent.RepoOwner() {
			t.Errorf("expected RepoOwner %s, got %s", originalAgent.RepoOwner(), roundtripAgent.RepoOwner())
		}

		if roundtripAgent.RepoID() != originalAgent.RepoID() {
			t.Errorf("expected RepoID %d, got %d", originalAgent.RepoID(), roundtripAgent.RepoID())
		}

		if roundtripAgent.RepoName() != originalAgent.RepoName() {
			t.Errorf("expected RepoName %s, got %s", originalAgent.RepoName(), roundtripAgent.RepoName())
		}
		if roundtripAgent.Version() != originalAgent.Version() {
			t.Errorf("expected Version %s, got %s", originalAgent.Version(), roundtripAgent.Version())
		}
		// Compare config attributes
		if roundtripAgent.DisplayName() != originalAgent.DisplayName() {
			t.Errorf("expected DisplayName %s, got %s", originalAgent.DisplayName(), roundtripAgent.DisplayName())
		}

		if roundtripAgent.Description() != originalAgent.Description() {
			t.Errorf("expected Description %s, got %s", originalAgent.Description(), roundtripAgent.Description())
		}

		if roundtripAgent.Prompt() != originalAgent.Prompt() {
			t.Errorf("expected Prompt %s, got %s", originalAgent.Prompt(), roundtripAgent.Prompt())
		}

		if len(roundtripAgent.Tools()) != len(originalAgent.Tools()) {
			t.Errorf("expected %d tools, got %d", len(originalAgent.Tools()), len(roundtripAgent.Tools()))
		}

		for i, tool := range originalAgent.Tools() {
			if i >= len(roundtripAgent.Tools()) || roundtripAgent.Tools()[i] != tool {
				t.Errorf("expected tool %s at index %d, got %v", tool, i, roundtripAgent.Tools())
			}
		}

		if roundtripAgent.ConfigError() != originalAgent.ConfigError() {
			t.Errorf("expected ConfigError %s, got %s", originalAgent.ConfigError(), roundtripAgent.ConfigError())
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
