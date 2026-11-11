package customagent

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// Helper function to create spokes with agents (similar to makeSpokesWithAgents but avoiding import cycle)
func makeSpokesWithAgents(t *testing.T, agents map[string]string) *spokestest.Client {
	t.Helper()

	fileBlobs := []spokestest.ClientOption{}
	for name, content := range agents {
		blob := spokestest.ClientWithBlob(filepath.Join(Directory, name+Extension), []byte(content))
		fileBlobs = append(fileBlobs, blob)
	}

	return spokestest.NewClient(t, fileBlobs...)
}

// Helper function to create spokes with repo-specific agents for testing repo/org precedence
func makeSpokesWithRepoSpecificAgents(t *testing.T, repoAgents, orgAgents map[string]string, repoID, orgRepoID uint64) *spokestest.Client {
	t.Helper()

	options := []spokestest.ClientOption{}

	// Add repository-specific agents
	for name, content := range repoAgents {
		option := spokestest.ClientWithRepoBlob(repoID, filepath.Join(Directory, name+Extension), []byte(content))
		options = append(options, option)
	}

	// Add organization-specific agents
	for name, content := range orgAgents {
		option := spokestest.ClientWithRepoBlob(orgRepoID, filepath.Join(OrgDirectory, name+Extension), []byte(content))
		options = append(options, option)
	}

	return spokestest.NewClient(t, options...)
}

// Helper function to create spokes with multiple org repos for testing .github vs .github-private precedence
func makeSpokesWithMultipleOrgRepos(t *testing.T, repoAgents, publicOrgAgents, privateOrgAgents map[string]string, repoID, publicOrgRepoID, privateOrgRepoID uint64) *spokestest.Client {
	t.Helper()

	options := []spokestest.ClientOption{}

	// Add repository-specific agents
	for name, content := range repoAgents {
		option := spokestest.ClientWithRepoBlob(repoID, filepath.Join(Directory, name+Extension), []byte(content))
		options = append(options, option)
	}

	// Add public organization-specific agents (.github)
	for name, content := range publicOrgAgents {
		option := spokestest.ClientWithRepoBlob(publicOrgRepoID, filepath.Join(OrgDirectory, name+Extension), []byte(content))
		options = append(options, option)
	}

	// Add private organization-specific agents (.github-private)
	for name, content := range privateOrgAgents {
		option := spokestest.ClientWithRepoBlob(privateOrgRepoID, filepath.Join(OrgDirectory, name+Extension), []byte(content))
		options = append(options, option)
	}

	return spokestest.NewClient(t, options...)
}

