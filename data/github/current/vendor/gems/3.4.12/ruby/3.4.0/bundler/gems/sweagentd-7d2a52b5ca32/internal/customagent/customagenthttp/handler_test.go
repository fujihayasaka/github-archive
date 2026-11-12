package customagenthttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// Helper function to create spokes with repo-specific agents for testing repo/org precedence
func makeSpokesWithRepoSpecificAgents(t *testing.T, repoAgents, orgAgents map[string]string, repoID, orgRepoID uint64) *spokestest.Client {
	t.Helper()

	options := []spokestest.ClientOption{}

	// Add repository-specific agents
	for name, content := range repoAgents {
		option := spokestest.ClientWithRepoBlob(repoID, filepath.Join(customagent.Directory, name+customagent.Extension), []byte(content))
		options = append(options, option)
	}

	// Add organization-specific agents
	for name, content := range orgAgents {
		option := spokestest.ClientWithRepoBlob(orgRepoID, filepath.Join(customagent.OrgDirectory, name+customagent.Extension), []byte(content))
		options = append(options, option)
	}

	return spokestest.NewClient(t, options...)
}

func TestHandlerListAgents(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("user must be in context", func(t *testing.T) {
		h := &Handler{
			obsv: obsv,
		}
		req := httptest.NewRequest(http.MethodGet, "/custom-agents/testowner/testrepo", http.NoBody)
		rr := httptest.NewRecorder()
		h.listAgents(rr, req)

		if rr.Code != http.StatusUnauthorized {
			t.Errorf("expected status %d, got %d", http.StatusUnauthorized, rr.Code)
		}
	})

	t.Run("feature flag must be enabled for user", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		ghTwirp := githubtwirp.NewNoopClient()
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, svc)

		ctx := requestctx.NewContext(context.Background())

		err := requestctx.AddUser(ctx, &requestctx.UserInfo{ID: 123})
		if err != nil {
			t.Fatalf("failed to add user to context: %v", err)
		}

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()
		h.listAgents(rr, req)

		if rr.Code != http.StatusNotFound {
			t.Errorf("expected status %d, got %d", http.StatusNotFound, rr.Code)
		}
	})

	t.Run("validate repo owner and name", func(t *testing.T) {
		ffs := map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:                    true,
			featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
		}
		ffClient := featureflags.NewNoopClient(ffs)
		h := &Handler{
			obsv:     obsv,
			ffclient: ffClient,
		}
		ctx := requestctx.NewContext(context.Background())

		err := requestctx.AddUser(ctx, &requestctx.UserInfo{ID: 123})
		if err != nil {
			t.Fatalf("failed to add user to context: %v", err)
		}

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testrepo", nil)
		rr := httptest.NewRecorder()
		h.listAgents(rr, req)

		if rr.Code != http.StatusBadRequest {
			t.Errorf("expected status %d, got %d", http.StatusBadRequest, rr.Code)
		}
	})

	t.Run("maps agent metadata to response", func(t *testing.T) {
		ffs := map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:                    true,
			featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
		}
		ffClient := featureflags.NewNoopClient(ffs)

		agents := map[string]string{
			"agent1": "---\nname: agent1\ndescription: First test agent\nkey: value\n---\nthis is agent 1",
			"agent2": "---\nname: agent2\ndescription: Second test agent\nkey: value\n---\nthis is agent 2",
		}
		spokes := customagenttest.MakeSpokes(t, agents)
		ghTwirp := githubtwirp.NewNoopClient()
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, svc)

		ctx := requestctx.NewContext(context.Background())

		userInfo := &requestctx.UserInfo{
			ID:        123,
			TokenInfo: &requestctx.TokenInfo{Token: "token"},
		}
		err := requestctx.AddUser(ctx, userInfo)
		if err != nil {
			t.Fatalf("failed to add user to context: %v", err)
		}

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()
		h.listAgents(rr, req)

		if rr.Code != http.StatusOK {
			t.Errorf("expected status %d, got %d", http.StatusOK, rr.Code)
		}

		if !strings.Contains(rr.Body.String(), "agent1") {
			t.Errorf("expected response body to contain agent1, got %s", rr.Body.String())
		}

		if !strings.Contains(rr.Body.String(), "\"repo_id\":1") {
			t.Errorf("expected response body to contain \"repo_id\":1, got %s", rr.Body.String())
		}

		if !strings.Contains(rr.Body.String(), "\"repo_owner_id\":456") {
			t.Errorf("expected response body to contain \"repo_owner_id\":456, got %s", rr.Body.String())
		}

		if !strings.Contains(rr.Body.String(), "agent2") {
			t.Errorf("expected response body to contain agent2, got %s", rr.Body.String())
		}
	})

	t.Run("returns empty list when no agents found", func(t *testing.T) {
		ffs := map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:                    true,
			featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
		}
		ffClient := featureflags.NewNoopClient(ffs)

		// Create a service that will return empty agents list
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return nil, twirp.NewError(twirp.NotFound, "repository not found")
		}

		// Empty spokes will result in no agents, but service should return empty list, not error
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, svc)

		ctx := requestctx.NewContext(context.Background())

		userInfo := &requestctx.UserInfo{
			ID:        123,
			TokenInfo: &requestctx.TokenInfo{Token: "token"},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()
		h.listAgents(rr, req)

		require.Equal(t, http.StatusNotFound, rr.Code)
		// For 404 response, no need to check response body structure
	})

	t.Run("excludeInvalidConfig query parameter filters invalid configurations", func(t *testing.T) {
		ffs := map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:                    true,
			featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
		}
		ffClient := featureflags.NewNoopClient(ffs)

		// Setup agents with mix of valid and invalid configurations
		agents := map[string]string{
			"valid-agent": `---
name: Valid Agent
description: A valid agent configuration
tools: ["tool1"]
---
You are a valid agent.`,
			"invalid-no-desc1": `---
name: No Description Agent 1
tools: ["tool2"]
---
Invalid agent without name.`,
			"invalid-no-desc2": `---
name: No Description Agent 2
tools: ["tool3"]
---
Invalid agent without description.`,
		}
		spokes := customagenttest.MakeSpokes(t, agents)
		ghTwirp := githubtwirp.NewNoopClient()
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID:        123,
			TokenInfo: &requestctx.TokenInfo{Token: "token"},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		// Test with excludeInvalidConfig=true (should only return valid agents)
		t.Run("excludeInvalidConfig=true filters out invalid configurations", func(t *testing.T) {
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo?exclude_invalid_config=true", nil)
			rr := httptest.NewRecorder()
			h.listAgents(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)

			// Should only return the valid agent
			require.Len(t, response.Agents, 1)
			assert.Equal(t, "Valid Agent", response.Agents[0].DisplayName)
			assert.Empty(t, response.Agents[0].ConfigError, "valid agent should not have config error")
		})

		// Test with excludeInvalidConfig=false (should return all agents including invalid ones)
		t.Run("excludeInvalidConfig=false includes invalid configurations", func(t *testing.T) {
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo?exclude_invalid_config=false", nil)
			rr := httptest.NewRecorder()
			h.listAgents(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)

			// Should return all agents (valid + invalid)
			require.Len(t, response.Agents, 3)

			// Find the valid agent and verify it has no config error
			var validAgent *customAgentDTO
			for i := range response.Agents {
				if response.Agents[i].DisplayName == "Valid Agent" {
					validAgent = &response.Agents[i]
					break
				}
			}
			require.NotNil(t, validAgent, "should find valid agent")
			assert.Empty(t, validAgent.ConfigError, "valid agent should not have config error")

			// Find invalid agents and verify they have config errors
			var invalidAgents []*customAgentDTO
			for i := range response.Agents {
				if response.Agents[i].ConfigError != "" {
					invalidAgents = append(invalidAgents, &response.Agents[i])
				}
			}
			require.Len(t, invalidAgents, 2, "should have 2 invalid agents with config errors")

			// Verify that invalid agent names have warning symbol
			for _, agent := range invalidAgents {
				assert.NotEmpty(t, agent.ConfigError, "invalid agent should have config error")
			}
		})

		// Test default behavior (no query parameter should behave like excludeInvalidConfig=false)
		t.Run("default behavior includes invalid configurations", func(t *testing.T) {
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
			rr := httptest.NewRecorder()
			h.listAgents(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)

			// Should return all agents by default
			require.Len(t, response.Agents, 3)
		})
	})
}

