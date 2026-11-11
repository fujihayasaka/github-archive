package customagent

import (
	"context"
	"errors"
	"strings"
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

func TestService_ResolveByNameAndRepoID(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoOwner := "test-owner"
	repoName := "test-repo"
	agentName := "test-agent"
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	t.Run("returns repo agent when found in repository", func(t *testing.T) {
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
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
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
		}

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("returns org agent when not found in repository but found in org", func(t *testing.T) {
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
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
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
		}

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("doesn't return any agent if only repo source is included and agents only exist at org level", func(t *testing.T) {
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
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true, IncludeSources: []string{SourceTypeRepo}})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("repo agent takes precedence over org agent", func(t *testing.T) {
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
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
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
		}

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("returns org agent when current repo context is .github-private or .github repo", func(t *testing.T) {
		orgAgents := map[string]string{
			agentName: `---
name: Test Org Agent in Org Repo
description: A org agent accessed from org repo context
tools: org-tool-from-github
---

You are a private organization-level agent accessed from org repo context.`,
		}

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})

		verify := func(result sweagentd.CustomAgent, repo string, repoID uint64) {
			require.NotNil(t, result)

			// Should return PrivilegedAgent wrapper even though current repo is .github-private
			orgAgent, ok := result.(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

			require.Equal(t, agentName, orgAgent.Name())
			require.Equal(t, "Test Org Agent in Org Repo", orgAgent.DisplayName())
			require.Equal(t, "A org agent accessed from org repo context", orgAgent.Description())
			require.Equal(t, repoOwner, orgAgent.RepoOwner())
			require.Equal(t, repoOwnerID, uint64(orgAgent.RepoOwnerID()))
			require.Equal(t, repo, orgAgent.RepoName()) // Should still be .github-private
			require.Equal(t, repoID, uint64(orgAgent.RepoID()))
			require.Contains(t, orgAgent.Tools(), "org-tool-from-github")
		}

		// .github
		spokes := makeSpokesWithMultipleOrgRepos(t, map[string]string{}, orgAgents, map[string]string{}, repoID, orgRepoID, privateOrgRepoID)
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)
		result, err := service.ResolveByNameAndRepoID(ctx, orgRepoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result, ".github", orgRepoID)

		// .github-private
		spokes = makeSpokesWithMultipleOrgRepos(t, map[string]string{}, map[string]string{}, orgAgents, repoID, orgRepoID, privateOrgRepoID)
		service = NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)
		result, err = service.ResolveByNameAndRepoID(ctx, privateOrgRepoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result, ".github-private", privateOrgRepoID)
	})

	t.Run("returns error from org agent lookup when agent not found in repo or org", func(t *testing.T) {
		// Setup empty spokes
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.Error(t, err)
		// ResolveByNameAndRepoID returns ErrRequestedAgentNotFound
		// when org repo exists but agent not found
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("returns .github-private agent when not found in repository or .github", func(t *testing.T) {
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
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
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
		}

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run(".github org agent takes precedence over .github-private org agent", func(t *testing.T) {
		// Setup same agent in both public and private org repos
		publicOrgAgents := map[string]string{
			agentName: `---
name: Test Agent (.github)
description: Public org version takes precedence over private
tools: public-org-tool
---

Public organization version of the agent.`,
		}
		privateOrgAgents := map[string]string{
			agentName: `---
name: Test Agent (.github-private)
description: Private org version should not be returned
tools: private-org-tool
---

Private organization version of the agent.`,
		}
		spokes := makeSpokesWithMultipleOrgRepos(t, map[string]string{}, publicOrgAgents, privateOrgAgents, repoID, orgRepoID, privateOrgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Should return PrivilegedAgent with public org version
			orgAgent, ok := result.(*PrivilegedAgent)
			require.True(t, ok, "Expected *PrivilegedAgent, got %T", result)

			require.Equal(t, agentName, orgAgent.Name())
			require.Equal(t, "Test Agent (.github)", orgAgent.DisplayName())
			require.Equal(t, "Public org version takes precedence over private", orgAgent.Description())
			require.Equal(t, ".github", orgAgent.RepoName()) // Should be the public org repo
			require.Contains(t, orgAgent.Tools(), "public-org-tool")
			require.NotContains(t, orgAgent.Tools(), "private-org-tool")
		}

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("returns ErrRequestedAgentNotFound when org repos do not exist and nothing in repo", func(t *testing.T) {
		// Setup empty repo
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, 0)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, 0, 0, repoOwnerID, false)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("returns ErrRequestedAgentNotFound when repository access fails", func(t *testing.T) {
		spokes := makeSpokesWithAgents(t, map[string]string{})

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, 0, 0, repoOwnerID, false)
		ghtwirp.NoopSweagentdAPI.AuthorizeCustomAgentRepoForUserResponse = &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
			CanAccess: false,
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("returns error when org repository access fails with unexpected error", func(t *testing.T) {
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
		ghtwirp.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
			if uint64(req.Ids[0]) != repoID {
				return nil, errors.New("some other error")
			}
			return &repositoriesTwirp.FindRepositoriesResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         int64(repoID),
						Name:       repoName,
						OwnerId:    int64(repoOwnerID),
						OwnerLogin: repoOwner,
					},
				},
			}, nil
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.Error(t, err)
		require.Nil(t, result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.Error(t, err)
		require.Nil(t, result)
	})

	t.Run("handles using agent configuration config at different level if parsing fails in repo config", func(t *testing.T) {
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
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		// Should return an error but we don't check specific error content
		require.NotNil(t, result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		// Should return an error but we don't check specific error content
		require.NotNil(t, result)
	})

	t.Run("handles agent configuration parsing errors in repo", func(t *testing.T) {
		// Setup invalid agent configuration in repo
		repoAgents := map[string]string{
			agentName: `invalid agent configuration without frontmatter`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, repoAgents, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, 0, 0, false)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.Error(t, err)
		// Should return an error but we don't check specific error content
		require.Nil(t, result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.Error(t, err)
		// Should return an error but we don't check specific error content
		require.Nil(t, result)
	})

	t.Run("handles agent configuration parsing errors in org level repos", func(t *testing.T) {
		// Setup invalid agent configuration in org only
		orgAgents := map[string]string{
			agentName: `invalid agent configuration without frontmatter`,
		}
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, orgAgents, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.Error(t, err)
		// Should return an error but we don't check specific error content for parsing errors
		require.Nil(t, result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.Error(t, err)
		// Should return an error but we don't check specific error content for parsing errors
		require.Nil(t, result)
	})

	t.Run("handles twirp NotFound error for enterprise agents gracefully", func(t *testing.T) {
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

		verify := func(result sweagentd.CustomAgent) {
			require.NotNil(t, result)

			// Should still find the repository agent even though enterprise agents returned NotFound
			agent, ok := result.(*Agent)
			require.True(t, ok, "Expected *Agent, got %T", result)
			require.Equal(t, agentName, agent.Name())
			require.Equal(t, "Test Agent", agent.DisplayName())
		}

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)

		// Also test ID variation
		result, err = service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.NoError(t, err)
		verify(result)
	})

	t.Run("handles non-NotFound twirp errors for enterprise agents", func(t *testing.T) {
		// Setup empty repository
		spokes := makeSpokesWithRepoSpecificAgents(t, map[string]string{}, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)
		ghtwirp.SweagentdAPI().(*githubtwirp.NoopSweagentdAPI).MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.InternalError("internal server error")
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		// Test ResolveByNameAndRepoID
		result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: true})
		require.Error(t, err)
		require.Nil(t, result)
	})

	t.Run("ResolveByNameAndRepoID preserves target values for repo agents", func(t *testing.T) {
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
				expectedTarget: TargetGitHubCopilot,
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				spokes := makeSpokesWithAgents(t, tc.repoAgents)
				ghtwirp := githubtwirp.NewNoopClient()
				setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

				ffClient := featureflags.NewNoopClient(map[string]bool{})
				service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

				result, err := service.ResolveByNameAndRepoID(ctx, repoID, agentName, "", ResolveByNameOpts{UserID: userID, ErrorOnInvalidConfig: false})
				require.NoError(t, err)
				require.NotNil(t, result)

				agent, ok := result.(*Agent)
				require.True(t, ok, "Expected *Agent, got %T", result)
				require.Equal(t, tc.expectedTarget, agent.Target())
			})
		}
	})
}
