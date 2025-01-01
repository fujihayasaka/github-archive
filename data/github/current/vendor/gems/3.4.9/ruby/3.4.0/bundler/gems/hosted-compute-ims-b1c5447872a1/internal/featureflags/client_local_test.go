package featureflags

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/stretchr/testify/assert"
)

func TestLocalFeatureFlagsClient(t *testing.T) {
	ctx := context.Background()
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)

	t.Run("simple case", func(t *testing.T) {
		client := newLocalClient(logger)

		client.EnableFeatureFlagGlobally(FeatureFlag_E2E_TestFlag_GloballyEnabled)
		client.EnableFeatureFlagForOwner(FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID)

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, FeatureFlag_E2E_TestFlag_GloballyDisabled))

		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, FeatureFlag_E2E_TestFlag_GloballyEnabled, "fake_user"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, FeatureFlag_E2E_TestFlag_GloballyDisabled, "fake_user"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, FeatureFlag_E2E_TestFlag_EnabledPerOwner, "fake_user"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "fake_flag", FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "fake_flag", "fake_user"))
	})

	t.Run("disabling flags", func(t *testing.T) {
		client := newLocalClient(logger)

		client.EnableFeatureFlagGlobally(FeatureFlag_E2E_TestFlag_GloballyEnabled)
		client.EnableFeatureFlagForOwner(FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID)

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID))

		client.DisableFeatureFlagGlobally(FeatureFlag_E2E_TestFlag_GloballyEnabled)
		client.DisableFeatureFlagForOwner(FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID)

		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID))
	})

	t.Run("reset flags", func(t *testing.T) {
		client := newLocalClient(logger)

		client.EnableFeatureFlagGlobally(FeatureFlag_E2E_TestFlag_GloballyEnabled)
		client.EnableFeatureFlagForOwner(FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID)

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID))

		client.Reset()

		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, FeatureFlag_E2E_TestFlag_EnabledPerOwner, FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID))
	})
}

func TestLocalFeatureFlagsClientFromConfig(t *testing.T) {
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)

	client := newLocalClientFromConfig(logger)
	assert.Greater(t, len(client.flagsGlobal), 0)
	assert.Greater(t, len(client.flagsPerOwner), 0)
}
