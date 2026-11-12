package features

import (
	"context"
	"os"
	"strings"
)

// enabledFlagOverrides returns the set of feature flags that should be
// force-enabled via the ENABLED_FEATURE_FLAGS environment variable.
// This is intended for integration testing where specific flags need to be
// enabled without using DEV_STANDALONE_MODE (which also mocks Spokes).
func enabledFlagOverrides() map[string]bool {
	env := os.Getenv("ENABLED_FEATURE_FLAGS")
	if env == "" {
		return nil
	}

	overrides := make(map[string]bool)
	for _, flag := range strings.Split(env, ",") {
		if flag = strings.TrimSpace(flag); flag != "" {
			overrides[flag] = true
		}
	}
	return overrides
}

// flagOverrideClient wraps a Client and returns true for any feature flag
// listed in the overrides set, delegating all other checks to the inner client.
type flagOverrideClient struct {
	inner     Client
	overrides map[string]bool
}

func (c *flagOverrideClient) IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error) {
	if c.overrides[feature] {
		results := make([]bool, len(actors))
		for i := range results {
			results[i] = true
		}
		return results, nil
	}
	return c.inner.IsFeatureFlagEnabled(ctx, feature, actors...)
}

func (c *flagOverrideClient) IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error) {
	if c.overrides[feature] {
		return true, nil
	}
	return c.inner.IsFeatureFlagEnabledForRepository(ctx, feature, repositoryID)
}

func (c *flagOverrideClient) IsFeatureFlagEnabledForUser(ctx context.Context, feature string, userID uint64) (bool, error) {
	if c.overrides[feature] {
		return true, nil
	}
	return c.inner.IsFeatureFlagEnabledForUser(ctx, feature, userID)
}

func (c *flagOverrideClient) IsFeatureFlagEnabledForOrganization(ctx context.Context, feature string, organizationID uint64) (bool, error) {
	if c.overrides[feature] {
		return true, nil
	}
	return c.inner.IsFeatureFlagEnabledForOrganization(ctx, feature, organizationID)
}