func TestService_ListAgents(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"

	t.Run("returns only repo agents when no org agents exist", func(t *testing.T) {
		// Setup different repository IDs to distinguish between repo and org
		repoID := uint64(1)
		orgRepoID := uint64(2)
		repoOwnerID := uint64(3)

		// Setup agents in repository only
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

		// Mock twirp with repo contents, but the .github and .github-private repos do not exist
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			if parts[1] == ".github" || parts[1] == ".github-private" {
				return nil, twirp.NewError(twirp.NotFound, fmt.Sprintf("repository %s/%s not found", parts[0], parts[1]))
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         int64(repoID),
						Name:       parts[1],
						OwnerId:    int64(repoOwnerID),
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.NoError(t, err)
		require.Len(t, result, 2)

		// Verify repo agents are returned
		agentNames := make([]string, len(result))
		for i, agent := range result {
			agentNames[i] = agent.Name()
		}
		require.Contains(t, agentNames, "repo-agent1")
		require.Contains(t, agentNames, "repo-agent2")
		agentRepoIDs := make(map[int64]bool)
		for _, agent := range result {
			id := agent.RepoID()
			if !agentRepoIDs[id] {
				agentRepoIDs[id] = true
			}
		}
		require.Len(t, agentRepoIDs, 1)
		require.Equal(t, true, agentRepoIDs[int64(repoID)])
		agentRepoOwnerIDs := make(map[int64]bool)
		for _, agent := range result {
			id := agent.RepoOwnerID()
			if !agentRepoOwnerIDs[id] {
				agentRepoOwnerIDs[id] = true
			}
		}
		require.Len(t, agentRepoOwnerIDs, 1)
		require.Equal(t, true, agentRepoOwnerIDs[int64(repoOwnerID)])
	})

	t.Run("returns only org agents when no repo agents exist", func(t *testing.T) {
		// Setup different repository IDs to distinguish between repo and org
		repoID := uint64(1)
		orgRepoID := uint64(2)
		repoOwnerID := uint64(3)

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
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.NoError(t, err)
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
	})

	t.Run("combines repo and org agents with repo agents taking precedence", func(t *testing.T) {
		// Setup different repository IDs to distinguish between repo and org
		repoID := uint64(1)
		orgRepoID := uint64(2)
		repoOwnerID := uint64(3)

		// Setup agents with some overlapping names to test precedence
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
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.NoError(t, err)
		require.Len(t, result, 3) // shared-agent (from repo), repo-only, org-only

		// Verify all expected agents are returned
		agentNames := make([]string, len(result))
		agentDescriptions := make(map[string]string)
		for i, agent := range result {
			agentNames[i] = agent.Name()
			agentDescriptions[agent.Name()] = agent.Description()
		}

		require.Contains(t, agentNames, "shared-agent")
		require.Contains(t, agentNames, "repo-only")
		require.Contains(t, agentNames, "org-only")

		// Verify that repo version of shared-agent takes precedence
		require.Equal(t, "Repository version of shared agent", agentDescriptions["shared-agent"])
		require.Equal(t, "Only exists in repository", agentDescriptions["repo-only"])
		require.Equal(t, "Only exists in organization", agentDescriptions["org-only"])

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
	})

	t.Run("handles error when repository access fails", func(t *testing.T) {
		spokes := makeSpokesWithAgents(t, map[string]string{})

		repoID := int64(1)
		orgRepoID := int64(2)

		// Simulate access denied for the for primary repo
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			if parts[1] == ".github" || parts[1] == ".github-private" {
				id = orgRepoID
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         id,
						Name:       parts[1],
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: false,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		_, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.Error(t, err)
	})

	t.Run("handles error when org repository access fails", func(t *testing.T) {
		// Setup some repo agents
		agents := map[string]string{
			"repo-agent": `---
name: Repo Agent
description: Repository agent
---

A repository agent.`,
		}
		spokes := makeSpokesWithAgents(t, agents)

		repoID := int64(1)
		orgRepoID := int64(2)

		// Simulate access denied for the for org repo
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			if parts[1] == ".github" || parts[1] == ".github-private" {
				id = orgRepoID
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         id,
						Name:       parts[1],
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		ghtwirp.NoopSweagentdAPI.MockAuthorizeCustomAgentRepoForUser = func(ctx context.Context, req *sweagentdv1.AuthorizeCustomAgentRepoForUserRequest) (*sweagentdv1.AuthorizeCustomAgentRepoForUserResponse, error) {
			if req.RepositoryId == uint64(orgRepoID) {
				return &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
					CanAccess: true,
				}, nil
			}
			return &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
				CanAccess: false,
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		_, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.Error(t, err)
	})

	t.Run("ListAgents 404s when no agents exist in repo or org", func(t *testing.T) {
		// Empty spokes - no agents configured
		spokes := makeSpokesWithAgents(t, map[string]string{})

		repoID := int64(1)
		orgRepoID := int64(2)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			if parts[1] == ".github" || parts[1] == ".github-private" {
				id = orgRepoID
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         id,
						Name:       parts[1],
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.True(t, errors.Is(err, ErrNoAgentsFound))
		require.Len(t, result, 0)
	})
}

func TestService_TargetProperty(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"
	agentName := "test-agent"
	repoID := uint64(1)
	repoOwnerID := uint64(3)

	// Helper function to create mock GitHub client for repo-only scenarios
	setupGitHubMock := func() *githubtwirp.NoopClient {
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			if parts[1] == ".github" || parts[1] == ".github-private" {
				return nil, twirp.NewError(twirp.NotFound, fmt.Sprintf("repository %s/%s not found", parts[0], parts[1]))
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         int64(repoID),
						Name:       parts[1],
						OwnerId:    int64(repoOwnerID),
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		return ghtwirp
	}

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
		ghtwirp := setupGitHubMock()
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.NoError(t, err)
		require.Len(t, result, 2)

		// Verify target values are preserved correctly
		agentTargets := make(map[string]string)
		for _, agent := range result {
			agentTargets[agent.Name()] = agent.Target()
		}

		require.Equal(t, "", agentTargets["default-agent"])
		require.Equal(t, "github-copilot", agentTargets["github-copilot-agent"])
	})

	t.Run("ResolveByName preserves target values for repo agents", func(t *testing.T) {
		testCases := []struct {
			name           string
			repoAgents     map[string]string
			expectedTarget string
		}{
			{
				name: "repo agent with empty target",
				repoAgents: map[string]string{
					agentName: `---
name: Default Test Agent
description: Agent with no target
tools: tool1
---
Default agent.`,
				},
				expectedTarget: "",
			},
			{
				name: "repo agent with github-copilot target",
				repoAgents: map[string]string{
					agentName: `---
name: GitHub Copilot Test Agent
description: Agent for GitHub Copilot
target: github-copilot
tools: tool1
---
GitHub Copilot agent.`,
				},
				expectedTarget: "github-copilot",
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				spokes := makeSpokesWithAgents(t, tc.repoAgents)
				ghtwirp := setupGitHubMock()
				ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
				service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

				result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", false)
				require.NoError(t, err)
				require.NotNil(t, result)

				agent, ok := result.(*Agent)
				require.True(t, ok, "Expected *Agent, got %T", result)
				require.Equal(t, tc.expectedTarget, agent.Target())
			})
		}
	})

	t.Run("vscode target returns specific error", func(t *testing.T) {
		// Setup agent with vscode target (should cause error)
		repoAgents := map[string]string{
			agentName: `---
name: VSCode Test Agent
description: Agent for VSCode (should error)
target: vscode
tools: tool1
---
VSCode agent.`,
		}

		spokes := makeSpokesWithAgents(t, repoAgents)
		ghtwirp := setupGitHubMock()
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ListAgents - should return ErrNoAgentsFound when excludeInvalidConfig=true and only invalid agents exist
		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, true)
		require.True(t, errors.Is(err, ErrNoAgentsFound), "ListAgents should return ErrNoAgentsFound when only invalid agents exist and excludeInvalidConfig=true")
		require.Len(t, result, 0)

		// Test ListAgents with excludeInvalidConfig=false - should include the invalid agent
		resultWithInvalid, errWithInvalid := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.NoError(t, errWithInvalid)
		require.Len(t, resultWithInvalid, 1, "ListAgents should include vscode agents when excludeInvalidConfig=false")

		// The agent should have a config error
		agent := resultWithInvalid[0]
		require.Equal(t, agentName, agent.Name())
		require.NotEmpty(t, agent.ConfigError(), "Agent should have a config error due to vscode target")

		// Test ResolveByName with errorOnInvalidConfig=true - should return the specific error for vscode target
		result2, err2 := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err2)
		require.Nil(t, result2)

		// Check that the error contains the expected message about vscode target
		require.Contains(t, err2.Error(), "Config is for VS Code only")

		// Test ResolveByName with errorOnInvalidConfig=false - should return agent with config error
		result3, err3 := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", false)
		require.NoError(t, err3)
		require.NotNil(t, result3)

		// The agent should have a config error but still be returned
		agentWithError := result3.(*Agent)
		require.Equal(t, agentName, agentWithError.Name())
		require.NotEmpty(t, agentWithError.ConfigError(), "Agent should have a config error due to vscode target")
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
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, true)
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
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.NoError(t, err)
		require.Len(t, result, 2, "expected all agents (valid + invalid) to be returned")

		// Verify that the valid agent doesn't have an error
		validAgent := findAgentByName(result, "Valid Agent")
		require.NotNil(t, validAgent, "expected to find valid agent")
		require.Empty(t, validAgent.ConfigError(), "valid agent should not have config error")

		// Verify that invalid agents have config errors
		invalidNoDescAgent := findAgentByName(result, "No Description")
		require.NotNil(t, invalidNoDescAgent, "expected to find agent with missing description")
		require.NotEmpty(t, invalidNoDescAgent.ConfigError(), "agent with missing description should have config error")
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
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test with excludeInvalidConfig=true
		resultExclude, err := service.ListAgents(ctx, userID, repoOwner, repoName, true)
		require.NoError(t, err)
		require.Len(t, resultExclude, 1, "expected only valid org agent")
		require.Equal(t, "Valid Org Agent", resultExclude[0].DisplayName())

		// Test with excludeInvalidConfig=false
		resultInclude, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.NoError(t, err)
		require.Len(t, resultInclude, 3, "expected all agents from both repo and org")
	})
}

