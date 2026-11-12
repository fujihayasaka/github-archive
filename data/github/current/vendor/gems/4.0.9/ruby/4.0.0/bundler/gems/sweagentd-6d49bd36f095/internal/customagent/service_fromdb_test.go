package customagent

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func TestService_FromDB(t *testing.T) {
	ctx := context.Background()

	t.Run("returns Copilot agent when no custom agent name is set or name is copilot", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		testCases := []struct {
			name      string
			agentName string
		}{
			{"empty name", ""},
			{"copilot name", DefaultAgentName},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				db := customagent.DBRecord{
					Name:        tc.agentName,
					RepoOwnerID: 123,
					RepoID:      456,
					RepoOwner:   "test-owner",
					RepoName:    "test-repo",
				}

				agent, err := service.FromDB(ctx, db)
				require.NoError(t, err)
				require.NotNil(t, agent)
				require.Equal(t, "", agent.Name())
				require.Equal(t, int64(123), agent.RepoOwnerID())
				require.Equal(t, int64(456), agent.RepoID())
				require.Equal(t, "test-owner", agent.RepoOwner())
				require.Equal(t, "test-repo", agent.RepoName())
			})
		}
	})

	t.Run("returns job-scoped agent when scope is job", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		db := customagent.DBRecord{
			Name:        "test-agent",
			Scope:       agentconfig.ScopeJob,
			RepoOwnerID: 123,
			RepoID:      456,
			RepoOwner:   "test-owner",
			RepoName:    "test-repo",
			DisplayName: "Test Job-Scoped Agent",
			Description: "A job-scoped test agent",
			Tools:       []string{"tool1", "tool2"},
			Version:     "v1.0.0",
			ConfigError: "some error",
			Target:      "some-target",
			Metadata:    map[string]string{"key": "value"},
			Prompt:      "You are a helpful assistant",
			Permissions: map[string]string{"perm1": "read"},
		}

		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.NotNil(t, agent)

		// Verify it's a PrivilegedAgent (job-scoped agents are PrivilegedAgent)
		_, ok := agent.(*PrivilegedAgent)
		require.True(t, ok, "expected PrivilegedAgent, got %T", agent)

		// Verify metadata
		require.Equal(t, "test-agent", agent.Name())
		require.Equal(t, int64(123), agent.RepoOwnerID())
		require.Equal(t, int64(456), agent.RepoID())
		require.Equal(t, "test-owner", agent.RepoOwner())
		require.Equal(t, "test-repo", agent.RepoName())
		require.Equal(t, "v1.0.0", agent.Version())
		require.Equal(t, "some error", agent.ConfigError())
		require.Equal(t, agentconfig.ScopeJob, agent.Scope())

		// Verify config attributes
		require.Equal(t, "Test Job-Scoped Agent", agent.DisplayName())
		require.Equal(t, "A job-scoped test agent", agent.Description())
		require.Equal(t, []string{"tool1", "tool2"}, agent.Tools())
		require.Equal(t, "some-target", agent.Target())
		require.Equal(t, "value", agent.Metadata()["key"])

		// Verify job-scoped specific attributes
		require.Equal(t, "You are a helpful assistant", agent.Prompt())
		pa := agent.(*PrivilegedAgent)
		require.Equal(t, "read", pa.Permissions().ToMap()["perm1"])
	})

	t.Run("sets default tools when nil for job-scoped agent", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		db := customagent.DBRecord{
			Name:        "test-agent",
			Scope:       agentconfig.ScopeJob,
			RepoOwnerID: 123,
			RepoID:      456,
			RepoOwner:   "test-owner",
			RepoName:    "test-repo",
			Tools:       nil, // nil tools should default to ["*"]
		}

		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.NotNil(t, agent)
		require.Equal(t, []string{"*"}, agent.Tools())
	})

	t.Run("loads job-scoped agent with MCP servers", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		db := customagent.DBRecord{
			Name:        "test-agent",
			Scope:       agentconfig.ScopeJob,
			RepoOwnerID: 123,
			RepoID:      456,
			RepoOwner:   "test-owner",
			RepoName:    "test-repo",
			Tools:       []string{"*"},
			MCPServers: []customagent.MCPServer{
				{
					Name:    "local-server",
					Type:    "local",
					Tools:   []string{"tool1"},
					Command: "python",
					Args:    []string{"-m", "server"},
					Env:     map[string]string{"VAR": "value"},
				},
				{
					Name:    "remote-server",
					Type:    "http",
					Tools:   []string{"tool2"},
					URL:     "https://example.com/mcp",
					Headers: map[string]string{"Auth": "token"},
				},
			},
		}

		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.NotNil(t, agent)

		mcpConfig := agent.(*PrivilegedAgent).MCPConfig()
		require.Len(t, mcpConfig.Servers, 2)

		// Verify local server
		localServer, ok := mcpConfig.Servers["local-server"]
		require.True(t, ok)
		require.Equal(t, "local", localServer.Type)
		require.Equal(t, []string{"tool1"}, localServer.Tools)
		require.NotNil(t, localServer.Local)
		require.Equal(t, "python", localServer.Command)
		require.Equal(t, []string{"-m", "server"}, localServer.Args)
		require.Equal(t, "value", localServer.Env["VAR"])

		// Verify remote server
		remoteServer, ok := mcpConfig.Servers["remote-server"]
		require.True(t, ok)
		require.Equal(t, "http", remoteServer.Type)
		require.Equal(t, []string{"tool2"}, remoteServer.Tools)
		require.NotNil(t, remoteServer.Remote)
		require.Equal(t, "https://example.com/mcp", remoteServer.URL)
		require.Equal(t, "token", remoteServer.Headers["Auth"])
	})

	t.Run("fetches agent from repository for non-job-scoped custom agent", func(t *testing.T) {
		repoID := uint64(2) // This is the ID that noop client returns for .github
		agentName := "my-agent"

		// Setup agent in repository
		agents := map[string]string{
			agentName: `---
name: My Agent
description: A test agent from repo
tools: repo-tool
---

You are a test agent.`,
		}
		options := []spokestest.ClientOption{}
		for name, content := range agents {
			option := spokestest.WithRepoBlob(repoID, filepath.Join(OrgDirectory, name+Extension), []byte(content))
			options = append(options, option)
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		db := customagent.DBRecord{
			Name:        agentName,
			RepoOwnerID: 1,
			RepoID:      int64(repoID),
			RepoOwner:   "test-owner",
			RepoName:    ".github",
			Version:     "",
		}

		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.NotNil(t, agent)
		require.Equal(t, agentName, agent.Name())
		require.Equal(t, "My Agent", agent.DisplayName())
		require.Equal(t, "A test agent from repo", agent.Description())
	})

	t.Run("converts database representation to agent by fetching from repo", func(t *testing.T) {
		repoID := uint64(2)
		agentName := "db-agent"

		// Setup agent in repository - note that Service.FromDB fetches non-adhoc agents
		// from the repo, so the agent config comes from here rather than the DB record
		agents := map[string]string{
			agentName: `---
name: Database Agent
description: An agent from the database
tools:
  - db_reader
  - query_writer
---

This is the prompt.`,
		}
		options := []spokestest.ClientOption{}
		for name, content := range agents {
			option := spokestest.WithRepoBlob(repoID, filepath.Join(OrgDirectory, name+Extension), []byte(content))
			options = append(options, option)
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		db := customagent.DBRecord{
			Name:   agentName,
			RepoID: int64(repoID),
		}

		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.NotNil(t, agent)

		// The agent should be fetched from the repo, so we verify the values from the repo config
		require.Equal(t, "db-agent", agent.Name())
		require.Equal(t, "Database Agent", agent.DisplayName())
		require.Equal(t, "An agent from the database", agent.Description())
		require.Equal(t, []string{"db_reader", "query_writer"}, agent.Tools())
		require.Equal(t, "This is the prompt.", agent.Prompt())
	})

	t.Run("converts privileged database representation with MCP Config to agent", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		db := customagent.DBRecord{
			Name:        "db-agent",
			Scope:       agentconfig.ScopeJob,
			RepoOwnerID: 1,
			RepoOwner:   "github",
			RepoID:      2,
			RepoName:    "db-repo",
			DisplayName: "Database Agent",
			Description: "An agent from the database",
			Tools:       []string{"db_reader", "query_writer"},
			MCPServers:  []customagent.MCPServer{{Name: "test", Type: "local"}},
		}

		// Test privileged agent which should return MCP config
		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)

		pa, ok := agent.(*PrivilegedAgent)
		require.True(t, ok, "expected PrivilegedAgent, got %T", agent)
		require.Len(t, pa.MCPConfig().Servers, 1)

		// Test without MCP servers
		db.MCPServers = nil
		agent2, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.Empty(t, agent2.(*PrivilegedAgent).MCPConfig().Servers)
	})

	t.Run("sets defaults when DB record is empty", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		db := customagent.DBRecord{}

		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.NotNil(t, agent)

		// Empty record should return Copilot agent
		require.Equal(t, "", agent.Name())
		require.Equal(t, "", agent.DisplayName())
		require.Equal(t, []string{"*"}, agent.Tools())
		require.Equal(t, "", agent.RepoOwner())
		require.Equal(t, "", agent.RepoName())
		require.Equal(t, "", agent.Version())
		require.Equal(t, "", agent.Description())
		require.Equal(t, "", agent.Prompt())
	})

	t.Run("ensures tools is not nil", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test with Copilot agent
		db := Copilot(1, 2, "foo", "bar").ToDB()
		db.Tools = nil // Simulate legacy data with nil tools

		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.Equal(t, []string{"*"}, agent.Tools())

		// Now with a non-copilot job-scoped example
		db = customagent.DBRecord{Name: "not-copilot", Scope: agentconfig.ScopeJob, RepoOwner: "foo", RepoName: "bar", Tools: nil}
		agent, err = service.FromDB(ctx, db)
		require.NoError(t, err)
		require.Equal(t, []string{"*"}, agent.Tools())
	})

	t.Run("ensures default agent tools is not empty", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		db := Copilot(1, 2, "foo", "bar").ToDB()
		db.Tools = []string{} // Simulate legacy data with empty tools

		agent, err := service.FromDB(ctx, db)
		require.NoError(t, err)
		require.Equal(t, []string{"*"}, agent.Tools())
	})
}

