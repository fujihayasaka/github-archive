package featureflags

import (
	"context"
	"maps"

	"github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/sweagentd/internal/sweagentd"
)

// NoopClient is a no-operation feature flag client for testing.
type NoopClient struct {
	flags map[string]bool
	appID int64
}

// NewNoopClient creates a new no-operation feature flag client.
func NewNoopClient(flags map[string]bool) Client {
	flagsToReturn := map[string]bool{
		CopilotSWEAgentIntegrationCodeScanningAlerts: true,
	}
	maps.Copy(flagsToReturn, flags)
	return &NoopClient{
		flags: flagsToReturn,
	}
}

// NewNoopClientWithAppID creates a new no-operation feature flag client with an app ID.
func NewNoopClientWithAppID(flags map[string]bool, appID int64) Client {
	flagsToReturn := map[string]bool{
		CopilotSWEAgentIntegrationCodeScanningAlerts: true,
	}
	maps.Copy(flagsToReturn, flags)
	return &NoopClient{
		flags: flagsToReturn,
		appID: appID,
	}
}

// IsEnabled checks if a feature flag is enabled (no-op implementation).
func (c *NoopClient) IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool {
	f, ok := c.flags[featureFlagName]
	if !ok {
		return false
	}
	return f
}

// IsEnabledForUser checks if a feature flag is enabled for a user (no-op implementation).
func (c *NoopClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

// IsEnabledForRepo checks if a feature flag is enabled for a repository (no-op implementation).
func (c *NoopClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

// IsEnabledForUserOrRepo checks if a feature flag is enabled for a user or repository (no-op implementation).
func (c *NoopClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

// IsEnabledForRepoOrOwner checks if a feature flag is enabled for a repository or its owner using the sweagentd.Repository interface (no-op implementation).
func (c *NoopClient) IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

// IsEnabledForUserOrRepoOrOwner checks if a feature flag is enabled for a user, repository, or repository owner using the sweagentd.RepositoryWithActor interface (no-op implementation).
func (c *NoopClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

// IsEnabledForGitHubApp checks if a feature flag is enabled for a GitHub App (no-op implementation).
func (c *NoopClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return c.IsEnabled(ctx, featureFlagName) && c.appID == appID
}

// IsEnabledForOAuthApp checks if a feature flag is enabled for an OAuth App (no-op implementation).
func (c *NoopClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return c.IsEnabled(ctx, featureFlagName) && c.appID == appID
}