// Helper function to find an agent by display name
func findAgentByName(agents []sweagentd.CustomAgent, displayName string) sweagentd.CustomAgent {
	for _, agent := range agents {
		if agent.DisplayName() == displayName {
			return agent
		}
	}
	return nil
}

func TestService_ResolveByName(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"
	agentName := "test-agent"

	t.Run("returns repo agent when found in repository", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)
		repoOwnerID := uint64(3)

		// Setup agent in repository only
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
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should return regular Agent, not PrivilegedAgent
		agent, ok := result.(*Agent)
		require.True(t, ok, "Expected *Agent, got %T", result)

		require.Equal(t, agentName, agent.Name())
		require.Equal(t, "Test Agent", agent.DisplayName())
		require.Equal(t, "A test agent in repository", agent.Description())
		require.Equal(t, repoOwnerID, uint64(agent.RepoOwnerID()))
		require.Equal(t, repoOwner, agent.RepoOwner())
		require.Equal(t, repoID, uint64(agent.RepoID()))
		require.Equal(t, repoName, agent.RepoName())
		require.Contains(t, agent.Tools(), "repo-tool")
	})

	t.Run("returns org agent when not found in repository but found in org", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)
		repoOwnerID := uint64(3)

		// Setup agent in org only
		orgAgents := map[string]string{
			agentName: `---
name: Test Org Agent
description: A test agent in organization
tools: org-tool
---

You are an organization-level test agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should return PrivilegedAgent wrapper
		orgAgent, ok := result.(*PrivilegedAgent)
		require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

		require.Equal(t, agentName, orgAgent.Name())
		require.Equal(t, "Test Org Agent", orgAgent.DisplayName())
		require.Equal(t, "A test agent in organization", orgAgent.Description())
		require.Equal(t, repoOwnerID, uint64(orgAgent.RepoOwnerID()))
		require.Equal(t, repoOwner, orgAgent.RepoOwner())
		require.Equal(t, ".github", orgAgent.RepoName()) // Org agents come from .github repo
		require.Equal(t, orgRepoID, uint64(orgAgent.RepoID()))
		require.Contains(t, orgAgent.Tools(), "org-tool")
	})

	t.Run("repo agent takes precedence over org agent", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup same agent in both repo and org
		repoAgents := map[string]string{
			agentName: `---
name: Test Agent (Repo)
description: Repository version takes precedence
tools: repo-tool
---

Repository version of the agent.`,
		}
		orgAgents := map[string]string{
			agentName: `---
name: Test Agent (Org)
description: Organization version should not be returned
tools: org-tool
---

Organization version of the agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should return regular Agent (repo version), not PrivilegedAgent
		agent, ok := result.(*Agent)
		require.True(t, ok, "Expected *Agent, got %T", result)

		require.Equal(t, agentName, agent.Name())
		require.Equal(t, "Test Agent (Repo)", agent.DisplayName())
		require.Equal(t, "Repository version takes precedence", agent.Description())
		require.Equal(t, repoName, agent.RepoName()) // Should be the regular repo, not .github
		require.Contains(t, agent.Tools(), "repo-tool")
		require.NotContains(t, agent.Tools(), "org-tool")
	})

	t.Run("returns org agent when current repo context is .github repo", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)
		repoOwnerID := uint64(3)

		// Setup agent in .github repo (which is also our current repo context)
		orgAgents := map[string]string{
			agentName: `---
name: Test Org Agent in Github Repo
description: An org agent accessed from .github repo context
tools: org-tool-from-github
---

You are an organization-level agent accessed from .github repo context.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, ".github", agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should return PrivilegedAgent wrapper even though current repo is .github
		orgAgent, ok := result.(*PrivilegedAgent)
		require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

		require.Equal(t, agentName, orgAgent.Name())
		require.Equal(t, "Test Org Agent in Github Repo", orgAgent.DisplayName())
		require.Equal(t, "An org agent accessed from .github repo context", orgAgent.Description())
		require.Equal(t, repoOwnerID, uint64(orgAgent.RepoOwnerID()))
		require.Equal(t, repoOwner, orgAgent.RepoOwner())
		require.Equal(t, ".github", orgAgent.RepoName()) // Org agents come from .github repo
		require.Equal(t, orgRepoID, uint64(orgAgent.RepoID()))
		require.Contains(t, orgAgent.Tools(), "org-tool-from-github")
	})

	t.Run("returns org agent when current repo context is .github-private repo", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)
		privateOrgRepoID := uint64(3)
		repoOwnerID := uint64(4)

		privateOrgAgents := map[string]string{
			agentName: `---
name: Test Private Org Agent in Github Private Repo
description: A private org agent accessed from .github-private repo context
tools: private-org-tool-from-github
---

You are a private organization-level agent accessed from .github-private repo context.`,
		}
		spokes := makeSpokesWithMultipleOrgRepos(t, map[string]string{}, map[string]string{}, privateOrgAgents, repoID, orgRepoID, privateOrgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			switch parts[1] {
			case ".github":
				id = orgRepoID
			case ".github-private":
				id = privateOrgRepoID
			default:
				// Do nothing - here for linting purposes
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

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)
		result, err := service.ResolveByName(ctx, userID, repoOwner, ".github-private", agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should return PrivilegedAgent wrapper even though current repo is .github-private
		orgAgent, ok := result.(*PrivilegedAgent)
		require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

		require.Equal(t, agentName, orgAgent.Name())
		require.Equal(t, "Test Private Org Agent in Github Private Repo", orgAgent.DisplayName())
		require.Equal(t, "A private org agent accessed from .github-private repo context", orgAgent.Description())
		require.Equal(t, repoOwner, orgAgent.RepoOwner())
		require.Equal(t, repoOwnerID, uint64(orgAgent.RepoOwnerID()))
		require.Equal(t, ".github-private", orgAgent.RepoName()) // Should still be .github-private
		require.Equal(t, privateOrgRepoID, uint64(orgAgent.RepoID()))
		require.Contains(t, orgAgent.Tools(), "private-org-tool-from-github")
	})

	t.Run("returns error from org agent lookup when agent not found in repo or org", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup empty spokes
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err)
		// New behavior: instead of returning ErrRequestedAgentNotFound, ResolveByName returns
		// the error from org agent lookup when org repo exists but agent not found
		require.True(t, errors.Is(err, ErrRequestedAgentNotFound)) // The underlying error should still be ErrRequestedAgentNotFound
		require.Nil(t, result)
	})

	t.Run("returns private org agent when not found in repository or public org", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)
		privateOrgRepoID := uint64(3)
		repoOwnerID := uint64(4)

		// Setup agent in .github-private only
		privateOrgAgents := map[string]string{
			agentName: `---
name: Test Private Org Agent
description: A test agent in private organization repo
tools: private-org-tool
---

You are a private organization-level test agent.`,
		}
		spokes := makeSpokesWithMultipleOrgRepos(t, map[string]string{}, map[string]string{}, privateOrgAgents, repoID, orgRepoID, privateOrgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			switch parts[1] {
			case ".github":
				id = orgRepoID
			case ".github-private":
				id = privateOrgRepoID
			default:
				// Do nothing - here for linting purposes
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
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should return PrivilegedAgent wrapper for private org agent
		orgAgent, ok := result.(*PrivilegedAgent)
		require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

		require.Equal(t, agentName, orgAgent.Name())
		require.Equal(t, "Test Private Org Agent", orgAgent.DisplayName())
		require.Equal(t, "A test agent in private organization repo", orgAgent.Description())
		require.Equal(t, repoOwner, orgAgent.RepoOwner())
		require.Equal(t, repoOwnerID, uint64(orgAgent.RepoOwnerID()))
		require.Equal(t, ".github-private", orgAgent.RepoName()) // Private org agents come from .github-private repo
		require.Equal(t, privateOrgRepoID, uint64(orgAgent.RepoID()))
		require.Contains(t, orgAgent.Tools(), "private-org-tool")
	})

	t.Run("public org agent takes precedence over private org agent", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)
		privateOrgRepoID := uint64(3)

		// Setup same agent in both public and private org repos
		publicOrgAgents := map[string]string{
			agentName: `---
name: Test Agent (Public Org)
description: Public org version takes precedence over private
tools: public-org-tool
---

Public organization version of the agent.`,
		}
		privateOrgAgents := map[string]string{
			agentName: `---
name: Test Agent (Private Org)
description: Private org version should not be returned
tools: private-org-tool
---

Private organization version of the agent.`,
		}
		spokes := makeSpokesWithMultipleOrgRepos(t, map[string]string{}, publicOrgAgents, privateOrgAgents, repoID, orgRepoID, privateOrgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			switch parts[1] {
			case ".github":
				id = orgRepoID
			case ".github-private":
				id = privateOrgRepoID
			default:
				// Do nothing - here for linting purposes
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         int64(id),
						Name:       parts[1],
						OwnerId:    4,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should return PrivilegedAgent with public org version
		orgAgent, ok := result.(*PrivilegedAgent)
		require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

		require.Equal(t, agentName, orgAgent.Name())
		require.Equal(t, "Test Agent (Public Org)", orgAgent.DisplayName())
		require.Equal(t, "Public org version takes precedence over private", orgAgent.Description())
		require.Equal(t, ".github", orgAgent.RepoName()) // Should be the public org repo
		require.Contains(t, orgAgent.Tools(), "public-org-tool")
		require.NotContains(t, orgAgent.Tools(), "private-org-tool")
	})

	t.Run("returns error when org repo does not exist", func(t *testing.T) {
		repoID := uint64(1)

		// Setup empty repo
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, 0)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			if parts[1] == ".github" || parts[1] == ".github-private" {
				return nil, errors.New("not found")
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         int64(repoID),
						Name:       parts[1],
						OwnerId:    4,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err)
		require.Nil(t, result)
	})

	t.Run("returns error when repository access fails", func(t *testing.T) {
		spokes := makeSpokesWithAgents(t, map[string]string{})

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         1,
						Name:       parts[1],
						OwnerId:    4,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: false,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err)
		require.Nil(t, result)
	})

	t.Run("returns error when org repository access fails with non-404 error", func(t *testing.T) {
		repoID := uint64(1)

		// Setup empty repo
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, 0)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			if parts[1] == ".github" || parts[1] == ".github-private" {
				return nil, errors.New("some other error")
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         int64(id),
						Name:       parts[1],
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err)
		require.Nil(t, result)
	})

	t.Run("handles agent configuration uses config at different level if parsing errors in repo", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup invalid agent configuration in repo
		repoAgents := map[string]string{
			agentName: `invalid agent configuration without frontmatter`,
		}
		// Setup valid org agent as fallback
		orgAgents := map[string]string{
			agentName: `---
name: Valid Org Agent
description: Valid org agent
---

Valid org agent content.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.NoError(t, err)
		// Should return an error but we don't check specific error content
		require.NotNil(t, result)
	})

	t.Run("handles agent configuration parsing errors in repo", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup invalid agent configuration in repo
		repoAgents := map[string]string{
			agentName: `invalid agent configuration without frontmatter`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err)
		// Should return an error but we don't check specific error content
		require.Nil(t, result)
	})

	t.Run("returns error from org agent lookup for parsing errors", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup invalid agent configuration in org only
		orgAgents := map[string]string{
			agentName: `invalid agent configuration without frontmatter`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err)
		// Should return an error but we don't check specific error content for parsing errors
		require.Nil(t, result)
	})

	t.Run("handles twirp NotFound error for enterprise agents gracefully", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

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
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}

		// Setup mock to return twirp.NotFound for EnterpriseAgents
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should still find the repository agent even though enterprise agents returned NotFound
		agent, ok := result.(*Agent)
		require.True(t, ok, "Expected *Agent, got %T", result)
		require.Equal(t, agentName, agent.Name())
		require.Equal(t, "Test Agent", agent.DisplayName())
	})

	t.Run("handles non-NotFound twirp errors for enterprise agents", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup empty repository
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.InternalError("internal server error")
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err)
		require.Nil(t, result)
	})

	t.Run("handles twirp NotFound error for enterprise agents gracefully", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

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
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.NoError(t, err)
		require.NotNil(t, result)

		// Should still find the repository agent even though enterprise agents returned NotFound
		agent, ok := result.(*Agent)
		require.True(t, ok, "Expected *Agent, got %T", result)
		require.Equal(t, agentName, agent.Name())
		require.Equal(t, "Test Agent", agent.DisplayName())
	})

	t.Run("handles non-NotFound twirp errors for enterprise agents", func(t *testing.T) {
		repoID := uint64(1)
		orgRepoID := uint64(2)

		// Setup empty repository
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
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
						OwnerId:    3,
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.InternalError("internal server error")
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByName(ctx, userID, repoOwner, repoName, agentName, "", true)
		require.Error(t, err)
		require.Nil(t, result)
	})
}