func TestHandlerGetAgent(t *testing.T) {
	t.Run("returns custom agent details", func(t *testing.T) {
		result := runGetTest(t, "sha-999999999999999999999999999999999999", "agent1", "sha-999999999999999999999999999999999999", http.StatusOK)
		assert.Equal(t, "agent1", result.Name, "agent name should match")
		assert.Equal(t, "This is agent 1", result.Description, "agent description should match")
		assert.Equal(t, []string{"tool1", "tool2"}, result.Tools, "agent tools should match")
		assert.Equal(t, "This is the prompt for agent 1.", result.Prompt, "agent prompt should match")
		assert.Equal(t, "sha-999999999999999999999999999999999999", result.Version, "agent version should match")
	})

	t.Run("returns latest custom agent details", func(t *testing.T) {
		result := runGetTest(t, "", "agent1", "", http.StatusOK)
		assert.Equal(t, "agent1", result.Name, "agent name should match")
		assert.Equal(t, "This is agent 1", result.Description, "agent description should match")
		assert.Equal(t, []string{"tool1", "tool2"}, result.Tools, "agent tools should match")
		assert.Equal(t, "This is the prompt for agent 1.", result.Prompt, "agent prompt should match")
		assert.NotEmpty(t, result.Version, "agent version should be set")
	})

	t.Run("404s when repo not found", func(t *testing.T) {
		runGetTest(t, "repo-does-not-exist", "agent1", "", http.StatusNotFound)
	})

	t.Run("404s for non-existent agent", func(t *testing.T) {
		runGetTest(t, "", "does-not-exist", "", http.StatusNotFound)
	})

	t.Run("404s for non-existent version", func(t *testing.T) {
		runGetTest(t, "sha-999999999999999999999999999999999999", "agent1", "sha-999999999999999999999999999999999988", http.StatusNotFound)
	})
}

