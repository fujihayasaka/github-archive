package customagent

import (
	"context"
	"path/filepath"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestService_PrivilegedDirectoryConfiguration(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoName := "test-repo"
	repoOwner := "test-owner"
	repoID := uint64(1)
	orgRepoID := uint64(2)        // .github repo ID
	privateOrgRepoID := uint64(4) // .github-private repo ID
	repoOwnerID := uint64(5)

	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghtwirp := githubtwirp.NewNoopClient()
	setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
	ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
	}

	privilegedAgents := map[string]string{
		"test-agent-priv": `---
name: Privileged Version
description: Agent from privileged directory.
tools: privileged-tool
---

This is the privileged version.`,
	}
	regularAgents := map[string]string{
		"test-agent": `---
name: Regular Version
description: Agent from regular directory.
tools: regular-tool
---

This is the regular version.`,
	}

	t.Run("privileged repo can load agent from PrivilegedDirectory", func(t *testing.T) {
		agentName := "test-agent-priv"
		// Setup agent only in privileged directory
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, privilegedAgents, orgRepoID, orgRepoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(agent sweagentd.CustomAgent) {
			require.NotNil(t, agent)

			// Should return PrivilegedAgent wrapper
			privilegedAgent, ok := agent.(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent, got %T", agent)

			require.Equal(t, agentName, privilegedAgent.Name())
			require.Equal(t, "Privileged Version", privilegedAgent.DisplayName())
			require.Equal(t, "Agent from privileged directory.", privilegedAgent.Description())
			require.Contains(t, privilegedAgent.Tools(), "privileged-tool")
		}

		// Try ResolveByNameAndRepoID
		agentByID, err := service.ResolveByNameAndRepoID(ctx, orgRepoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(agentByID)

		// Try GetAgent
		agent2, err := service.GetAgent(ctx, repoOwner, ".github", agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(agent2)

		// Also try ID variant
		agentByID2, err := service.GetAgentByRepoID(ctx, orgRepoID, agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(agentByID2)
	})

	t.Run("non-privileged repo can load agent from Directory", func(t *testing.T) {
		agentName := "test-agent"
		// Setup agent only in regular directory
		spokes := makeSpokesWithRepoSpecificAgents(t, regularAgents, map[string]string{}, repoID, orgRepoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(agent sweagentd.CustomAgent) {
			require.NotNil(t, agent)

			// Should return regular Agent (not PrivilegedAgent wrapper)
			regularAgent, ok := agent.(*Agent)
			require.True(t, ok, "Expected *Agent, got %T", agent)

			require.Equal(t, agentName, regularAgent.Name())
			require.Equal(t, "Regular Version", regularAgent.DisplayName())
			require.Equal(t, "Agent from regular directory.", regularAgent.Description())
			require.Contains(t, regularAgent.Tools(), "regular-tool")
		}

		// Try ResolveByNameAndRepoID
		agentByID, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(agentByID)

		// Try GetAgent
		agent2, err := service.GetAgent(ctx, repoOwner, "regular-repo", agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(agent2)

		// Also try ID variant
		agentByID2, err := service.GetAgentByRepoID(ctx, repoID, agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(agentByID2)
	})

	t.Run("non-privileged repo cannot load agent from PrivilegedDirectory", func(t *testing.T) {
		agentName := "test-agent-priv"
		// Setup agent only in prv'd dir, but using the repo ID as the regular repo for the privileged set
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, privilegedAgents, repoID, repoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Should not find the agent since regular repo cannot access privileged directory
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)

		// Try GetAgent
		result, err = service.GetAgent(ctx, repoOwner, "regular-repo", agentName, "", GetAgentOpts{UserID: userID})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("ListAgents includes content from both directories based on the repo", func(t *testing.T) {
		spokes := makeSpokesWithRepoSpecificAgents(t, privilegedAgents, regularAgents, repoID, orgRepoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2)

			// Verify both agents are returned
			agentNames := make([]string, len(result))
			for i, agent := range result {
				agentNames[i] = agent.Name()
			}
			require.Contains(t, agentNames, "test-agent-priv")
			require.Contains(t, agentNames, "test-agent")

			// Both should be PrivilegedAgent wrappers since this is a privileged repo
			_, ok := result[0].(*Agent)
			require.True(t, ok, "Expected *Agent, got %T", result[0])
			_, ok = result[1].(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent, got %T", result[1])
		}

		result, err := service.ListAgents(ctx, repoOwner, "regular-repo", ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(resultByID)
	})
}

func TestService_PrefixFunctionality(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoID := uint64(1)
	orgRepoID := uint64(2)
	repoOwnerID := uint64(3)

	ffClient := featureflags.NewNoopClient(map[string]bool{})

	setupGitHubMock := func() *githubtwirp.NoopClient {
		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, "test-repo", repoOwner, repoID, orgRepoID, orgRepoID, repoOwnerID, true)
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
		}
		return ghtwirp
	}

	t.Run("ResolveByNameAndRepoID strips .gh: prefix and finds agent in Directory", func(t *testing.T) {
		agentName := "test-agent"
		prefixedName := ".gh:test-agent"

		// Setup agent in .github/agents directory (Directory, not OrgDirectory)
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(Directory, agentName+Extension), []byte(`---
name: Test Agent
description: Agent from .github/agents folder
tools: test-tool
---

Agent content.`)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := setupGitHubMock()
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Should return the agent without the prefix in its name
			require.Equal(t, agentName, result.Name())
			require.Equal(t, "Test Agent", result.DisplayName())
			require.Equal(t, "Agent from .github/agents folder", result.Description())
		}

		// ResolveByNameAndRepoID should strip the prefix and find the agent in Directory
		resultByID, err := service.ResolveByNameAndRepoID(ctx, orgRepoID, prefixedName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("ResolveByNameAndRepoID without prefix finds agent in OrgDirectory", func(t *testing.T) {
		agentName := "org-agent"

		// Setup agent in .github-agents directory (OrgDirectory)
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(OrgDirectory, agentName+Extension), []byte(`---
name: Org Agent
description: Agent from .github-agents folder
tools: org-tool
---

Org agent content.`)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := setupGitHubMock()
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			require.Equal(t, agentName, result.Name())
			require.Equal(t, "Org Agent", result.DisplayName())
			require.Equal(t, "Agent from .github-agents folder", result.Description())
		}

		// ResolveByNameAndRepoID without prefix should find agent in OrgDirectory
		resultByID, err := service.ResolveByNameAndRepoID(ctx, orgRepoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("GetAgent strips .gh: prefix and finds agent in Directory", func(t *testing.T) {
		agentName := "test-agent"
		prefixedName := ".gh:test-agent"

		// Setup agent in .github/agents directory
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(Directory, agentName+Extension), []byte(`---
name: Test Agent for GetAgent
description: Agent from .github/agents folder
tools: test-tool
---

Agent content for GetAgent.`)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := setupGitHubMock()
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			require.Equal(t, agentName, result.Name())
			require.Equal(t, "Test Agent for GetAgent", result.DisplayName())
			require.Equal(t, "Agent from .github/agents folder", result.Description())
		}

		// GetAgent should strip the prefix and find the agent in Directory
		result, err := service.GetAgent(ctx, repoOwner, ".github", prefixedName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.GetAgentByRepoID(ctx, orgRepoID, prefixedName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("GetAgent without prefix finds agent in OrgDirectory for org repo", func(t *testing.T) {
		agentName := "org-agent-get"

		// Setup agent in .github-agents directory
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(OrgDirectory, agentName+Extension), []byte(`---
name: Org Agent for GetAgent
description: Agent from .github-agents folder
tools: org-tool
---

Org agent content for GetAgent.`)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := setupGitHubMock()
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			require.Equal(t, agentName, result.Name())
			require.Equal(t, "Org Agent for GetAgent", result.DisplayName())
			require.Equal(t, "Agent from .github-agents folder", result.Description())
		}

		// GetAgent without prefix should find agent in OrgDirectory
		result, err := service.GetAgent(ctx, repoOwner, ".github", agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.GetAgentByRepoID(ctx, orgRepoID, agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("ListAgents handles agents in both directories of same repo", func(t *testing.T) {
		// Setup different agents in both Directory (.github/agents) and OrgDirectory (.github-agents)
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(Directory, "dir-agent"+Extension), []byte(`---
name: Agent from Directory
description: Agent from .github/agents folder
tools: dir-tool
---

Directory agent.`)),
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(OrgDirectory, "org-agent"+Extension), []byte(`---
name: Agent from OrgDirectory
description: Agent from .github-agents folder
tools: org-tool
---

OrgDirectory agent.`)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := setupGitHubMock()
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2, "should return both agents")

			// Verify dir-agent has prefix in its name
			var hasPrefixedDirAgent bool
			for _, agent := range result {
				if agent.Name() == forceDotGitHubAgentsDirPrefix+"dir-agent" {
					hasPrefixedDirAgent = true
					break
				}
			}
			require.True(t, hasPrefixedDirAgent, "dir-agent should have prefix in its name")

			// Verify both agents are present (with or without prefix)
			agentNames := make(map[string]sweagentd.CustomAgent)
			for _, agent := range result {
				// Strip prefix if present to get base name
				baseName := strings.TrimPrefix(agent.Name(), forceDotGitHubAgentsDirPrefix)
				agentNames[baseName] = agent
			}

			require.Contains(t, agentNames, "dir-agent")
			require.Contains(t, agentNames, "org-agent")

			require.Equal(t, "Agent from Directory", agentNames["dir-agent"].DisplayName())
			require.Equal(t, "Agent from OrgDirectory", agentNames["org-agent"].DisplayName())
		}

		// ListAgents should return both agents
		result, err := service.ListAgents(ctx, repoOwner, ".github", ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.ListAgentsByRepoID(ctx, orgRepoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("ListAgents does not add prefix when repo only has Directory agents", func(t *testing.T) {
		agentName := "dir-only-agent"

		// Setup agent only in Directory (.github/agents)
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(Directory, agentName+Extension), []byte(`---
name: Directory Only Agent
description: Agent only in .github/agents folder
tools: dir-tool
---

Directory only agent.`)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := setupGitHubMock()
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 1)

			// Should not have prefix since there's no OrgDirectory agent
			require.Equal(t, agentName, result[0].Name())
			require.Equal(t, "Directory Only Agent", result[0].DisplayName())
		}

		result, err := service.ListAgents(ctx, repoOwner, ".github", ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.ListAgentsByRepoID(ctx, orgRepoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("ListAgents does not add prefix when repo only has OrgDirectory agents", func(t *testing.T) {
		agentName := "org-only-agent"

		// Setup agent only in OrgDirectory (.github-agents)
		options := []spokestest.ClientOption{
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(OrgDirectory, agentName+Extension), []byte(`---
name: OrgDirectory Only Agent
description: Agent only in .github-agents folder
tools: org-tool
---

OrgDirectory only agent.`)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := setupGitHubMock()
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 1)

			// Should not have prefix
			require.Equal(t, agentName, result[0].Name())
			require.Equal(t, "OrgDirectory Only Agent", result[0].DisplayName())
		}

		result, err := service.ListAgents(ctx, repoOwner, ".github", ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.ListAgentsByRepoID(ctx, orgRepoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("indexedAgents treats .gh:name and name as duplicates", func(t *testing.T) {
		agentName := "duplicate-agent"

		// Create two agents with the same base name, one with prefix
		agent1 := &Agent{
			metadata: Metadata{
				Name: agentName,
			},
			cfg: &Config{
				attributes: ConfigAttributes{
					DisplayName: "Agent without prefix",
					Description: "Test description",
				},
			},
		}
		agent2 := &Agent{
			metadata: Metadata{
				Name: ".gh:" + agentName,
			},
			cfg: &Config{
				attributes: ConfigAttributes{
					DisplayName: "Agent with prefix",
					Description: "Test description",
				},
			},
		}

		index := make(map[string]struct{})
		agents := []sweagentd.CustomAgent{agent1, agent2}

		// indexedAgents should filter out the duplicate
		unique := indexedAgents(index, agents)

		// Should only return one agent (the first one encountered)
		require.Len(t, unique, 1)
		require.Equal(t, agentName, unique[0].Name())
	})

	t.Run("prefix functionality works with GetAgent to select directory", func(t *testing.T) {
		agentName := "directory-agent"

		// Setup agent with same name in both directories of .github repo
		options := []spokestest.ClientOption{
			// Agent in Directory (.github/agents)
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(Directory, agentName+Extension), []byte(`---
name: Agent from Directory
description: Agent from .github/agents folder
tools: dir-tool
---

Directory agent.`)),
			// Agent in OrgDirectory (agents)
			spokestest.WithRepoBlob(orgRepoID, filepath.Join(OrgDirectory, agentName+Extension), []byte(`---
name: Agent from OrgDirectory
description: Agent from .github-agents folder
tools: org-tool
---

OrgDirectory agent.`)),
		}
		spokes := spokestest.NewClient(t, options...)

		ghtwirp := setupGitHubMock()
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// GetAgent without prefix on org repo should find agent in OrgDirectory (default for org repos)
		result, err := service.GetAgent(ctx, repoOwner, ".github", agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		require.Equal(t, "Agent from OrgDirectory", result.DisplayName())

		// Also try ID variant
		resultByID, err := service.GetAgentByRepoID(ctx, orgRepoID, agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		require.Equal(t, "Agent from OrgDirectory", resultByID.DisplayName())

		// GetAgent with .gh: prefix should find agent in Directory
		result, err = service.GetAgent(ctx, repoOwner, ".github", ".gh:"+agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		require.Equal(t, "Agent from Directory", result.DisplayName())

		// Also try ID variant
		resultByID, err = service.GetAgentByRepoID(ctx, orgRepoID, ".gh:"+agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		require.Equal(t, "Agent from Directory", resultByID.DisplayName())
	})
}

// Currently this test focuses on feature flags, but is set up for the future if we end up needing to add policy checks
func TestService_PrivilegedRepoLevelAgents(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"
	agentName := "test-agent"
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	// Setup agent in repository
	repoAgents := map[string]string{
		agentName: `---
name: Test Agent
description: A test agent
tools: test-tool
---

You are a test agent.`,
	}

	t.Run("GetAgent returns PrivilegedAgent when isPrivilegedRepo is true", func(t *testing.T) {
		// Use .github repo like the existing GetAgent tests
		orgRepoID := uint64(2)
		orgAgents := map[string]string{
			agentName: `---
name: Test Agent
description: A test agent
tools: test-tool
---

You are a test agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, orgAgents, 0, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPrivilegedRepo: true,
		})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Should return PrivilegedAgent wrapper - org repos are always privileged
			privilegedAgent, ok := result.(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

			require.Equal(t, agentName, privilegedAgent.Name())
			require.Equal(t, "Test Agent", privilegedAgent.DisplayName())
			require.Equal(t, "A test agent", privilegedAgent.Description())
			require.Equal(t, int64(orgRepoID), privilegedAgent.RepoID())
		}

		result, err := service.GetAgent(ctx, repoOwner, ".github", agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.GetAgentByRepoID(ctx, orgRepoID, agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("GetAgent returns PrivilegedAgent for org repo even when isPrivilegedRepo is false", func(t *testing.T) {
		// Use .github repo - org repos are always privileged regardless of feature flag
		orgRepoID := uint64(2)
		orgAgents := map[string]string{
			agentName: `---
name: Test Agent
description: A test agent
tools: test-tool
---

You are a test agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, orgAgents, 0, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPrivilegedRepo: false,
		})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Should return PrivilegedAgent wrapper - org repos are always privileged
			privilegedAgent, ok := result.(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent even with feature flag disabled, got %T", result)

			require.Equal(t, agentName, privilegedAgent.Name())
			require.Equal(t, "Test Agent", privilegedAgent.DisplayName())
			require.Equal(t, "A test agent", privilegedAgent.Description())
			require.Equal(t, int64(orgRepoID), privilegedAgent.RepoID())
		}

		result, err := service.GetAgent(ctx, repoOwner, ".github", agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.GetAgentByRepoID(ctx, orgRepoID, agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("ResolveByNameAndRepoID returns PrivilegedAgent when isPrivilegedRepo is true", func(t *testing.T) {
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, 0)
		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, false)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPrivilegedRepo: true,
		})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Should return PrivilegedAgent wrapper when feature flag is enabled
			privilegedAgent, ok := result.(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

			require.Equal(t, agentName, privilegedAgent.Name())
			require.Equal(t, "Test Agent", privilegedAgent.DisplayName())
		}

		resultByID, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("ResolveByNameAndRepoID returns Agent when isPrivilegedRepo is false", func(t *testing.T) {
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, 0)
		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, false)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPrivilegedRepo: false,
		})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Should return regular Agent when feature flag is disabled
			agent, ok := result.(*Agent)
			require.True(t, ok, "Expected *Agent, got %T", result)

			require.Equal(t, agentName, agent.Name())
			require.Equal(t, "Test Agent", agent.DisplayName())
		}

		resultByID, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("ListAgents includes PrivilegedAgent when isPrivilegedRepo is true", func(t *testing.T) {
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, 0)
		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, false)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPrivilegedRepo: true,
		})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 1)

			// Agent from privileged repo should be PrivilegedAgent
			privilegedAgent, ok := result[0].(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent, got %T", result[0])

			require.Equal(t, agentName, privilegedAgent.Name())
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:      userID,
			DedupeNames: true,
		})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:      userID,
			DedupeNames: true,
		})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("ListAgents includes Agent when isPrivilegedRepo is false", func(t *testing.T) {
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, 0)
		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, false)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPrivilegedRepo: false,
		})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 1)

			// Agent from non-privileged repo should be regular Agent
			agent, ok := result[0].(*Agent)
			require.True(t, ok, "Expected *Agent, got %T", result[0])

			require.Equal(t, agentName, agent.Name())
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:      userID,
			DedupeNames: true,
		})
		require.NoError(t, err)
		verify(result)

		// Also try ID variant
		resultByID, err := service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:      userID,
			DedupeNames: true,
		})
		require.NoError(t, err)
		verify(resultByID)
	})

	t.Run("Org repos always return PrivilegedAgent regardless of isPrivilegedRepo", func(t *testing.T) {
		orgRepoID := uint64(2)
		orgAgents := map[string]string{
			agentName: `---
name: Org Agent
description: Organization agent
tools: org-tool
---

Org agent content.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}

		// Test with feature flag disabled - org repos should still return PrivilegedAgent
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentPrivilegedRepo: false,
		})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Org repos always return PrivilegedAgent
			privilegedAgent, ok := result.(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent for org repo even with feature flag disabled, got %T", result)

			require.Equal(t, agentName, privilegedAgent.Name())
			require.Equal(t, "Org Agent", privilegedAgent.DisplayName())
		}

		// Test ResolveByNameAndRepoID
		resultByID, err := service.ResolveByNameAndRepoID(ctx, orgRepoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(resultByID)

		// Test GetAgent
		result2, err := service.GetAgent(ctx, repoOwner, ".github", agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(result2)

		// Also try ID variant
		resultByID2, err := service.GetAgentByRepoID(ctx, orgRepoID, agentName, "", GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		verify(resultByID2)
	})
}