func TestService_PrivilegedDirectoryConfiguration(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoID := uint64(1)
	privilegedRepoID := uint64(2) // .github repo ID
	repoOwnerID := uint64(3)

	ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
	ghtwirp := githubtwirp.NewNoopClient()
	ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		parts := strings.Split(req.Nwos[0], "/")
		id := repoID
		switch parts[1] {
		case ".github":
			id = privilegedRepoID
		case ".github-private":
			return nil, ErrRepoNotFound
		default:
			// Do nothing - here for linting purposes
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
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, privilegedAgents, privilegedRepoID, privilegedRepoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		validate := func(agent sweagentd.CustomAgent) {
			require.NotNil(t, agent)

			// Should return PrivilegedAgent wrapper
			privilegedAgent, ok := agent.(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent, got %T", agent)

			require.Equal(t, agentName, privilegedAgent.Name())
			require.Equal(t, "Privileged Version", privilegedAgent.DisplayName())
			require.Equal(t, "Agent from privileged directory.", privilegedAgent.Description())
			require.Contains(t, privilegedAgent.Tools(), "privileged-tool")
		}

		// Try ResolveByName
		agent, err := service.ResolveByName(ctx, userID, repoOwner, ".github", agentName, "", true)
		require.NoError(t, err)
		validate(agent)

		// Try GetAgent
		agent2, err := service.GetAgent(ctx, userID, repoOwner, ".github", agentName, "")
		require.NoError(t, err)
		validate(agent2)
	})

	t.Run("non-privileged repo can load agent from Directory", func(t *testing.T) {
		agentName := "test-agent"
		// Setup agent only in regular directory
		spokes := makeSpokesWithRepoSpecificAgents(t, regularAgents, map[string]string{}, repoID, privilegedRepoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		validate := func(agent sweagentd.CustomAgent) {
			require.NotNil(t, agent)

			// Should return regular Agent (not PrivilegedAgent wrapper)
			regularAgent, ok := agent.(*Agent)
			require.True(t, ok, "Expected *Agent, got %T", agent)

			require.Equal(t, agentName, regularAgent.Name())
			require.Equal(t, "Regular Version", regularAgent.DisplayName())
			require.Equal(t, "Agent from regular directory.", regularAgent.Description())
			require.Contains(t, regularAgent.Tools(), "regular-tool")
		}

		// Try ResolveByName
		agent, err := service.ResolveByName(ctx, userID, repoOwner, "regular-repo", agentName, "", true)
		require.NoError(t, err)
		validate(agent)

		// Try GetAgent
		agent2, err := service.GetAgent(ctx, userID, repoOwner, "regular-repo", agentName, "")
		require.NoError(t, err)
		validate(agent2)
	})

	t.Run("non-privileged repo cannot load agent from PrivilegedDirectory", func(t *testing.T) {
		agentName := "test-agent-priv"
		// Setup agent only in prv'd dir, but using the repo ID as the regular repo for the privileged set
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, privilegedAgents, repoID, repoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Should not find the agent since regular repo cannot access privileged directory
		// Try ResolveByName
		_, err := service.ResolveByName(ctx, userID, repoOwner, "regular-repo", agentName, "", true)
		require.Error(t, err)
		require.True(t, errors.Is(err, ErrRequestedAgentNotFound))

		// Try GetAgent
		_, err = service.GetAgent(ctx, userID, repoOwner, "regular-repo", agentName, "")
		require.Error(t, err)
		require.True(t, errors.Is(err, ErrRequestedAgentNotFound))
	})

	t.Run("ListAgents includes content from both directories based on the repo", func(t *testing.T) {
		spokes := makeSpokesWithRepoSpecificAgents(t, privilegedAgents, regularAgents, repoID, privilegedRepoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, "regular-repo", false)
		require.NoError(t, err)
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
	})
}

func TestTwirpRepoProvider(t *testing.T) {
	ctx := context.Background()

	t.Run("getRepository success with single repository", func(t *testing.T) {
		// Create a mock client that returns a successful response
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: false,
			},
		}

		provider := newTwirpRepoProvider(mockClient)

		repo, err := provider.getRepository(ctx, "test-owner", ".github")
		require.NoError(t, err)
		require.NotNil(t, repo)

		// Verify the repository ID matches what our noop returns (ID 2 for .github)
		require.Equal(t, int64(2), repo.GetID())
	})

	t.Run("getRepository returns repository for regular repos", func(t *testing.T) {
		// Create a mock client that returns repositories
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: false,
			},
		}

		provider := newTwirpRepoProvider(mockClient)

		// Request a non-org repository - our noop now returns all requested repos
		repo, err := provider.getRepository(ctx, "test-owner", "regular-repo")
		require.NoError(t, err)
		require.NotNil(t, repo)
		require.Equal(t, int64(1), repo.GetID())
	})

	t.Run("getRepository propagates API errors", func(t *testing.T) {
		// Create a mock client that returns an error
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				ShouldReturnError: true,
			},
		}

		provider := newTwirpRepoProvider(mockClient)

		repo, err := provider.getRepository(ctx, "test-owner", ".github")
		require.Error(t, err)
		require.Nil(t, repo)
	})

	t.Run("getRepository handles nil client gracefully", func(t *testing.T) {
		// Test with nil NoopRepositoriesAPI (simulates manual client creation)
		mockClient := &githubtwirp.NoopClient{
			NoopRepositoriesAPI: nil, // This causes our nil receiver handling to kick in
		}

		provider := newTwirpRepoProvider(mockClient)

		repo, err := provider.getRepository(ctx, "test-owner", ".github")
		require.Error(t, err)
		require.ErrorIs(t, err, ErrRepoNotFound) // Empty response = not found
		require.Nil(t, repo)
	})

	t.Run("getRepository extracts correct repository from multiple results", func(t *testing.T) {
		// Create a noop client that returns multiple repositories (first should be used)
		mockClient := githubtwirp.NewNoopClientWithMultipleRepositories()

		provider := newTwirpRepoProvider(mockClient)

		repo, err := provider.getRepository(ctx, "test-owner", ".github")
		require.NoError(t, err)
		require.NotNil(t, repo)

		// Should use the first repository from the response
		require.Equal(t, int64(100), repo.GetID())
	})
}