const agentContent string = `---
name: agent1
description: This is agent 1
tools: ["tool1", "tool2" ]
---
This is the prompt for agent 1.
`

func runGetTest(t *testing.T, dataVersion, expectedAgentName, expectedVersion string, expectedHTTPStatus int) customAgentDTO {
	obsv := observability.NewNoopExporters()
	ffs := map[string]bool{
		featureflags.CopilotSWEAgentUseCustomAgents:                    true,
		featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
	}
	ffClient := featureflags.NewNoopClient(ffs)
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
		return nil, nil
	}
	if dataVersion == "repo-does-not-exist" {
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return nil, twirp.NewError(twirp.NotFound, "repository not found")
		}
	} else {
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         12345,
						Name:       "testrepo",
						OwnerLogin: "testowner",
						OwnerId:    456,
					},
				},
			}, nil
		}
	}

	ctx := requestctx.NewContext(context.Background())

	agents := map[string]string{
		"agent1": agentContent,
		"agent2": "---\nkey: value\n---\nthis is agent 2",
	}
	spokes := customagenttest.MakeSpokesWithCommitSHA(t, agents, dataVersion)
	svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, ffClient, svc)

	userInfo := &requestctx.UserInfo{
		ID:        123,
		TokenInfo: &requestctx.TokenInfo{Token: "token"},
	}
	err := requestctx.AddUser(ctx, userInfo)
	if err != nil {
		t.Fatalf("failed to add user to context: %v", err)
	}

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("repoOwner", "testowner")
	rctx.URLParams.Add("repoName", "testrepo")
	rctx.URLParams.Add("agentName", expectedAgentName)
	ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

	var req *http.Request
	if expectedVersion != "" {
		req = httptest.NewRequestWithContext(ctx, "GET", "/agent/custom-agents/testowner/testrepo/"+expectedAgentName+"?version="+expectedVersion, nil)
	} else {
		req = httptest.NewRequestWithContext(ctx, "GET", "/agent/custom-agents/testowner/testrepo/"+expectedAgentName, nil)
	}
	rr := httptest.NewRecorder()
	h.getAgent(rr, req)

	// Check expected status
	if rr.Code != expectedHTTPStatus {
		t.Errorf("expected status %d, got %d", expectedHTTPStatus, rr.Code)
	}

	// If not OK, return empty result
	if rr.Code != http.StatusOK {
		return customAgentDTO{}
	}

	var result customAgentDTO
	err = json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err, "failed to unmarshal response")

	return result
}