// Test migrated from agent_test.go TestToDBAndBack
func TestService_ToDBAndBack(t *testing.T) {
	ctx := context.Background()

	t.Run("roundtrip conversion preserves data for job-scoped agent", func(t *testing.T) {
		spokes := spokestest.NewClient(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Create original job-scoped agent (Service.FromDB only does direct conversion for job-scoped agents)
		metadata := Metadata{
			Name:        "roundtrip-agent",
			RepoOwnerID: 1,
			RepoOwner:   "github",
			RepoID:      2,
			RepoName:    "roundtrip-repo",
			Version:     "sha-99999999999999999999999999999999999999",
			ConfigError: "All work and no play",
			Scope:       agentconfig.ScopeJob,
		}

		config := &Config{
			attributes: ConfigAttributes{
				DisplayName:  "Roundtrip Agent",
				Description:  "An agent for roundtrip testing",
				Prompt:       "You are a roundtrip test agent",
				Tools:        []string{"tool1", "tool2", "tool3"},
				ArgumentHint: "Provide input here",
				Metadata: map[string]string{
					"category": "testing",
					"version":  "1.0.0",
				},
				Permissions: permissions.New(map[string]string{
					"contents": "write",
				}),
			},
		}

		originalAgent := &PrivilegedAgent{NewWithConfig(metadata, config)}

		// Convert to DB
		db := originalAgent.ToDB()

		// Convert back to Agent using Service.FromDB
		roundtripAgent, err := service.FromDB(ctx, db)
		require.NoError(t, err)

		// Verify data is preserved
		require.Equal(t, originalAgent.Name(), roundtripAgent.Name())
		require.Equal(t, originalAgent.RepoOwnerID(), roundtripAgent.RepoOwnerID())
		require.Equal(t, originalAgent.RepoOwner(), roundtripAgent.RepoOwner())
		require.Equal(t, originalAgent.RepoID(), roundtripAgent.RepoID())
		require.Equal(t, originalAgent.RepoName(), roundtripAgent.RepoName())
		require.Equal(t, originalAgent.Version(), roundtripAgent.Version())
		require.Equal(t, originalAgent.Scope(), roundtripAgent.Scope())

		// Compare config attributes
		require.Equal(t, originalAgent.DisplayName(), roundtripAgent.DisplayName())
		require.Equal(t, originalAgent.Description(), roundtripAgent.Description())
		require.Equal(t, originalAgent.Tools(), roundtripAgent.Tools())
		require.Equal(t, originalAgent.ConfigError(), roundtripAgent.ConfigError())
		require.Equal(t, originalAgent.Metadata(), roundtripAgent.Metadata())

		// For job-scoped agents, prompt and permissions ARE persisted
		require.Equal(t, originalAgent.Prompt(), roundtripAgent.Prompt())
		require.Equal(t, originalAgent.Permissions(), roundtripAgent.(*PrivilegedAgent).Permissions())
	})

	t.Run("roundtrip conversion preserves data for regular agent", func(t *testing.T) {
		// For non-adhoc agents, Service.FromDB fetches from repo, so we need to
		// set up the spokes mock with the agent config that matches what we expect
		repoID := uint64(2)
		agentName := "roundtrip-agent"

		agentContent := `---
name: Roundtrip Agent
description: An agent for roundtrip testing
tools:
  - tool1
  - tool2
  - tool3
metadata:
  category: testing
  version: 1.0.0
---
You are a roundtrip test agent`

		// Use Directory (not OrgDirectory) for regular repo agents
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(repoID, filepath.Join(Directory, agentName+Extension), []byte(agentContent)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}
		// No enterprise repo for this test
		ghtwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return &sweagentdv1.EnterpriseAgentsResponse{
				RepositoryId: 0, // No enterprise repo
			}, nil
		}

		// No privileged repo feature flag
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Create original agent - use a non-org repo name to avoid privileged status
		metadata := Metadata{
			Name:        agentName,
			RepoOwnerID: 1,
			RepoOwner:   "github",
			RepoID:      int64(repoID),
			RepoName:    "my-regular-repo", // Not .github or .github-private
			Version:     "",
		}

		config := &Config{
			attributes: ConfigAttributes{
				DisplayName: "Roundtrip Agent",
				Description: "An agent for roundtrip testing",
				Prompt:      "You are a roundtrip test agent",
				Tools:       []string{"tool1", "tool2", "tool3"},
				Metadata: map[string]string{
					"category": "testing",
					"version":  "1.0.0",
				},
			},
		}

		originalAgent := NewWithConfig(metadata, config)

		// Convert to DB
		db := originalAgent.ToDB()

		// Convert back to Agent using Service.FromDB (fetches from repo)
		roundtripAgent, err := service.FromDB(ctx, db)
		require.NoError(t, err)

		// Verify key data is preserved (metadata comes from fetched agent)
		require.Equal(t, originalAgent.Name(), roundtripAgent.Name())
		require.Equal(t, originalAgent.DisplayName(), roundtripAgent.DisplayName())
		require.Equal(t, originalAgent.Description(), roundtripAgent.Description())
		require.Equal(t, originalAgent.Tools(), roundtripAgent.Tools())
		require.Equal(t, originalAgent.Prompt(), roundtripAgent.Prompt())
		require.Equal(t, originalAgent.Metadata(), roundtripAgent.Metadata())

		// Verify this is a regular Agent (not PrivilegedAgent)
		_, isPrivileged := roundtripAgent.(*PrivilegedAgent)
		require.False(t, isPrivileged, "expected regular Agent, got PrivilegedAgent")
	})

	t.Run("roundtrip conversion preserves data for privileged agent with MCP servers", func(t *testing.T) {
		// For privileged agents with MCP servers, set up the spokes mock with MCP config
		repoID := uint64(2)
		agentName := "privileged-agent"

		agentContent := `---
name: Privileged Agent
description: A privileged agent with MCP servers
tools:
  - tool1
  - tool2
mcp-servers:
  local-server:
    type: local
    command: python
    args:
      - -m
      - server
    env:
      VAR: value
    tools:
      - local_tool
  remote-server:
    type: http
    url: https://example.com/mcp
    headers:
      Auth: token
    tools:
      - remote_tool
---
You are a privileged test agent`

		// Use OrgDirectory for .github repo agents
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(repoID, filepath.Join(OrgDirectory, agentName+Extension), []byte(agentContent)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}
		// Enable privileged access for MCP servers
		ghtwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return &sweagentdv1.EnterpriseAgentsResponse{
				RepositoryId: repoID,
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Create DB record for the privileged agent
		db := customagent.DBRecord{
			Name:        agentName,
			RepoOwnerID: 1,
			RepoOwner:   "github",
			RepoID:      int64(repoID),
			RepoName:    ".github",
			Version:     "",
		}

		// Convert back to Agent using Service.FromDB (fetches from repo)
		roundtripAgent, err := service.FromDB(ctx, db)
		require.NoError(t, err)

		// Verify key data is preserved
		require.Equal(t, agentName, roundtripAgent.Name())
		require.Equal(t, "Privileged Agent", roundtripAgent.DisplayName())
		require.Equal(t, "A privileged agent with MCP servers", roundtripAgent.Description())
		require.Equal(t, []string{"tool1", "tool2"}, roundtripAgent.Tools())
		require.Equal(t, "You are a privileged test agent", roundtripAgent.Prompt())

		// Verify this is a PrivilegedAgent with MCP config
		pa, isPrivileged := roundtripAgent.(*PrivilegedAgent)
		require.True(t, isPrivileged, "expected PrivilegedAgent, got %T", roundtripAgent)

		mcpConfig := pa.MCPConfig()
		require.Len(t, mcpConfig.Servers, 2)

		// Verify local server
		localServer, ok := mcpConfig.Servers["local-server"]
		require.True(t, ok)
		require.Equal(t, "local", localServer.Type)
		require.Equal(t, "python", localServer.Command)
		require.Equal(t, []string{"-m", "server"}, localServer.Args)
		require.Equal(t, "value", localServer.Env["VAR"])
		require.Equal(t, []string{"local_tool"}, localServer.Tools)

		// Verify remote server
		remoteServer, ok := mcpConfig.Servers["remote-server"]
		require.True(t, ok)
		require.Equal(t, "http", remoteServer.Type)
		require.Equal(t, "https://example.com/mcp", remoteServer.URL)
		require.Equal(t, "token", remoteServer.Headers["Auth"])
		require.Equal(t, []string{"remote_tool"}, remoteServer.Tools)
	})
}