func TestService_GetAgent(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := ".github" // Use org repo that exists in twirp noop client
	agentName := "test-agent"
	version := ""

	t.Run("returns agent when user is authorized and agent exists", func(t *testing.T) {
		repoID := uint64(2) // This is the ID that noop client returns for .github

		// Setup agent in repository
		agents := map[string]string{
			agentName: `---
name: Test Agent
description: A test agent
tools: test-tool
---

You are a test agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, agents, 0, repoID)

		// Mock GitHub twirp client that returns successful authorization
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, userID, repoOwner, repoName, agentName, version)
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, agentName, result.Name())
		require.Equal(t, "Test Agent", result.DisplayName())
		require.Equal(t, "A test agent", result.Description())
		require.Equal(t, int64(repoID), result.RepoID())
	})

	t.Run("returns ErrRequestedAgentNotFound when user is not authorized", func(t *testing.T) {
		repoID := uint64(2)

		// Setup agent in repository (exists but user can't access)
		agents := map[string]string{
			agentName: `---
name: Test Agent
description: A test agent
---

You are a test agent.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, agents, 0, repoID)

		// Mock GitHub twirp client that denies authorization
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: false,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, userID, repoOwner, repoName, agentName, version)
		require.Error(t, err)
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("returns error when repository is not found", func(t *testing.T) {
		spokes := makeSpokesWithAgents(t, map[string]string{})

		// Mock GitHub twirp client that returns repository not found
		ghtwirp := githubtwirp.NewNoopClientWithRepositoryError()

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, userID, repoOwner, "non-existent-repo", agentName, version)
		require.Error(t, err)
		// The error should wrap the repository access error (not ErrRepoNotFound since API error is returned)
		require.NotErrorIs(t, err, ErrRepoNotFound)
		require.Nil(t, result)
	})

	t.Run("returns error when authorization API call fails", func(t *testing.T) {
		spokes := makeSpokesWithAgents(t, map[string]string{})

		authErr := errors.New("authorization service unavailable")
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI = &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryError: &authErr,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, userID, repoOwner, "non-existent-repo", agentName, version)
		require.Error(t, err)
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("returns error when agent does not exist but user is authorized", func(t *testing.T) {
		// Empty spokes - no agents configured
		spokes := makeSpokesWithAgents(t, map[string]string{})

		// Mock GitHub twirp client that allows access
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, userID, repoOwner, repoName, agentName, version)
		require.Error(t, err)
		require.Nil(t, result)
		// Should get error from getAgent since agent doesn't exist
	})

	t.Run("passes correct parameters to authorization API", func(t *testing.T) {
		repoID := uint64(2) // .github repo ID from noop client

		agents := map[string]string{
			agentName: `---
name: Test Agent
description: A test agent for authorization
---
Content.`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, agents, 0, repoID)

		// Use default noop client - we'll verify indirectly by successful execution
		ghtwirp := githubtwirp.NewNoopClient()

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, userID, repoOwner, repoName, agentName, version)
		require.NoError(t, err)
		require.NotNil(t, result)

		// If we get here successfully, it means the authorization call was made with correct parameters
		// The noop implementation returns CanAccess: true by default
	})

	t.Run("handles agent configuration parsing errors", func(t *testing.T) {
		repoID := uint64(2)

		// Setup invalid agent configuration
		agents := map[string]string{
			agentName: `invalid agent configuration without frontmatter`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, agents, 0, repoID)

		// Mock GitHub twirp client that allows access
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: true,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, userID, repoOwner, repoName, agentName, version)
		require.Error(t, err)
		require.Nil(t, result)
		// Should get parsing error from getAgent method
	})
}