func TestMakeCustomAgentDTO(t *testing.T) {
	t.Run("includes MCP servers in DTO", func(t *testing.T) {
		agentContent := `---
name: mcp-test-agent
description: Agent with MCP servers
tools: ["file_ops", "web_search"]
mcp-servers:
  filesystem:
    type: local
    tools: ["read_file", "write_file"]
    command: npx
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
    env:
      NODE_ENV: development
  web-search:
    type: sse
    tools: ["web_search"]
    url: https://api.example.com/mcp
    headers:
      Authorization: Bearer token123
---
This agent has MCP servers configured.`

		agents := map[string]string{
			"mcp-test-agent": agentContent,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, agents, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:                    true,
			featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
		})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, 123, "testowner", ".github", "mcp-test-agent", "") // Need to use .github repo to get privileged result
		require.NoError(t, err)

		// Test with includePrompt = true
		dtoWithPrompt := makeCustomAgentDTO(agent, true)
		assert.Equal(t, "mcp-test-agent", dtoWithPrompt.Name)
		assert.Equal(t, "Agent with MCP servers", dtoWithPrompt.Description)
		assert.Equal(t, "This agent has MCP servers configured.", dtoWithPrompt.Prompt)
		assert.NotNil(t, dtoWithPrompt.MCPServers)

		// Verify filesystem server (local type)
		assert.Contains(t, dtoWithPrompt.MCPServers, "filesystem")
		filesystemServer := dtoWithPrompt.MCPServers["filesystem"]
		assert.Equal(t, "local", filesystemServer.Type)
		assert.ElementsMatch(t, []string{"read_file", "write_file"}, filesystemServer.Tools)
		assert.NotNil(t, filesystemServer.Local)
		assert.Equal(t, "npx", filesystemServer.Command)
		assert.ElementsMatch(t, []string{"-y", "@modelcontextprotocol/server-filesystem", "/tmp"}, filesystemServer.Args)
		assert.Equal(t, "development", filesystemServer.Env["NODE_ENV"])
		assert.Nil(t, filesystemServer.Remote)

		// Verify web-search server (remote type)
		assert.Contains(t, dtoWithPrompt.MCPServers, "web-search")
		webSearchServer := dtoWithPrompt.MCPServers["web-search"]
		assert.Equal(t, "sse", webSearchServer.Type)
		assert.ElementsMatch(t, []string{"web_search"}, webSearchServer.Tools)
		assert.NotNil(t, webSearchServer.Remote)
		assert.Equal(t, "https://api.example.com/mcp", webSearchServer.URL)
		assert.Equal(t, "Bearer token123", webSearchServer.Headers["Authorization"])
		assert.Nil(t, webSearchServer.Local)

		// Test with includePrompt = false
		dtoWithoutPrompt := makeCustomAgentDTO(agent, false)
		assert.Equal(t, "mcp-test-agent", dtoWithoutPrompt.Name)
		assert.Equal(t, "Agent with MCP servers", dtoWithoutPrompt.Description)
		assert.Empty(t, dtoWithoutPrompt.Prompt, "prompt should be excluded when includePrompt=false")
		assert.NotNil(t, dtoWithoutPrompt.MCPServers, "MCP servers should still be included")
		assert.Contains(t, dtoWithoutPrompt.MCPServers, "filesystem")
		assert.Contains(t, dtoWithoutPrompt.MCPServers, "web-search")
	})

	t.Run("handles empty MCP servers", func(t *testing.T) {
		agentContent := `---
name: no-mcp-agent
description: Agent without MCP servers
tools: ["basic_tool"]
---
This agent has no MCP servers.`

		agents := map[string]string{
			"no-mcp-agent": agentContent,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:                    true,
			featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
		})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, 123, "testowner", "testrepo", "no-mcp-agent", "")
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		assert.Equal(t, "no-mcp-agent", dto.Name)
		// MCPServers can be nil or empty map when no servers are configured
		if dto.MCPServers != nil {
			assert.Empty(t, dto.MCPServers, "should have empty MCP servers map")
		}
	})
}

