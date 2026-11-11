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
	"github.com/github/go-stats"
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
		option := spokestest.WithRepoBlob(repoID, filepath.Join(customagent.Directory, name+customagent.Extension), []byte(content))
		options = append(options, option)
	}

	// Add organization-specific agents
	for name, content := range orgAgents {
		option := spokestest.WithRepoBlob(orgRepoID, filepath.Join(customagent.OrgDirectory, name+customagent.Extension), []byte(content))
		options = append(options, option)
	}

	return spokestest.NewClient(t, options...)
}

func TestHandlerListAgents(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("validate repo owner and name with nil userInfo", func(t *testing.T) {
		h := &Handler{
			obsv: obsv,
		}
		req := httptest.NewRequest(http.MethodGet, "/custom-agents/testowner/testrepo", http.NoBody)
		rr := httptest.NewRecorder()
		// Test that handler returns bad request when repo params are missing (no chi route context)
		h.listAgents(&requestctx.UserInfo{ID: 123}, stats.Tags{})(rr, req)

		if rr.Code != http.StatusBadRequest {
			t.Errorf("expected status %d, got %d", http.StatusBadRequest, rr.Code)
		}
	})

	t.Run("validate repo owner and name", func(t *testing.T) {
		ffs := map[string]bool{}
		ffClient := featureflags.NewNoopClient(ffs)
		h := &Handler{
			obsv:     obsv,
			ffclient: ffClient,
		}
		ctx := requestctx.NewContext(context.Background())

		userInfo := &requestctx.UserInfo{ID: 123}
		err := requestctx.AddUser(ctx, userInfo)
		if err != nil {
			t.Fatalf("failed to add user to context: %v", err)
		}

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testrepo", nil)
		rr := httptest.NewRecorder()
		h.listAgents(userInfo, stats.Tags{})(rr, req)

		if rr.Code != http.StatusBadRequest {
			t.Errorf("expected status %d, got %d", http.StatusBadRequest, rr.Code)
		}
	})

	t.Run("maps agent metadata to response", func(t *testing.T) {
		ffs := map[string]bool{}
		ffClient := featureflags.NewNoopClient(ffs)

		agents := map[string]string{
			"agent1": "---\nname: agent1\ndescription: First test agent\nkey: value\n---\nthis is agent 1",
			"agent2": "---\nname: agent2\ndescription: Second test agent\nkey: value\n---\nthis is agent 2",
		}
		spokes := customagenttest.MakeSpokes(t, agents)
		ghTwirp := githubtwirp.NewNoopClient()
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

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
		h.listAgents(userInfo, stats.Tags{})(rr, req)

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
		ffs := map[string]bool{}
		ffClient := featureflags.NewNoopClient(ffs)

		// Empty spokes will result in no agents directory, should return empty list
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		ghTwirp := githubtwirp.NewNoopClient()
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

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
		h.listAgents(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.NewDecoder(rr.Body).Decode(&response)
		require.NoError(t, err)
		require.Empty(t, response.Agents)
	})

	t.Run("excludeInvalidConfig query parameter filters invalid configurations", func(t *testing.T) {
		ffs := map[string]bool{}
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
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

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
			h.listAgents(userInfo, stats.Tags{})(rr, req)

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
			h.listAgents(userInfo, stats.Tags{})(rr, req)

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
			h.listAgents(userInfo, stats.Tags{})(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)

			// Should return all agents by default
			require.Len(t, response.Agents, 3)
		})
	})

	t.Run("include_sources query parameter filters agent sources", func(t *testing.T) {
		ffs := map[string]bool{}
		ffClient := featureflags.NewNoopClient(ffs)

		repoID := uint64(1)
		orgRepoID := uint64(2)
		repoOwnerID := uint64(3)

		repoAgents := map[string]string{
			"repo-agent": `---
name: Repo Agent
description: Agent from repository
---
Repo agent.`,
		}
		orgAgents := map[string]string{
			"org-agent": `---
name: Org Agent
description: Agent from organization
---
Org agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)

		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			if parts[1] == ".github" || parts[1] == ".github-private" {
				id = orgRepoID
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         int64(id),
						Name:       parts[1],
						OwnerId:    int64(repoOwnerID),
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

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

		t.Run("include_sources=org excludes agents from initial repo", func(t *testing.T) {
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo?include_sources=org", nil)
			rr := httptest.NewRecorder()
			h.listAgents(userInfo, stats.Tags{})(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)

			require.Len(t, response.Agents, 1)
			assert.Equal(t, "org-agent", response.Agents[0].Name)
		})

		t.Run("include_sources=repo includes only repo agents", func(t *testing.T) {
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo?include_sources=repo", nil)
			rr := httptest.NewRecorder()
			h.listAgents(userInfo, stats.Tags{})(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)

			require.Len(t, response.Agents, 1)
			assert.Equal(t, "repo-agent", response.Agents[0].Name)
		})

		t.Run("include_sources=repo,org includes both repo and org agents", func(t *testing.T) {
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo?include_sources=repo,org", nil)
			rr := httptest.NewRecorder()
			h.listAgents(userInfo, stats.Tags{})(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)

			require.Len(t, response.Agents, 2)

			agentNames := make([]string, len(response.Agents))
			for i, agent := range response.Agents {
				agentNames[i] = agent.Name
			}
			assert.Contains(t, agentNames, "repo-agent")
			assert.Contains(t, agentNames, "org-agent")
		})

		t.Run("default behavior includes all sources", func(t *testing.T) {
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
			rr := httptest.NewRecorder()
			h.listAgents(userInfo, stats.Tags{})(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)

			require.Len(t, response.Agents, 2)

			agentNames := make([]string, len(response.Agents))
			for i, agent := range response.Agents {
				agentNames[i] = agent.Name
			}
			assert.Contains(t, agentNames, "repo-agent")
			assert.Contains(t, agentNames, "org-agent")
		})
	})

	t.Run("feature-flagged filtering excludes non-user-invocable triggered agents", func(t *testing.T) {
		makeHandler := func(flags map[string]bool) *Handler {
			ffClient := featureflags.NewNoopClient(flags)
			agents := map[string]string{
				"user-invocable-triggered": `---
name: User Invocable Triggered
description: Visible because it is user invocable
user-invocable: true
on:
  issues:
    types: [opened]
---
Visible agent.`,
				"non-user-invocable-triggered": `---
name: Non User Invocable Triggered
description: Hidden when flag is enabled
user-invocable: false
on:
  issues:
    types: [opened]
---
Hidden agent.`,
				"non-user-invocable-no-triggers": `---
name: Non User Invocable No Triggers
description: Visible because it has no triggers
user-invocable: false
---
Visible agent.`,
			}
			spokes := customagenttest.MakeSpokes(t, agents)
			ghTwirp := githubtwirp.NewNoopClient()
			svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
			return NewHandler(obsv, ffClient, ghTwirp, svc)
		}

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

		t.Run("flag disabled preserves existing behavior", func(t *testing.T) {
			h := makeHandler(map[string]bool{})
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
			rr := httptest.NewRecorder()
			h.listAgents(userInfo, stats.Tags{})(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)
			require.Len(t, response.Agents, 3)
		})

		t.Run("flag enabled hides non-user-invocable triggered agents", func(t *testing.T) {
			h := makeHandler(map[string]bool{
				featureflags.CopilotSWEAgentCustomAgentListFilterNonUserInvocableTriggered: true,
			})
			req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
			rr := httptest.NewRecorder()
			h.listAgents(userInfo, stats.Tags{})(rr, req)

			require.Equal(t, http.StatusOK, rr.Code)

			var response listAgentsResponse
			err = json.Unmarshal(rr.Body.Bytes(), &response)
			require.NoError(t, err)
			require.Len(t, response.Agents, 2)

			agentNames := make([]string, len(response.Agents))
			for i, agent := range response.Agents {
				agentNames[i] = agent.Name
			}

			assert.Contains(t, agentNames, "user-invocable-triggered")
			assert.Contains(t, agentNames, "non-user-invocable-no-triggers")
			assert.NotContains(t, agentNames, "non-user-invocable-triggered")
		})
	})
}

func TestHandlerListAgentsDedupeNames(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffs := map[string]bool{}
	ffClient := featureflags.NewNoopClient(ffs)

	repoID := uint64(1)
	orgRepoID := uint64(2)
	repoOwnerID := uint64(3)

	// Setup agents with duplicate names across repo and org
	repoAgents := map[string]string{
		"shared-agent": `---
name: Shared Agent (Repo)
description: Agent from repository
---
Repo version.`,
	}
	orgAgents := map[string]string{
		"shared-agent": `---
name: Shared Agent (Org)
description: Agent from organization
---
Org version.`,
	}
	spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		parts := strings.Split(req.Nwos[0], "/")
		id := repoID
		if parts[1] == ".github" || parts[1] == ".github-private" {
			id = orgRepoID
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{
					Id:         int64(id),
					Name:       parts[1],
					OwnerId:    int64(repoOwnerID),
					OwnerLogin: parts[0],
				},
			},
		}, nil
	}

	svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
	h := NewHandler(obsv, ffClient, ghTwirp, svc)

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

	t.Run("dedupeNames=true returns only unique agent names", func(t *testing.T) {
		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo?dedupe=true", nil)
		rr := httptest.NewRecorder()
		h.listAgents(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.Unmarshal(rr.Body.Bytes(), &response)
		require.NoError(t, err)

		// Should only return 1 agent when deduped
		require.Len(t, response.Agents, 1)
		assert.Equal(t, "shared-agent", response.Agents[0].Name)
		assert.Equal(t, "Agent from repository", response.Agents[0].Description)
	})

	t.Run("dedupeNames=false returns duplicate agent names", func(t *testing.T) {
		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo?dedupe=false&include_sources=repo,org", nil)
		rr := httptest.NewRecorder()
		h.listAgents(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.Unmarshal(rr.Body.Bytes(), &response)
		require.NoError(t, err)

		// Should return multiple agents with same name
		require.GreaterOrEqual(t, len(response.Agents), 2)

		// Check we have both repo and org versions
		descriptions := make([]string, len(response.Agents))
		for i, agent := range response.Agents {
			descriptions[i] = agent.Description
		}
		assert.Contains(t, descriptions, "Agent from repository")
		assert.Contains(t, descriptions, "Agent from organization")
	})

	t.Run("default behavior (no dedupe param) deduplicates agents", func(t *testing.T) {
		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()
		h.listAgents(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.Unmarshal(rr.Body.Bytes(), &response)
		require.NoError(t, err)

		// Default should deduplicate, returning only 1 agent
		require.Len(t, response.Agents, 1)
		assert.Equal(t, "shared-agent", response.Agents[0].Name)
	})
}

func TestHandlerListAutomations(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("validate repo owner and name", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		h := &Handler{obsv: obsv, ffclient: ffClient}

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{ID: 123}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/automations/testrepo", http.NoBody)
		rr := httptest.NewRecorder()
		h.listAutomations(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusBadRequest, rr.Code)
	})

	t.Run("returns only agents with triggers", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		agents := map[string]string{
			"automation-issues": `---
name: Automation Issues
description: Triggered by issue events
user-invocable: false
on:
  issues:
    types: [opened]
---
Automation agent.`,
			"automation-interval": `---
name: Automation Interval
description: Triggered on interval
on:
  interval:
    types: [daily]
---
Automation agent.`,
			"standard-agent": `---
name: Standard Agent
description: No triggers
---
Standard agent.`,
		}

		spokes := customagenttest.MakeSpokes(t, agents)
		ghTwirp := githubtwirp.NewNoopClient()
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{Token: "token"}}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/automations/testowner/testrepo", http.NoBody)
		rr := httptest.NewRecorder()
		h.listAutomations(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.Unmarshal(rr.Body.Bytes(), &response)
		require.NoError(t, err)
		require.Len(t, response.Agents, 2)

		agentNames := make([]string, len(response.Agents))
		for i, agent := range response.Agents {
			agentNames[i] = agent.Name
		}

		assert.Contains(t, agentNames, "automation-issues")
		assert.Contains(t, agentNames, "automation-interval")
		assert.NotContains(t, agentNames, "standard-agent")
	})

	t.Run("returns empty list when no automations found", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		agents := map[string]string{
			"standard-agent": `---
name: Standard Agent
description: No triggers
---
Standard agent.`,
		}

		spokes := customagenttest.MakeSpokes(t, agents)
		ghTwirp := githubtwirp.NewNoopClient()
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{Token: "token"}}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/automations/testowner/testrepo", http.NoBody)
		rr := httptest.NewRecorder()
		h.listAutomations(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.Unmarshal(rr.Body.Bytes(), &response)
		require.NoError(t, err)
		require.Empty(t, response.Agents)
	})

	t.Run("include_sources applies to automations endpoint", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		repoID := uint64(1)
		orgRepoID := uint64(2)
		repoOwnerID := uint64(3)

		repoAgents := map[string]string{
			"repo-standard": `---
name: Repo Standard
description: No triggers
---
Standard agent.`,
		}
		orgAgents := map[string]string{
			"org-automation": `---
name: Org Automation
description: Triggered by workflow run
on:
  workflow_run:
    types: [completed]
---
Automation agent.`,
		}

		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			if parts[1] == ".github" || parts[1] == ".github-private" {
				id = orgRepoID
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{Repositories: []*repositoriesTwirp.RepositoryListItem{{
				Id:         int64(id),
				Name:       parts[1],
				OwnerId:    int64(repoOwnerID),
				OwnerLogin: parts[0],
			}}}, nil
		}

		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{ID: 123, TokenInfo: &requestctx.TokenInfo{Token: "token"}}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/automations/testowner/testrepo?include_sources=org", http.NoBody)
		rr := httptest.NewRecorder()
		h.listAutomations(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.Unmarshal(rr.Body.Bytes(), &response)
		require.NoError(t, err)
		require.Len(t, response.Agents, 1)
		assert.Equal(t, "org-automation", response.Agents[0].Name)
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
	ffs := map[string]bool{}
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
	h := NewHandler(obsv, ffClient, ghTwirp, svc)

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
	h.getAgent(userInfo, stats.Tags{})(rr, req)

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
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", ".github", "mcp-test-agent", "", customagent.GetAgentOpts{UserID: 123}) // Need to use .github repo to get privileged result
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
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "no-mcp-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		assert.Equal(t, "no-mcp-agent", dto.Name)
		// MCPServers can be nil or empty map when no servers are configured
		if dto.MCPServers != nil {
			assert.Empty(t, dto.MCPServers, "should have empty MCP servers map")
		}
	})

	t.Run("includes model and handoffs properties", func(t *testing.T) {
		agentContent := `---
name: test-agent
description: Agent with model and handoffs
model: gpt-4
handoffs:
  - label: Start Implementation
    agent: implementation
    prompt: Now implement the plan outlined above.
    send: false
---
This agent has model and handoffs configured.`

		agents := map[string]string{
			"test-agent": agentContent,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "test-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		assert.Equal(t, "test-agent", dto.Name)
		assert.Equal(t, "gpt-4", dto.Model)
		assert.NotNil(t, dto.Handoffs)
		assert.Len(t, dto.Handoffs, 1)
		assert.Equal(t, "Start Implementation", dto.Handoffs[0].Label)
		assert.Equal(t, "implementation", dto.Handoffs[0].Agent)
		assert.Equal(t, "Now implement the plan outlined above.", dto.Handoffs[0].Prompt)
		assert.Equal(t, false, dto.Handoffs[0].Send)
	})

	t.Run("includes disable_model_invocation property", func(t *testing.T) {
		agentContent := `---
name: test-agent
description: Agent with disable-model-invocation
disable-model-invocation: true
---
This agent has disable-model-invocation configured.`

		agents := map[string]string{
			"test-agent": agentContent,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "test-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		assert.Equal(t, "test-agent", dto.Name)
		assert.True(t, dto.DisableModelInvocation)
		assert.False(t, dto.InferenceEnabled)
	})

	t.Run("disable_model_invocation defaults to false", func(t *testing.T) {
		agentContent := `---
name: test-agent
description: Agent without disable-model-invocation
---
This agent has no disable-model-invocation configured.`

		agents := map[string]string{
			"test-agent": agentContent,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "test-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		assert.Equal(t, "test-agent", dto.Name)
		assert.False(t, dto.DisableModelInvocation)
		assert.True(t, dto.InferenceEnabled)
	})

	t.Run("includes user_invocable property", func(t *testing.T) {
		agentContent := `---
name: test-agent
description: Agent with user-invocable
user-invocable: false
---
This agent has user-invocable configured.`

		agents := map[string]string{
			"test-agent": agentContent,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "test-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		assert.Equal(t, "test-agent", dto.Name)
		assert.False(t, dto.UserInvocable)
	})

	t.Run("user_invocable defaults to true", func(t *testing.T) {
		agentContent := `---
name: test-agent
description: Agent without user-invocable
---
This agent has no user-invocable configured.`

		agents := map[string]string{
			"test-agent": agentContent,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "test-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		assert.Equal(t, "test-agent", dto.Name)
		assert.True(t, dto.UserInvocable)
	})

	t.Run("github omitted when no permissions or toolsets", func(t *testing.T) {
		agentContent := `---
name: plain-agent
description: Agent without github config
tools: ["*"]
---
No github block expected.`

		agents := map[string]string{"plain-agent": agentContent}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "plain-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		assert.Nil(t, dto.GitHub, "github block should be nil when neither permissions nor toolsets are set")

		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		assert.NotContains(t, string(raw), `"github"`)
	})

	t.Run("github present with permissions only", func(t *testing.T) {
		agentContent := `---
name: perms-agent
description: Agent with permissions
tools: ["*"]
github:
  permissions:
    contents: write
    pull-requests: read
---
Agent with permissions.`

		agents := map[string]string{"perms-agent": agentContent}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "perms-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		require.NotNil(t, dto.GitHub, "github block should be present with permissions")
		assert.Equal(t, "write", dto.GitHub.Permissions["contents"])
		assert.Equal(t, "read", dto.GitHub.Permissions["pull-requests"])
		// metadata is always injected by permissions.New
		assert.Equal(t, "read", dto.GitHub.Permissions["metadata"])
		assert.Nil(t, dto.GitHub.Toolsets)

		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		assert.Contains(t, string(raw), `"github"`)
		assert.Contains(t, string(raw), `"permissions"`)
		assert.NotContains(t, string(raw), `"toolsets"`)
	})

	t.Run("github present with toolsets only", func(t *testing.T) {
		agentContent := `---
name: toolsets-agent
description: Agent with toolsets
tools: ["*"]
github:
  toolsets:
    - code-review
    - pull-requests
---
Agent with toolsets.`

		agents := map[string]string{"toolsets-agent": agentContent}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "toolsets-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		require.NotNil(t, dto.GitHub, "github block should be present with toolsets")
		assert.Empty(t, dto.GitHub.Permissions)
		// Dashes are replaced with underscores in toolset names
		assert.Equal(t, []string{"code_review", "pull_requests"}, dto.GitHub.Toolsets)

		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		assert.Contains(t, string(raw), `"github"`)
		assert.NotContains(t, string(raw), `"permissions"`)
		assert.Contains(t, string(raw), `"toolsets"`)
		assert.Contains(t, string(raw), `"code_review"`)
		assert.Contains(t, string(raw), `"pull_requests"`)
	})

	t.Run("github present with both permissions and toolsets", func(t *testing.T) {
		agentContent := `---
name: full-agent
description: Agent with both permissions and toolsets
tools: ["*"]
github:
  permissions:
    contents: read
    issues: write
  toolsets:
    - issues
    - code-security
---
Agent with both.`

		agents := map[string]string{"full-agent": agentContent}
		spokes := makeSpokesWithRepoSpecificAgents(t, agents, map[string]string{}, uint64(1), uint64(2))
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)

		ctx := context.Background()
		agent, err := svc.GetAgent(ctx, "testowner", "testrepo", "full-agent", "", customagent.GetAgentOpts{UserID: 123})
		require.NoError(t, err)

		dto := makeCustomAgentDTO(agent, true)
		require.NotNil(t, dto.GitHub)
		assert.Equal(t, "read", dto.GitHub.Permissions["contents"])
		assert.Equal(t, "write", dto.GitHub.Permissions["issues"])
		assert.Equal(t, "read", dto.GitHub.Permissions["metadata"])
		assert.Equal(t, []string{"issues", "code_security"}, dto.GitHub.Toolsets)

		// Verify JSON round-trip preserves both
		raw, err := json.Marshal(dto)
		require.NoError(t, err)
		var decoded customAgentDTO
		require.NoError(t, json.Unmarshal(raw, &decoded))
		require.NotNil(t, decoded.GitHub)
		assert.Equal(t, dto.GitHub.Permissions, decoded.GitHub.Permissions)
		assert.Equal(t, dto.GitHub.Toolsets, decoded.GitHub.Toolsets)
	})
}

func TestHandlerGetAgentWithMCPServers(t *testing.T) {
	runTest := func(t *testing.T, repoName string, enterprisePrivileged, isPrivileged bool) {
		t.Helper()
		obsv := observability.NewNoopExporters()
		ffs := map[string]bool{}
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
		h := NewHandler(obsv, ffClient, ghTwirp, svc)
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
		h.getAgent(userInfo, stats.Tags{})(rr, req)

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
		ffs := map[string]bool{}
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
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

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
		h.listAgents(userInfo, stats.Tags{})(rr, req)

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

func TestHandlerListAgentsTargetParameter(t *testing.T) {
	obsv := observability.NewNoopExporters()
	agents := map[string]string{
		"default-agent": `---
name: Default Agent
description: Agent with no target specified
tools: ["tool1"]
---
Default agent.`,
		"github-copilot-agent": `---
name: GitHub Copilot Agent
description: Agent for GitHub Copilot
target: github-copilot
tools: ["tool2"]
---
GitHub Copilot agent.`,
		"vscode-agent": `---
name: VSCode Agent
description: Agent for VSCode
target: vscode
tools: ["tool3"]
---
VSCode agent.`,
	}
	spokes := customagenttest.MakeSpokes(t, agents)
	ghTwirp := githubtwirp.NewNoopClient()

	runTest := func(t *testing.T, targetParam string, ffClient featureflags.Client) []string {
		svc := customagent.NewService(observability.NewNoopExporters(), spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

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

		req := httptest.NewRequestWithContext(ctx, "GET", "/custom-agents/testowner/testrepo?exclude_invalid_config=true&target="+targetParam, nil)
		rr := httptest.NewRecorder()
		h.listAgents(userInfo, stats.Tags{})(rr, req)

		require.Equal(t, http.StatusOK, rr.Code)

		var response listAgentsResponse
		err = json.Unmarshal(rr.Body.Bytes(), &response)
		require.NoError(t, err)

		agentNames := make([]string, len(response.Agents))
		for i, agent := range response.Agents {
			agentNames[i] = agent.Name
		}
		return agentNames
	}

	t.Run("target parameter filters agents correctly for vscode target", func(t *testing.T) {
		ffs := map[string]bool{}
		ffClient := featureflags.NewNoopClient(ffs)
		agentNames := runTest(t, "vscode", ffClient)
		require.Len(t, agentNames, 2)
		assert.Contains(t, agentNames, "default-agent")
		assert.Contains(t, agentNames, "vscode-agent")
		assert.NotContains(t, agentNames, "github-copilot-agent")
	})

	t.Run("target parameter filters agents correctly for github-copilot target", func(t *testing.T) {
		ffs := map[string]bool{}
		ffClient := featureflags.NewNoopClient(ffs)
		agentNames := runTest(t, customagent.TargetGitHubCopilot, ffClient)
		require.Len(t, agentNames, 2)
		assert.Contains(t, agentNames, "default-agent")
		assert.Contains(t, agentNames, "github-copilot-agent")
		assert.NotContains(t, agentNames, "vscode-agent")
	})

	t.Run("target parameter defaults to github-copilot when feature flag is disabled", func(t *testing.T) {
		// Feature flag disabled means default target should be github-copilot
		ffsWithoutDefaultToAll := map[string]bool{
			// CopilotSWEAgentCustomAgentListDefaultToAll is NOT enabled
		}
		ffClientWithoutDefaultToAll := featureflags.NewNoopClient(ffsWithoutDefaultToAll)
		agentNames := runTest(t, "", ffClientWithoutDefaultToAll)
		require.Len(t, agentNames, 2)
		assert.Contains(t, agentNames, "default-agent")
		assert.Contains(t, agentNames, "github-copilot-agent")
		assert.NotContains(t, agentNames, "vscode-agent")
	})

	t.Run("target parameter returns all agents when empty and feature flag is enabled", func(t *testing.T) {
		// When the feature flag is enabled, empty target means "return all agents"
		ffsWithDefaultToAll := map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentListDefaultToAll: true, // Enable so empty target returns all
		}
		ffClientWithDefaultToAll := featureflags.NewNoopClient(ffsWithDefaultToAll)
		agentNames := runTest(t, "", ffClientWithDefaultToAll)
		require.Len(t, agentNames, 3)
		assert.Contains(t, agentNames, "default-agent")
		assert.Contains(t, agentNames, "github-copilot-agent")
		assert.Contains(t, agentNames, "vscode-agent")
	})
}
