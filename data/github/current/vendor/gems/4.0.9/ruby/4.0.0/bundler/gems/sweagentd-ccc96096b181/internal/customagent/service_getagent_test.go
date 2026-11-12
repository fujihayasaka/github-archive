package customagent

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func TestService_GetAgent(t *testing.T) {
	ctx := context.Background()
	userID := uint64(123)
	repoID := uint64(2) // This is the ID that noop client returns for .github
	repoOwner := "test-owner"
	repoName := ".github" // Use org repo that exists in twirp noop client
	agentName := "test-agent"
	version := ""

	t.Run("returns agent when user is authorized and agent exists", func(t *testing.T) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, repoOwner, repoName, agentName, version, GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, agentName, result.Name())
		require.Equal(t, "Test Agent", result.DisplayName())
		require.Equal(t, "A test agent", result.Description())
		require.Equal(t, int64(repoID), result.RepoID())

		// Test GetAgentByRepoID as well
		result, err = service.GetAgentByRepoID(ctx, repoID, agentName, version, GetAgentOpts{UserID: userID})
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, agentName, result.Name())
		require.Equal(t, "Test Agent", result.DisplayName())
		require.Equal(t, "A test agent", result.Description())
		require.Equal(t, int64(repoID), result.RepoID())
	})

	t.Run("returns ErrRequestedAgentNotFound when user is not authorized", func(t *testing.T) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, repoOwner, repoName, agentName, version, GetAgentOpts{UserID: userID})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)

		// Test GetAgentByRepoID as well
		result, err = service.GetAgentByRepoID(ctx, repoID, agentName, version, GetAgentOpts{UserID: userID})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("returns error when repository is not found", func(t *testing.T) {
		spokes := makeSpokesWithAgents(t, map[string]string{})

		// Mock GitHub twirp client that returns repository not found
		ghtwirp := githubtwirp.NewNoopClientWithRepositoryError()

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, repoOwner, "non-existent-repo", agentName, version, GetAgentOpts{UserID: userID})
		// The error should reflect the underlying GitHub repository access/API error, so it must not be the internal ErrRepoNotFound sentinel.
		require.NotErrorIs(t, err, ErrRepoNotFound)
		require.Nil(t, result)

		// Test GetAgentByRepoID as well
		result, err = service.GetAgentByRepoID(ctx, 9999, agentName, version, GetAgentOpts{UserID: userID})
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

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, repoOwner, repoName, agentName, version, GetAgentOpts{UserID: userID})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)

		// Test GetAgentByRepoID as well
		result, err = service.GetAgentByRepoID(ctx, repoID, agentName, version, GetAgentOpts{UserID: userID})
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

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, repoOwner, repoName, agentName, version, GetAgentOpts{UserID: userID})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)

		// Test GetAgentByRepoID as well
		result, err = service.GetAgentByRepoID(ctx, repoID, agentName, version, GetAgentOpts{UserID: userID})
		require.ErrorIs(t, err, ErrRequestedAgentNotFound)
		require.Nil(t, result)
	})

	t.Run("handles agent configuration parsing errors", func(t *testing.T) {
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

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp, ffClient)

		result, err := service.GetAgent(ctx, repoOwner, repoName, agentName, version, GetAgentOpts{UserID: userID})
		require.Error(t, err)
		require.Nil(t, result)

		// Test GetAgentByRepoID as well
		result, err = service.GetAgentByRepoID(ctx, repoID, agentName, version, GetAgentOpts{UserID: userID})
		require.Error(t, err)
		require.Nil(t, result)
	})
}
