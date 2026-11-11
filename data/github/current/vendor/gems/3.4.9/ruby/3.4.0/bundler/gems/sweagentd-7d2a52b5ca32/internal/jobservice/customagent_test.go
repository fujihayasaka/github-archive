package jobservice

import (
	"context"
	"errors"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetCustomAgent(t *testing.T) {
	ctx := context.Background()

	// Create test repository
	createTestRepo := func() *gg.Repository {
		owner := "test-owner"
		name := "test-repo"
		return &gg.Repository{
			Name: &name,
			Owner: &gg.User{
				Login: &owner,
			},
		}
	}

	// Common test setup
	setupService := func(enableCustomAgents, enableCustomAgentParamsThroughAPI bool) *Service {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:  enableCustomAgents,
			featureflags.CopilotSWEAgentCustomAgentAsAPI: enableCustomAgentParamsThroughAPI,
		})
		obsv := observability.NewNoopExporters()
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		twirp.NoopRepositoriesAPI.MockRepositoryResult = &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{
					Id:         456,
					Name:       "test-repo",
					OwnerId:    789,
					OwnerLogin: "test-owner",
				},
			},
		}

		// Create a custom agent service with spokes for testing
		agents := map[string]string{
			"named-agent": `---
name: Named Test Agent
description: A named test agent configuration
tools: named-tool,another-tool
---

You are a named agent that helps with testing.

This is the prompt/instructions section that comes after the YAML frontmatter.`,
		}
		spokes := customagenttest.MakeSpokes(t, agents)
		customAgentSvc := customagent.NewService(obsv, spokes, twirp, ffClient)

		service := New(obsv, ffClient, store, capi, gcf, nil, aq, limiter, exp, customAgentSvc, "test@example.com", nil)
		return service
	}

	t.Run("feature flag disabled - should return default Copilot agent", func(t *testing.T) {
		service := setupService(false, false) // Feature flag disabled
		repo := createTestRepo()

		params := GetCustomAgentParams{
			UserID:   123,
			GHClient: &github.NoopClient{},
			GHRepo:   repo,
			Name:     "test-agent",
		}

		agent, err := service.GetCustomAgent(ctx, params)

		require.NoError(t, err)
		require.NotNil(t, agent)
		// Should return default Copilot agent when feature flag is disabled
		assert.Equal(t, "copilot", agent.Name())
		assert.Equal(t, "test-owner", agent.RepoOwner())
		assert.Equal(t, "test-repo", agent.RepoName())
	})

	t.Run("no specific custom agent configuration - should use default Copilot agent", func(t *testing.T) {
		service := setupService(true, false) // Feature flag enabled
		repo := createTestRepo()

		params := GetCustomAgentParams{
			UserID:   123,
			GHClient: &github.NoopClient{},
			GHRepo:   repo,
			// No Name or Attributes provided
		}

		agent, err := service.GetCustomAgent(ctx, params)

		require.NoError(t, err)
		require.NotNil(t, agent)
		// Should return default Copilot agent when no specific config is provided
		assert.Equal(t, "copilot", agent.Name())
		assert.Equal(t, "test-owner", agent.RepoOwner())
		assert.Equal(t, "test-repo", agent.RepoName())
	})

	t.Run("custom attributes provided and has FF enabled - should create custom agent", func(t *testing.T) {
		service := setupService(true, true) // Feature flag enabled
		repo := createTestRepo()

		attributes := &GetCustomAgentParamsAttributes{
			DisplayName: "Custom Test Agent",
			Description: "A test agent for custom tasks",
			Prompt:      "You are a helpful test assistant",
			Tools:       []string{"test-tool", "another-tool"},
		}

		params := GetCustomAgentParams{
			UserID:     123,
			GHClient:   &github.NoopClient{},
			GHRepo:     repo,
			Attributes: attributes,
		}

		agent, err := service.GetCustomAgent(ctx, params)

		require.NoError(t, err)
		require.NotNil(t, agent)
		// Should return custom agent with the provided attributes
		assert.Equal(t, "custom", agent.Name())
		assert.Equal(t, "test-owner", agent.RepoOwner())
		assert.Equal(t, "test-repo", agent.RepoName())
		assert.Equal(t, "Custom Test Agent", agent.DisplayName())
		assert.Equal(t, "A test agent for custom tasks", agent.Description())
		assert.Equal(t, "You are a helpful test assistant", agent.Prompt())
		assert.Equal(t, []string{"test-tool", "another-tool"}, agent.Tools())
	})

	t.Run("custom attributes provided and has FF disabled - should not create custom agent", func(t *testing.T) {
		service := setupService(true, false) // Feature flag enabled
		repo := createTestRepo()

		attributes := &GetCustomAgentParamsAttributes{
			DisplayName: "Custom Test Agent",
			Description: "A test agent for custom tasks",
			Prompt:      "You are a helpful test assistant",
			Tools:       []string{"test-tool", "another-tool"},
		}

		params := GetCustomAgentParams{
			UserID:     123,
			GHClient:   &github.NoopClient{},
			GHRepo:     repo,
			Attributes: attributes,
		}

		agent, err := service.GetCustomAgent(ctx, params)

		require.NoError(t, err)
		require.NotNil(t, agent)
		// Should return default Copilot agent when no specific config is provided
		assert.Equal(t, "copilot", agent.Name())
		assert.Equal(t, "test-owner", agent.RepoOwner())
		assert.Equal(t, "test-repo", agent.RepoName())
	})

	t.Run("named custom agent provided - should load from repository", func(t *testing.T) {
		// Setup the spokes client to return a mock agent configuration
		// Note: the format needs YAML frontmatter with --- delimiters
		agents := map[string]string{
			"named-agent": `---
name: Named Test Agent
description: A named test agent configuration
tools: named-tool,another-tool
---

You are a named agent that helps with testing.

This is the prompt/instructions section that comes after the YAML frontmatter.`,
		}
		spokes := customagenttest.MakeSpokes(t, agents)

		// Create service with the mock spokes client
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:  true,
			featureflags.CopilotSWEAgentCustomAgentAsAPI: true,
		})
		obsv := observability.NewNoopExporters()
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		// Create a custom agent service with the spokes client that has the test agent
		customAgentSvc := customagent.NewService(obsv, spokes, twirp, ffClient)
		service := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, customAgentSvc, "test@example.com", nil)

		repo := createTestRepo()

		// Create a mock GitHub client that will be used to fetch custom agent config
		mockGH := &github.NoopClient{}

		params := GetCustomAgentParams{
			UserID:   123,
			GHClient: mockGH,
			GHRepo:   repo,
			Name:     "named-agent",
		}

		agent, err := service.GetCustomAgent(ctx, params)

		require.NoError(t, err)
		require.NotNil(t, agent)
		// Should return the named agent loaded from repository
		assert.Equal(t, "named-agent", agent.Name())
		assert.Equal(t, "test-owner", agent.RepoOwner())
		assert.Equal(t, "test-repo", agent.RepoName())
	})

	t.Run("repository error when loading named custom agent - should return error", func(t *testing.T) {
		service := setupService(true, true) // Feature flag enabled
		repo := createTestRepo()

		// Create a GitHub client that will fail when accessing repository
		mockGH := &github.NoopClient{
			MockGetRepository: func(ctx context.Context, owner, repo string) (*gg.Repository, error) {
				return nil, errors.New("repository access failed")
			},
		}

		params := GetCustomAgentParams{
			UserID:   123,
			GHClient: mockGH,
			GHRepo:   repo,
			Name:     "failing-agent",
		}

		agent, err := service.GetCustomAgent(ctx, params)

		require.Error(t, err)
		assert.Nil(t, agent)
	})

	t.Run("nil attributes should not panic", func(t *testing.T) {
		service := setupService(true, true) // Feature flag enabled
		repo := createTestRepo()

		params := GetCustomAgentParams{
			UserID:     123,
			GHClient:   &github.NoopClient{},
			GHRepo:     repo,
			Attributes: nil, // Explicitly nil
		}

		agent, err := service.GetCustomAgent(ctx, params)

		require.NoError(t, err)
		require.NotNil(t, agent)
		// Should fall back to default Copilot agent
		assert.Equal(t, "copilot", agent.Name())
	})
}

