package featureflags

import (
	"context"

	"github.com/github/sweagentd/internal/sweagentd"
)

type publicRepoAutomationFlagger interface {
	IsEnabledForRepoOrOwnerWithDefaultValue(ctx context.Context, featureFlagName string, defaultValue bool, actors sweagentd.Repository) bool
}

// ShouldSkipPublicRepoAutomations reports whether public-repo automations should be blocked.
func ShouldSkipPublicRepoAutomations(ctx context.Context, ffClient publicRepoAutomationFlagger, actors sweagentd.Repository) bool {
	if ffClient == nil || actors == nil {
		return true
	}

	return ffClient.IsEnabledForRepoOrOwnerWithDefaultValue(ctx, CopilotAutomationsBlockPublicRepos, true, actors)
}