func TestHandlerGetAgentWithMCPServers(t *testing.T) {
	runTest := func(t *testing.T, repoName string, enterprisePrivileged, isPrivileged bool) {
		t.Helper()
		obsv := observability.NewNoopExporters()
		ffs := map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:                    true,
			featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
		}
		ffClient := featureflags.NewNoopClient(ffs)

		agentWithMCP := `---
name: mcp-agent
description: Test agent with MCP
tools: ["*"]
mcp-servers:
  test-server:
    type: local
    tools: ["test_tool"]
    command: test-cmd
    args: ["arg1", "arg2"]
---
Test prompt with MCP.`

		privRepoID := uint64(1)
		agents := map[string]string{
			"mcp-agent": agentWithMCP,
		}
		privAgents := agents
		if isPrivileged {
			agents = map[string]string{}
			if !enterprisePrivileged {
				privRepoID = uint64(2)
			}
		} else {
			privAgents = map[string]string{}
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, privAgents, uint64(1), privRepoID)
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			if !enterprisePrivileged {
				return &sweagentdTwirp.EnterpriseAgentsResponse{
					RepositoryId: 999999,
				}, nil
			}
			return &sweagentdTwirp.EnterpriseAgentsResponse{
				RepositoryId: 1,
			}, nil
		}

		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, svc)
		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID:        123,
			TokenInfo: &requestctx.TokenInfo{Token: "token"},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", repoName)
		rctx.URLParams.Add("agentName", "mcp-agent")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo/mcp-agent", nil)
		rr := httptest.NewRecorder()
		h.getAgent(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var result customAgentDTO
		err = json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		if isPrivileged {
			// Verify basic agent info
			assert.Equal(t, "mcp-agent", result.Name)
			assert.Equal(t, "Test agent with MCP", result.Description)
			assert.Equal(t, "Test prompt with MCP.", result.Prompt)

			// Verify MCP servers are included in HTTP response
			assert.NotNil(t, result.MCPServers)
			assert.Contains(t, result.MCPServers, "test-server")

			testServer := result.MCPServers["test-server"]
			assert.Equal(t, "local", testServer.Type)
			assert.ElementsMatch(t, []string{"test_tool"}, testServer.Tools)
			assert.NotNil(t, testServer.Local)
			assert.Equal(t, "test-cmd", testServer.Command)
			assert.ElementsMatch(t, []string{"arg1", "arg2"}, testServer.Args)
		} else {
			assert.Nil(t, result.MCPServers, "MCP servers should be nil for non-privileged repo")
		}
	}

	t.Run("returns MCP servers in response", func(t *testing.T) {
		runTest(t, ".github", false, true) // Privileged repo to get MCP servers
	})

	t.Run("does not return MCP servers for non-privileged repo", func(t *testing.T) {
		runTest(t, "testrepo", false, false) // Non-privileged repo should not return MCP servers
	})

	t.Run("returns MCP servers in response for enterprise repo", func(t *testing.T) {
		runTest(t, "testrepo", true, true) // Privileged repo to get MCP servers
	})
}

