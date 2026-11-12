package customagent

import (
	"context"
	"errors"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestService_ListAgents(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"

	// Setup different repository IDs to distinguish between repo and org
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	t.Run("returns only repo agents when no org agents exist", func(t *testing.T) {
		repoAgents := map[string]string{
			"repo-agent1": `---
name: Repo Agent 1
description: First repository agent
tools: tool1,tool2
---

You are a repository-level agent.`,
			"repo-agent2": `---
name: Repo Agent 2
description: Second repository agent
tools: tool3
---

Another repository agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, false)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 2)
		agentNames := extractAgentNames(result)
		require.Contains(t, agentNames, "repo-agent1")
		require.Contains(t, agentNames, "repo-agent2")
		verifyAgentRepoIDs(t, result, int64(repoID))
		verifyAgentRepoOwnerIDs(t, result, int64(repoOwnerID))

		// Test ListAgentsByRepoID as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 2)
		agentNames = extractAgentNames(result)
		require.Contains(t, agentNames, "repo-agent1")
		require.Contains(t, agentNames, "repo-agent2")
		verifyAgentRepoIDs(t, result, int64(repoID))
		verifyAgentRepoOwnerIDs(t, result, int64(repoOwnerID))
	})

	t.Run("returns only org agents when no repo agents exist", func(t *testing.T) {
		// Add a dummy repo agent to prevent ErrNoAgentsFound on primary repo
		repoAgents := map[string]string{
			"dummy-agent": `---
name: Dummy Agent
description: Placeholder to prevent empty repo error
tools: dummy-tool
---

This is a dummy agent to prevent ErrNoAgentsFound.`,
		}

		// Only setup org agents
		orgAgents := map[string]string{
			"org-agent1": `---
name: Org Agent 1
description: First organization agent
tools: org-tool1
---

You are an organization-level agent.`,
			"org-agent2": `---
name: Org Agent 2
description: Second organization agent
tools: org-tool2
---

Another organization agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 3) // 1 repo agent + 2 org agents
			// Verify agents are returned (both repo and org)
			agentNames := make([]string, len(result))
			for i, agent := range result {
				agentNames[i] = agent.Name()
			}
			require.Contains(t, agentNames, "dummy-agent")
			require.Contains(t, agentNames, "org-agent1")
			require.Contains(t, agentNames, "org-agent2")
			agentRepoIDs := make(map[int64]bool)
			for _, agent := range result {
				id := agent.RepoID()
				if !agentRepoIDs[id] {
					agentRepoIDs[id] = true
				}
			}
			require.Len(t, agentRepoIDs, 2)
			require.Equal(t, true, agentRepoIDs[int64(repoID)])
			require.Equal(t, true, agentRepoIDs[int64(orgRepoID)])
			agentRepoOwnerIDs := make(map[int64]bool)
			for _, agent := range result {
				id := agent.RepoOwnerID()
				if !agentRepoOwnerIDs[id] {
					agentRepoOwnerIDs[id] = true
				}
			}
			require.Len(t, agentRepoOwnerIDs, 1)
			require.Equal(t, true, agentRepoOwnerIDs[int64(repoOwnerID)])
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Test ID variation as well
		result2, err := service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result2)
	})

	t.Run("combines repo and org agents with repo agents taking precedence", func(t *testing.T) {
		repoAgents := map[string]string{
			"shared-agent": `---
name: Shared Agent (Repo)
description: Repository version of shared agent
tools: repo-tool
---

This is the repo version and should take precedence.`,
			"repo-only": `---
name: Repo Only Agent
description: Only exists in repository
tools: repo-exclusive
---

This agent only exists in the repository.`,
		}

		orgAgents := map[string]string{
			"shared-agent": `---
name: Shared Agent (Org)
description: Organization version of shared agent
tools: org-tool
---

This is the org version and should NOT be returned.`,
			"org-only": `---
name: Org Only Agent
description: Only exists in organization
tools: org-exclusive
---

This agent only exists in the organization.`,
		}

		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 3)

			agentNames := extractAgentNames(result)
			agentDescriptions := make(map[string]string)
			for _, agent := range result {
				agentDescriptions[agent.Name()] = agent.Description()
			}

			require.Contains(t, agentNames, "shared-agent")
			require.Contains(t, agentNames, "repo-only")
			require.Contains(t, agentNames, "org-only")

			require.Equal(t, "Repository version of shared agent", agentDescriptions["shared-agent"])
			require.Equal(t, "Only exists in repository", agentDescriptions["repo-only"])
			require.Equal(t, "Only exists in organization", agentDescriptions["org-only"])

			verifyAgentRepoIDs(t, result, int64(repoID), int64(orgRepoID))
			verifyAgentRepoOwnerIDs(t, result, int64(repoOwnerID))
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Check ListAgentsByRepoID as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("ListAgents returns ErrRepoNotFound when repository not found", func(t *testing.T) {
		repoID := uint64(999)

		spokes := makeSpokesWithAgents(t, map[string]string{})

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
			return &repositoriesTwirp.FindRepositoriesResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{},
			}, nil
		}
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{},
			}, nil
		}
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, "org", "repo", ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.True(t, errors.Is(err, ErrRepoNotFound))
		require.Nil(t, result)

		// Test list by ID as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.True(t, errors.Is(err, ErrRepoNotFound))
		require.Nil(t, result)
	})

	t.Run("ListAgents returns ErrNoAgentsFound when repository access fails", func(t *testing.T) {
		spokes := makeSpokesWithAgents(t, map[string]string{})

		// Simulate access denied for the for primary repo
		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: false,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.True(t, errors.Is(err, ErrNoAgentsFound))
		require.Len(t, result, 0)

		// Also test by ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.True(t, errors.Is(err, ErrNoAgentsFound))
		require.Len(t, result, 0)
	})

	t.Run("ListAgents returns ErrNoAgentsFound error when org repository access fails and no repos-level agents exist", func(t *testing.T) {
		// Setup some repo agents
		agents := map[string]string{
			"repo-agent": `---
name: Repo Agent
description: Repository agent
---

A repository agent.`,
		}
		spokes := makeSpokesWithAgents(t, agents)
		// Simulate access denied for the for org repo
		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
		ghtwirp.NoopSweagentdAPI.MockAuthorizeCustomAgentRepoForUser = func(ctx context.Context, req *sweagentdv1.AuthorizeCustomAgentRepoForUserRequest) (*sweagentdv1.AuthorizeCustomAgentRepoForUserResponse, error) {
			if req.RepositoryId == orgRepoID {
				return &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
					CanAccess: true,
				}, nil
			}
			return &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
				CanAccess: false,
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.True(t, errors.Is(err, ErrNoAgentsFound))
		require.Len(t, result, 0)

		// Test by ID variation as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.True(t, errors.Is(err, ErrNoAgentsFound))
		require.Len(t, result, 0)
	})

	t.Run("ListAgents returns ErrNoAgentsFound when no agents exist in repo or org", func(t *testing.T) {
		// Empty spokes - no agents configured
		spokes := makeSpokesWithAgents(t, map[string]string{})

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.True(t, errors.Is(err, ErrNoAgentsFound))
		require.Len(t, result, 0)

		// Test by ID variation as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.True(t, errors.Is(err, ErrNoAgentsFound))
		require.Len(t, result, 0)
	})

	t.Run("ListAgents preserves target values correctly", func(t *testing.T) {
		// Setup agents with mixed target values in repo only
		repoAgents := map[string]string{
			"default-agent": `---
name: Default Agent
description: Agent with no target specified
tools: tool1
---
Default agent.`,
			"github-copilot-agent": `---
name: GitHub Copilot Agent
description: Agent for GitHub Copilot
target: github-copilot
tools: tool2
---
GitHub Copilot agent.`,
		}

		spokes := makeSpokesWithAgents(t, repoAgents)
		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2)

			// Verify target values are preserved correctly
			agentTargets := make(map[string]string)
			for _, agent := range result {
				agentTargets[agent.Name()] = agent.Target()
			}

			require.Equal(t, "", agentTargets["default-agent"])
			require.Equal(t, TargetGitHubCopilot, agentTargets["github-copilot-agent"])
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Test ListAgentsByRepoID as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("ListAgents handles twirp NotFound error for enterprise agents gracefully", func(t *testing.T) {
		agentName := "test-agent"
		// Setup agent in repository
		repoAgents := map[string]string{
			agentName: `---
name: Test Agent
description: A test agent in repository
tools: repo-tool
---

You are a repository-level test agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		// Setup mock to return twirp.NotFound for EnterpriseAgents
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Should still find the repository agent even though enterprise agents returned NotFound
			agent, ok := result[0].(*Agent)
			require.True(t, ok, "Expected *Agent, got %T", result)
			require.Equal(t, agentName, agent.Name())
			require.Equal(t, "Test Agent", agent.DisplayName())
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Test ListAgentsByRepoID as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("ListAgents handles non-NotFound twirp errors for enterprise agents", func(t *testing.T) {
		// Setup empty repository
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.InternalError("internal server error")
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.Error(t, err)
		require.Nil(t, result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.Error(t, err)
		require.Nil(t, result)
	})
}

func TestService_ListAgentsExcludeInvalidConfig(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"

	t.Run("excludeInvalidConfig=true filters out invalid configurations", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup agents with mix of valid and invalid configurations
		repoAgents := map[string]string{
			"valid-agent": `---
name: Valid Agent
description: A valid agent
---

You are a valid agent.`,
			"invalid-no-desc": `---
name: No Description
---

Invalid agent.`,
		}

		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, orgRepoID)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{CanAccess: true}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:               userID,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		require.Len(t, result, 1, "expected only valid agent to be returned")
		require.Equal(t, "Valid Agent", result[0].DisplayName())

		// Test ListAgentsByRepoID as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:               userID,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		require.Len(t, result, 1, "expected only valid agent to be returned")
		require.Equal(t, "Valid Agent", result[0].DisplayName())
	})

	t.Run("excludeInvalidConfig=false includes invalid configurations", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup agents with mix of valid and invalid configurations
		repoAgents := map[string]string{
			"valid-agent": `---
name: Valid Agent
description: A valid agent
---

You are a valid agent.`,
			"invalid-no-desc": `---
name: No Description
---

Invalid agent.`,
		}

		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, orgRepoID)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{CanAccess: true}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2, "expected all agents (valid + invalid) to be returned")

			// Verify that the valid agent doesn't have an error
			validAgent := findAgentByName(result, "Valid Agent")
			require.NotNil(t, validAgent, "expected to find valid agent")
			require.Empty(t, validAgent.ConfigError(), "valid agent should not have config error")

			// Verify that invalid agents have config errors
			invalidNoDescAgent := findAgentByName(result, "No Description")
			require.NotNil(t, invalidNoDescAgent, "expected to find agent with missing description")
			require.NotEmpty(t, invalidNoDescAgent.ConfigError(), "agent with missing description should have config error")
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Test ListAgentsByRepoID as well
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("excludeInvalidConfig behavior is consistent across org and repo agents", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup invalid agent in repo and valid agent in org
		repoAgents := map[string]string{
			"invalid-repo": `---
name: Invalid Repo
---

Invalid repo agent.`,
		}

		orgAgents := map[string]string{
			"valid-org": `---
name: Valid Org Agent
description: A valid org agent
---

Valid org agent.`,
			"invalid-org": `---
name: Invalid Org
---

Missing description.`,
		}

		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{CanAccess: true}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test with excludeInvalidConfig=true
		resultExclude, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:               userID,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		require.Len(t, resultExclude, 1, "expected only valid org agent")
		require.Equal(t, "Valid Org Agent", resultExclude[0].DisplayName())

		// Test with excludeInvalidConfig=false
		resultInclude, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, resultInclude, 3, "expected all agents from both repo and org")

		// Test with excludeInvalidConfig=true for ID variation
		resultExclude, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:               userID,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		require.Len(t, resultExclude, 1, "expected only valid org agent")
		require.Equal(t, "Valid Org Agent", resultExclude[0].DisplayName())

		// Test with excludeInvalidConfig=false for ID variation
		resultInclude, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, resultInclude, 3, "expected all agents from both repo and org")
	})
}

func TestService_ListAgentsDedupeNames(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	setupMocks := func(t *testing.T, repoAgents, orgAgents map[string]string) (*Service, *githubtwirp.NoopClient) {
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)
		return service, ghtwirp
	}

	// Setup agents with duplicates across repo and org
	repoAgents := map[string]string{
		"agent1": `---
name: Agent 1 (Repo)
description: First agent from repository
---
Content.`,
		"agent2": `---
name: Agent 2 (Repo)
description: Second agent from repository
---
Content.`,
	}
	orgAgents := map[string]string{
		"agent1": `---
name: Agent 1 (Org)
description: First agent from organization
---
Content.`,
		"agent3": `---
name: Agent 3 (Org)
description: Third agent from organization
---
Content.`,
	}
	service, _ := setupMocks(t, repoAgents, orgAgents)

	t.Run("dedupeNames=true removes duplicate agent names across repos", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 3, "should return 3 unique agents when dedupeNames=true")
			agentNames := make([]string, len(result))
			agentDescriptions := make(map[string]string)
			for i, agent := range result {
				agentNames[i] = agent.Name()
				agentDescriptions[agent.Name()] = agent.Description()
			}

			require.Contains(t, agentNames, "agent1")
			require.Contains(t, agentNames, "agent2")
			require.Contains(t, agentNames, "agent3")

			// agent1 should be the repo version (first encountered)
			require.Equal(t, "First agent from repository", agentDescriptions["agent1"])
			require.Equal(t, "Second agent from repository", agentDescriptions["agent2"])
			require.Equal(t, "Third agent from organization", agentDescriptions["agent3"])
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("dedupeNames=false keeps duplicate agent names across repos", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.GreaterOrEqual(t, len(result), 4, "should return at least 4 agents when dedupeNames=false")

			// Should have agent1 from both repo and org (and possibly .github-private)
			agent1Count := 0
			agent1Descriptions := make([]string, 0)
			allAgentNames := make(map[string]bool)

			for _, agent := range result {
				allAgentNames[agent.Name()] = true
				if agent.Name() == "agent1" {
					agent1Count++
					agent1Descriptions = append(agent1Descriptions, agent.Description())
				}
			}

			require.GreaterOrEqual(t, agent1Count, 2, "should have at least 2 instances of agent1")
			require.Contains(t, agent1Descriptions, "First agent from repository")
			require.Contains(t, agent1Descriptions, "First agent from organization")

			// Should also have agent2 and agent3
			require.True(t, allAgentNames["agent2"], "should have agent2")
			require.True(t, allAgentNames["agent3"], "should have agent3")
		}

		// Only include repo and org sources
		// Note: org includes both .github and .github-private repos which may have the same agent
		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    false,
			IncludeSources: []string{SourceTypeRepo, SourceTypeOrg},
		})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    false,
			IncludeSources: []string{SourceTypeRepo, SourceTypeOrg},
		})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("dedupeNames=true with only repo source returns only repo agents", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2, "should return only 2 repo agents")

			agentNames := make([]string, len(result))
			agentDescriptions := make(map[string]string)
			for i, agent := range result {
				agentNames[i] = agent.Name()
				agentDescriptions[agent.Name()] = agent.Description()
			}

			require.Contains(t, agentNames, "agent1")
			require.Contains(t, agentNames, "agent2")
			require.NotContains(t, agentNames, "agent3")

			// Both should be repo versions
			require.Equal(t, "First agent from repository", agentDescriptions["agent1"])
			require.Equal(t, "Second agent from repository", agentDescriptions["agent2"])
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeRepo},
		})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeRepo},
		})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("dedupeNames=false with only org source returns only org agents", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.GreaterOrEqual(t, len(result), 2, "should return at least 2 org agents")

			agentNames := make(map[string]bool)
			for _, agent := range result {
				agentNames[agent.Name()] = true
			}

			require.True(t, agentNames["agent1"], "should have agent1 from org")
			require.True(t, agentNames["agent3"], "should have agent3 from org")
			require.False(t, agentNames["agent2"], "should not have agent2 (only in repo)")
		}

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    false,
			IncludeSources: []string{SourceTypeOrg},
		})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    false,
			IncludeSources: []string{SourceTypeOrg},
		})
		require.NoError(t, err)
		verify(result)
	})
}

func TestService_ListAgentsTargetFiltering(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoName := "test-repo"
	repoOwner := "test-owner"
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	ghtwirp := githubtwirp.NewNoopClient()
	setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
	ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
	}

	// Setup agents with mixed target values
	repoAgents := map[string]string{
		"default-agent": `---
name: Default Agent
description: Agent with no target specified
tools: tool1
---
Default agent.`,
		"github-copilot-agent": `---
name: GitHub Copilot Agent
description: Agent for GitHub Copilot
target: github-copilot
tools: tool2
---
GitHub Copilot agent.`,
		"vscode-agent": `---
name: VSCode Agent
description: Agent for VSCode
target: vscode
tools: tool3
---
VSCode agent.`,
	}
	spokes := makeSpokesWithAgents(t, repoAgents)

	t.Run("ListAgents with empty target returns all targets", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 3, "should return all targets")

			agentNames := make([]string, len(result))
			for i, agent := range result {
				agentNames[i] = agent.Name()
			}
			require.Contains(t, agentNames, "default-agent")
			require.Contains(t, agentNames, "vscode-agent")
			require.Contains(t, agentNames, "github-copilot-agent")
		}

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)
		result, err := service.ListAgents(ctx, repoOwner, ".github", ListAgentsOpts{
			UserID:               userID,
			Target:               TargetEmpty,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:               userID,
			Target:               TargetEmpty,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("ListAgents with vscode target returns agents with vscode or all targets", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2, "should return agents with vscode and all targets (blank) when target is vscode")

			agentNames := make([]string, len(result))
			for i, agent := range result {
				agentNames[i] = agent.Name()
			}
			require.Contains(t, agentNames, "default-agent")
			require.Contains(t, agentNames, "vscode-agent")
			require.NotContains(t, agentNames, "github-copilot-agent")
		}

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)
		result, err := service.ListAgents(ctx, repoOwner, ".github", ListAgentsOpts{
			UserID:               userID,
			Target:               TargetVSCode,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:               userID,
			Target:               TargetVSCode,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("ListAgents with github-copilot target returns agents with github-copilot or all targets", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2, "should return agents with github-copilot and all targets (blank) when target is github-copilot")

			// Verify both github-copilot and default agents are returned
			agentNames := make([]string, len(result))
			for i, agent := range result {
				agentNames[i] = agent.Name()
			}
			require.Contains(t, agentNames, "default-agent")
			require.Contains(t, agentNames, "github-copilot-agent")
			require.NotContains(t, agentNames, "vscode-agent")
		}

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)
		result, err := service.ListAgents(ctx, repoOwner, ".github", ListAgentsOpts{
			UserID:               userID,
			Target:               TargetGitHubCopilot,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:               userID,
			Target:               TargetGitHubCopilot,
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
		})
		require.NoError(t, err)
		verify(result)
	})
}

func TestService_ListAgentsIncludeSources(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	setupMocks := func(t *testing.T, repoAgents, orgAgents map[string]string) (*Service, *githubtwirp.NoopClient) {
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)
		return service, ghtwirp
	}

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

	t.Run("include only repo agents", func(t *testing.T) {
		service, _ := setupMocks(t, repoAgents, orgAgents)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeRepo},
		})
		require.NoError(t, err)
		require.Len(t, result, 1)
		require.Equal(t, "repo-agent", result[0].Name())

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeRepo},
		})
		require.NoError(t, err)
		require.Len(t, result, 1)
		require.Equal(t, "repo-agent", result[0].Name())
	})

	t.Run("include only org agents", func(t *testing.T) {
		service, _ := setupMocks(t, repoAgents, orgAgents)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeOrg},
		})
		require.NoError(t, err)
		require.Len(t, result, 1)
		require.Equal(t, "org-agent", result[0].Name())

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeOrg},
		})
		require.NoError(t, err)
		require.Len(t, result, 1)
		require.Equal(t, "org-agent", result[0].Name())
	})

	t.Run("include repo and org agents", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2)

			agentNames := make([]string, len(result))
			for i, agent := range result {
				agentNames[i] = agent.Name()
			}
			require.Contains(t, agentNames, "repo-agent")
			require.Contains(t, agentNames, "org-agent")
		}

		service, _ := setupMocks(t, repoAgents, orgAgents)
		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeRepo, SourceTypeOrg},
		})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeRepo, SourceTypeOrg},
		})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("default includes all sources (nil)", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2)

			agentNames := make([]string, len(result))
			for i, agent := range result {
				agentNames[i] = agent.Name()
			}
			require.Contains(t, agentNames, "repo-agent")
			require.Contains(t, agentNames, "org-agent")
		}

		service, _ := setupMocks(t, repoAgents, orgAgents)
		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("default includes all sources (empty array)", func(t *testing.T) {
		verify := func(result []sweagentd.CustomAgent) {
			require.Len(t, result, 2)

			agentNames := make([]string, len(result))
			for i, agent := range result {
				agentNames[i] = agent.Name()
			}
			require.Contains(t, agentNames, "repo-agent")
			require.Contains(t, agentNames, "org-agent")
		}

		service, _ := setupMocks(t, repoAgents, orgAgents)
		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{},
		})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ListAgentsByRepoID(ctx, repoID, ListAgentsOpts{
			UserID:         userID,
			DedupeNames:    true,
			IncludeSources: []string{},
		})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("twirpRepoProvider error handling in service context", func(t *testing.T) {
		// Test that errors from twirpRepoProvider are handled correctly by the service
		spokes := makeSpokesWithAgents(t, map[string]string{
			"repo-agent": `---
name: Repo Agent
---
Content.`,
		})

		// Use error-returning noop client to simulate twirp failures
		ghtwirp := githubtwirp.NewNoopClientWithRepositoryError()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return nil, twirp.InternalError("some unexpected error")
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, repoOwner, repoName, ListAgentsOpts{UserID: userID, DedupeNames: true})
		require.Error(t, err)
		require.Nil(t, result)
	})
}