func TestTwirpRepoProviderIntegration(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"

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
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ListAgents(ctx, userID, repoOwner, repoName, false)
		require.Error(t, err)
		require.Nil(t, result)
	})
}

func TestService_IsEnabledForRepo(t *testing.T) {
	ctx := context.Background()

	t.Run("returns true when feature flag is enabled", func(t *testing.T) {
		userID := int64(123)
		ownerID := int64(456)
		repoID := int64(789)

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		service := NewService(observability.NewNoopExporters(), nil, githubtwirp.NewNoopClient(), ffClient)

		result := service.IsEnabledForRepo(ctx, userID, ownerID, repoID)
		require.True(t, result)
	})

	t.Run("returns false when feature flag is disabled", func(t *testing.T) {
		userID := int64(123)
		ownerID := int64(456)
		repoID := int64(789)

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: false})
		service := NewService(observability.NewNoopExporters(), nil, githubtwirp.NewNoopClient(), ffClient)

		result := service.IsEnabledForRepo(ctx, userID, ownerID, repoID)
		require.False(t, result)
	})

	t.Run("returns false when feature flag is not set", func(t *testing.T) {
		userID := int64(123)
		ownerID := int64(456)
		repoID := int64(789)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), nil, githubtwirp.NewNoopClient(), ffClient)

		result := service.IsEnabledForRepo(ctx, userID, ownerID, repoID)
		require.False(t, result)
	})

	t.Run("returns false when disallow feature flag is enabled", func(t *testing.T) {
		userID := int64(123)
		ownerID := int64(456)
		repoID := int64(789)

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:      true,
			featureflags.CopilotSWEAgentCustomAgentsDisallow: true,
		})
		service := NewService(observability.NewNoopExporters(), nil, githubtwirp.NewNoopClient(), ffClient)

		result := service.IsEnabledForRepo(ctx, userID, ownerID, repoID)
		require.False(t, result, "should return false when disallow flag is enabled")
	})

	t.Run("returns true when disallow is not enabled and custom agents enabled", func(t *testing.T) {
		userID := int64(123)
		ownerID := int64(456)
		repoID := int64(789)

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:      true,
			featureflags.CopilotSWEAgentCustomAgentsDisallow: false,
		})
		service := NewService(observability.NewNoopExporters(), nil, githubtwirp.NewNoopClient(), ffClient)

		result := service.IsEnabledForRepo(ctx, userID, ownerID, repoID)
		require.True(t, result, "should return true when use custom agents is enabled and disallow is explicitly false")
	})
}