func TestHandlerListAgentsWithMCPServers(t *testing.T) {
	runTest := func(t *testing.T, enterprisePrivileged, orgPrivileged bool) {
		t.Helper()
		obsv := observability.NewNoopExporters()
		ffs := map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:                    true,
			featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault: true,
		}
		ffClient := featureflags.NewNoopClient(ffs)

		agent1WithMCP := `---
name: agent1
description: First agent
tools: ["tool1"]
mcp-servers:
  server1:
    type: local
    tools: ["server1_tool"]
    command: cmd1
---
First agent prompt.`

		agent2WithMCP := `---
name: agent2
description: Second agent
tools: ["tool2"]
mcp-servers:
  server2:
    type: sse
    tools: ["server2_tool"]
    url: https://example.com/server2
---
Second agent prompt.`

		agents := map[string]string{
			"agent1": agent1WithMCP,
			"agent2": agent2WithMCP,
		}

		contentRepoID := uint64(1)
		privRepoID := uint64(99)
		privAgents := agents
		switch {
		case orgPrivileged:
			agents = map[string]string{}
			privRepoID = 2 // Use .github repo ID to simulate org-privileged
		case enterprisePrivileged:
			agents = map[string]string{}
			privRepoID = 3 // Use enterprise repo ID to simulate enterprise-privileged
		default:
			// Use normal repo ID for non-privileged
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, privAgents, contentRepoID, privRepoID)

		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			if enterprisePrivileged {
				return &sweagentdTwirp.EnterpriseAgentsResponse{
					RepositoryId: 3,
				}, nil
			}
			return &sweagentdTwirp.EnterpriseAgentsResponse{
				RepositoryId: 9999999,
			}, nil
		}
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			switch parts[1] {
			case "testrepo":
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{
							Id:         1,
							OwnerId:    1,
							OwnerLogin: "testowner",
							Name:       "testrepo",
						},
					},
				}, nil
			case ".github":
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{
							Id:         2,
							OwnerId:    1,
							OwnerLogin: "testowner",
							Name:       ".github",
						},
					},
				}, nil
			default:
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{
							Id:         3,
							OwnerId:    1,
							OwnerLogin: "testowner",
							Name:       "enterpriserepo",
						},
					},
				}, nil
			}
		}
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID:        123,
			TokenInfo: &requestctx.TokenInfo{Token: "token"},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo") // Need a privileged repo to test MCP
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()
		h.listAgents(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.Unmarshal(rr.Body.Bytes(), &response)
		require.NoError(t, err)

		require.Len(t, response.Agents, 2)

		if orgPrivileged || enterprisePrivileged {
			// Verify that prompts are NOT included in list response (includePrompt=false)
			for _, agent := range response.Agents {
				assert.Empty(t, agent.Prompt, "prompts should not be included in list response")
				assert.NotNil(t, agent.MCPServers, "MCP servers should be included")
			}

			// Find and verify specific agents
			var agent1, agent2 *customAgentDTO
			for i := range response.Agents {
				if response.Agents[i].Name == "agent1" {
					agent1 = &response.Agents[i]
				}
				if response.Agents[i].Name == "agent2" {
					agent2 = &response.Agents[i]
				}
			}

			require.NotNil(t, agent1, "agent1 should be in response")
			require.NotNil(t, agent2, "agent2 should be in response")

			// Verify agent1 MCP servers
			assert.Contains(t, agent1.MCPServers, "server1")
			server1 := agent1.MCPServers["server1"]
			assert.Equal(t, "local", server1.Type)
			assert.Equal(t, "cmd1", server1.Command)

			// Verify agent2 MCP servers
			assert.Contains(t, agent2.MCPServers, "server2")
			server2 := agent2.MCPServers["server2"]
			assert.Equal(t, "sse", server2.Type)
			assert.Equal(t, "https://example.com/server2", server2.URL)
		} else {
			assert.Empty(t, response.Agents[0].MCPServers, "MCP servers should be nil for non-privileged repo")
			assert.Empty(t, response.Agents[1].MCPServers, "MCP servers should be nil for non-privileged repo")
		}
	}
	t.Run("includes MCP servers in list response", func(t *testing.T) {
		runTest(t, false, true) // Privileged repo to get MCP servers
	})

	t.Run("does not include MCP servers in list response if not privileged", func(t *testing.T) {
		runTest(t, false, false) // Non-privileged repo should not return MCP servers
	})

	t.Run("includes MCP servers in list response from enterprise repo", func(t *testing.T) {
		runTest(t, true, false) // Enterprise repo should return MCP servers
	})
}
