package customagent

import (
	"context"
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
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// NOTE: This file includes common tests and utilities - the majority of tests are in other files

// Helper function to create spokes with agents (similar to makeSpokesWithAgents but avoiding import cycle)
func makeSpokesWithAgents(t *testing.T, agents map[string]string) *spokestest.Client {
	t.Helper()

	fileBlobs := []spokestest.ClientOption{}
	for name, content := range agents {
		blob := spokestest.WithBlob(filepath.Join(Directory, name+Extension), []byte(content))
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
		option := spokestest.WithRepoBlob(repoID, filepath.Join(Directory, name+Extension), []byte(content))
		options = append(options, option)
	}

	// Add organization-specific agents
	for name, content := range orgAgents {
		option := spokestest.WithRepoBlob(orgRepoID, filepath.Join(OrgDirectory, name+Extension), []byte(content))
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
		option := spokestest.WithRepoBlob(repoID, filepath.Join(Directory, name+Extension), []byte(content))
		options = append(options, option)
	}

	// Add public organization-specific agents (.github)
	for name, content := range publicOrgAgents {
		option := spokestest.WithRepoBlob(publicOrgRepoID, filepath.Join(OrgDirectory, name+Extension), []byte(content))
		options = append(options, option)
	}

	// Add private organization-specific agents (.github-private)
	for name, content := range privateOrgAgents {
		option := spokestest.WithRepoBlob(privateOrgRepoID, filepath.Join(OrgDirectory, name+Extension), []byte(content))
		options = append(options, option)
	}

	return spokestest.NewClient(t, options...)
}

// Helper to setup mock for FindRepositoriesByName
func setupRepositoryMocks(t *testing.T, ghtwirp *githubtwirp.NoopClient, repoName, ownerLogin string, repoID, orgRepoID, privateOrgRepoID, repoOwnerID uint64, orgReposExist bool) {
	t.Helper()
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
		if (id == orgRepoID || id == privateOrgRepoID) && !orgReposExist {
			return nil, twirp.NewError(twirp.NotFound, fmt.Sprintf("repository %s/%s not found", parts[0], parts[1]))
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
	ghtwirp.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		name := repoName
		switch uint64(req.Ids[0]) {
		case orgRepoID:
			name = ".github"
		case privateOrgRepoID:
			name = ".github-private"
		default:
			// Do nothing - here for linting purposes
		}
		if (name == ".github" || name == ".github-private") && !orgReposExist {
			return nil, twirp.NewError(twirp.NotFound, fmt.Sprintf("repository %d not found", req.Ids[0]))
		}
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{
					Id:         req.Ids[0],
					Name:       name,
					OwnerId:    int64(repoOwnerID),
					OwnerLogin: ownerLogin,
				},
			},
		}, nil
	}
}

// Helper to extract agent names from results
func extractAgentNames(agents []sweagentd.CustomAgent) []string {
	names := make([]string, len(agents))
	for i, agent := range agents {
		names[i] = agent.Name()
	}
	return names
}

// Helper to verify repo IDs in agent results
func verifyAgentRepoIDs(t *testing.T, agents []sweagentd.CustomAgent, expectedIDs ...int64) {
	t.Helper()
	agentRepoIDs := make(map[int64]bool)
	for _, agent := range agents {
		agentRepoIDs[agent.RepoID()] = true
	}
	require.Len(t, agentRepoIDs, len(expectedIDs))
	for _, id := range expectedIDs {
		require.True(t, agentRepoIDs[id])
	}
}

// Helper to verify repo owner IDs in agent results
func verifyAgentRepoOwnerIDs(t *testing.T, agents []sweagentd.CustomAgent, expectedIDs ...int64) {
	t.Helper()
	agentRepoOwnerIDs := make(map[int64]bool)
	for _, agent := range agents {
		agentRepoOwnerIDs[agent.RepoOwnerID()] = true
	}
	require.Len(t, agentRepoOwnerIDs, len(expectedIDs))
	for _, id := range expectedIDs {
		require.True(t, agentRepoOwnerIDs[id])
	}
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

func TestService_IsEnabledForRepo(t *testing.T) {
	ctx := context.Background()

	t.Run("returns false when disallow feature flag is enabled", func(t *testing.T) {
		userID := int64(123)
		ownerID := int64(456)
		repoID := int64(789)

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentsDisallow: true,
		})
		service := NewService(observability.NewNoopExporters(), nil, githubtwirp.NewNoopClient(), ffClient)

		result := service.IsEnabledForRepo(ctx, userID, ownerID, repoID)
		require.False(t, result, "should return false when disallow flag is enabled")
	})

	t.Run("returns true when disallow is not enabled", func(t *testing.T) {
		userID := int64(123)
		ownerID := int64(456)
		repoID := int64(789)

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentsDisallow: false,
		})
		service := NewService(observability.NewNoopExporters(), nil, githubtwirp.NewNoopClient(), ffClient)

		result := service.IsEnabledForRepo(ctx, userID, ownerID, repoID)
		require.True(t, result, "should return true when use custom agents is enabled and disallow is explicitly false")
	})
}

func TestService_IsEnabledForRepoByName(t *testing.T) {
	ctx := context.Background()

	t.Run("returns error when repository cannot be fetched", func(t *testing.T) {
		userID := int64(123)
		repoOwner := "test-owner"
		repoName := "test-repo"

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghtwirp := githubtwirp.NewNoopClientWithRepositoryError()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		enabled, err := service.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
		require.Error(t, err)
		require.False(t, enabled)
		require.Contains(t, err.Error(), "failed to get repo")
	})

	t.Run("returns false when disallow feature flag is enabled", func(t *testing.T) {
		userID := int64(123)
		repoOwner := "test-owner"
		repoName := "test-repo"

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentsDisallow: true,
		})
		ghtwirp := githubtwirp.NewNoopClient()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		enabled, err := service.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
		require.NoError(t, err)
		require.False(t, enabled, "should return false when disallow flag is enabled")
	})

	t.Run("returns true when disallow is not enabled", func(t *testing.T) {
		userID := int64(123)
		repoOwner := "test-owner"
		repoName := "test-repo"

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghtwirp := githubtwirp.NewNoopClient()
		service := NewService(observability.NewNoopExporters(), nil, ghtwirp, ffClient)

		enabled, err := service.IsEnabledForRepoByName(ctx, userID, repoOwner, repoName)
		require.NoError(t, err)
		require.True(t, enabled, "should return true when use custom agents is enabled and disallow is not set")
	})
}