func TestGetCustomAgentParamsAttributes(t *testing.T) {
	t.Run("all fields populated", func(t *testing.T) {
		attrs := &GetCustomAgentParamsAttributes{
			DisplayName: "Test Agent",
			Description: "A test description",
			Prompt:      "Test prompt",
			Tools:       []string{"tool1", "tool2"},
		}

		assert.Equal(t, "Test Agent", attrs.DisplayName)
		assert.Equal(t, "A test description", attrs.Description)
		assert.Equal(t, "Test prompt", attrs.Prompt)
		assert.Equal(t, []string{"tool1", "tool2"}, attrs.Tools)
	})

	t.Run("empty fields", func(t *testing.T) {
		attrs := &GetCustomAgentParamsAttributes{}

		assert.Empty(t, attrs.DisplayName)
		assert.Empty(t, attrs.Description)
		assert.Empty(t, attrs.Prompt)
		assert.Nil(t, attrs.Tools)
	})
}

func TestGetCustomAgentParams(t *testing.T) {
	t.Run("all fields populated", func(t *testing.T) {
		repo := &gg.Repository{}
		client := &github.NoopClient{}
		attrs := &GetCustomAgentParamsAttributes{}

		params := GetCustomAgentParams{
			UserID:     123,
			GHClient:   client,
			GHRepo:     repo,
			Name:       "test-agent",
			Attributes: attrs,
		}

		assert.Equal(t, int64(123), params.UserID)
		assert.Equal(t, client, params.GHClient)
		assert.Equal(t, repo, params.GHRepo)
		assert.Equal(t, "test-agent", params.Name)
		assert.Equal(t, attrs, params.Attributes)
	})
}
