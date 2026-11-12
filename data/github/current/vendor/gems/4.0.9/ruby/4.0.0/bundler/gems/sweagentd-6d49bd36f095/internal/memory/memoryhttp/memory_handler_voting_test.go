package memoryhttp

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
)

// userOnlyFFClient is a test FF client where user flags differ from repo flags.
// IsEnabledForUser checks userFlags; IsEnabledForRepo delegates to the embedded
// NoopClient (which has no voting flags set), so repo checks return false.
type userOnlyFFClient struct {
	featureflags.Client

	userFlags map[string]bool
}

func (c *userOnlyFFClient) IsEnabledForUser(_ context.Context, flag string, _ int64) bool {
	return c.userFlags[flag]
}

func TestIsVotingEnabled(t *testing.T) {
	testRepo := &core.Repository{ID: 42}
	logger := log.NewNullLogger()

	ctxWithUser := func(integrationID string) context.Context {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), integrationID)
		return requestctx.AddData(ctx, &requestctx.CtxData{
			UserInfo: &requestctx.UserInfo{ID: 1, Login: "testuser"},
		})
	}

	const (
		nonCLIIntegration = "copilot-developer"
		cliIntegration    = "copilot-developer-cli"
	)

	nonCLIFlag := featureflags.CopilotSWEAgentMemoryVotingCodingAgent
	cliFlag := featureflags.CopilotSWEAgentMemoryVotingCLI

	t.Run("disabled when no feature flag client", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv: observability.NewNoopExporters(),
		})
		got := handler.isVotingEnabled(ctxWithUser(nonCLIIntegration), testRepo, logger, votingScopeRepoAndUser)
		assert.False(t, got)
	})

	t.Run("disabled when no user in context", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), nonCLIIntegration)
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv:              observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{nonCLIFlag: true}),
		})
		got := handler.isVotingEnabled(ctx, testRepo, logger, votingScopeRepoAndUser)
		assert.False(t, got)
	})

	t.Run("disabled when neither user nor repo voting flag enabled", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv:              observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{}),
		})
		got := handler.isVotingEnabled(ctxWithUser(nonCLIIntegration), testRepo, logger, votingScopeRepoAndUser)
		assert.False(t, got)
	})

	t.Run("enabled for non-CLI when repo voting flag set", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv:              observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{nonCLIFlag: true}),
		})
		got := handler.isVotingEnabled(ctxWithUser(nonCLIIntegration), testRepo, logger, votingScopeRepoAndUser)
		assert.True(t, got)
	})

	t.Run("enabled for non-CLI when user voting flag set and repo nil", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv:              observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{nonCLIFlag: true}),
		})
		got := handler.isVotingEnabled(ctxWithUser(nonCLIIntegration), nil, logger, votingScopeRepoAndUser)
		assert.True(t, got)
	})

	t.Run("repo only scope returns false when only user flag enabled", func(t *testing.T) {
		ffClient := &userOnlyFFClient{
			Client:    featureflags.NewNoopClient(map[string]bool{}),
			userFlags: map[string]bool{nonCLIFlag: true},
		}
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv:              observability.NewNoopExporters(),
			FeatureFlagClient: ffClient,
		})
		got := handler.isVotingEnabled(ctxWithUser(nonCLIIntegration), testRepo, logger, votingScopeRepoOnly)
		assert.False(t, got)
	})

	t.Run("repo and user scope returns true when only user flag enabled", func(t *testing.T) {
		ffClient := &userOnlyFFClient{
			Client:    featureflags.NewNoopClient(map[string]bool{}),
			userFlags: map[string]bool{nonCLIFlag: true},
		}
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv:              observability.NewNoopExporters(),
			FeatureFlagClient: ffClient,
		})
		got := handler.isVotingEnabled(ctxWithUser(nonCLIIntegration), testRepo, logger, votingScopeRepoAndUser)
		assert.True(t, got)
	})

	t.Run("repo only scope enabled when repo flag set", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv:              observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{nonCLIFlag: true}),
		})
		got := handler.isVotingEnabled(ctxWithUser(nonCLIIntegration), testRepo, logger, votingScopeRepoOnly)
		assert.True(t, got)
	})

	t.Run("CLI disabled when voting flag off", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv:              observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{}),
		})
		got := handler.isVotingEnabled(ctxWithUser(cliIntegration), testRepo, logger, votingScopeRepoAndUser)
		assert.False(t, got)
	})

	t.Run("CLI enabled when voting flag on", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv: observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{
				cliFlag: true,
			}),
		})
		got := handler.isVotingEnabled(ctxWithUser(cliIntegration), testRepo, logger, votingScopeRepoAndUser)
		assert.True(t, got)
	})

	t.Run("CLI repo only scope disabled when repo nil", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv: observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{
				cliFlag: true,
			}),
		})
		got := handler.isVotingEnabled(ctxWithUser(cliIntegration), nil, logger, votingScopeRepoOnly)
		assert.False(t, got)
	})

	t.Run("CLI repo only scope enabled when repo flag set", func(t *testing.T) {
		handler := NewMemoryHandler(MemoryHandlerOpts{
			Obsv: observability.NewNoopExporters(),
			FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{
				cliFlag: true,
			}),
		})
		got := handler.isVotingEnabled(ctxWithUser(cliIntegration), testRepo, logger, votingScopeRepoOnly)
		assert.True(t, got)
	})
}