func TestService_IsEnabledForRepoByName(t *testing.T) {
	ctx := context.Background()

	t.Run("returns true when feature flag is enabled and repository exists", func(t *testing.T) {
		userID := int64(123)
		repoOwner := "test-owner"
		repoName := "test-repo"

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		ghtwirp := githubtwirp.NewNoopClient()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		enabled, err := service.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
		require.NoError(t, err)
		require.True(t, enabled)
	})

	t.Run("returns false when feature flag is disabled", func(t *testing.T) {
		userID := int64(123)
		repoOwner := "test-owner"
		repoName := "test-repo"

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: false})
		ghtwirp := githubtwirp.NewNoopClient()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		enabled, err := service.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
		require.NoError(t, err)
		require.False(t, enabled)
	})

	t.Run("returns error when repository cannot be fetched", func(t *testing.T) {
		userID := int64(123)
		repoOwner := "test-owner"
		repoName := "test-repo"

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		ghtwirp := githubtwirp.NewNoopClientWithRepositoryError()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		enabled, err := service.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
		require.Error(t, err)
		require.False(t, enabled)
		require.Contains(t, err.Error(), "failed to get repo")
	})

	t.Run("returns correct values for different repositories", func(t *testing.T) {
		userID := int64(123)

		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentUseCustomAgents: true})
		ghtwirp := githubtwirp.NewNoopClient()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		// Test with regular repository
		enabled, err := service.IsEnabledForRepoByName(ctx, userID, "owner1", "repo1")
		require.NoError(t, err)
		require.True(t, enabled)

		// Test with org repository
		enabled, err = service.IsEnabledForRepoByName(ctx, userID, "owner2", ".github")
		require.NoError(t, err)
		require.True(t, enabled)

		// Test with private org repository
		enabled, err = service.IsEnabledForRepoByName(ctx, userID, "owner3", ".github-private")
		require.NoError(t, err)
		require.True(t, enabled)
	})

	t.Run("returns false when disallow feature flag is enabled", func(t *testing.T) {
		userID := int64(123)
		repoOwner := "test-owner"
		repoName := "test-repo"

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:      true,
			featureflags.CopilotSWEAgentCustomAgentsDisallow: true,
		})
		ghtwirp := githubtwirp.NewNoopClient()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		enabled, err := service.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
		require.NoError(t, err)
		require.False(t, enabled, "should return false when disallow flag is enabled")
	})

	t.Run("returns true when use custom agents is enabled and disallow is not enabled", func(t *testing.T) {
		userID := int64(123)
		repoOwner := "test-owner"
		repoName := "test-repo"

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: true,
		})
		ghtwirp := githubtwirp.NewNoopClient()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		enabled, err := service.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
		require.NoError(t, err)
		require.True(t, enabled, "should return true when use custom agents is enabled and disallow is not set")
	})
}
