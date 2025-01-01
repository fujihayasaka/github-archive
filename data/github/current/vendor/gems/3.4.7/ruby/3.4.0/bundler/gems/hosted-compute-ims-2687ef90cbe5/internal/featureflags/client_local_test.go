package featureflags

import (
	"context"
	"testing"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
)

type FakeActor struct {
	id    string
	stamp string
}

func (a *FakeActor) VexiID() string {
	return a.id
}

func (a *FakeActor) GlobalId() string {
	return a.id
}

func (a *FakeActor) Stamp() string {
	return a.stamp
}

func (a *FakeActor) DotcomActor() models.DotcomActor {
	return "User:fake_user"
}

func getFakeUserActor() models.Actor {
	return &FakeActor{id: "fake_user", stamp: ""}
}

func TestLocalFeatureFlagsClient(t *testing.T) {
	ctx := context.Background()

	t.Run("simple case", func(t *testing.T) {
		client := newLocalClient()

		client.EnableFeatureFlagGlobally(TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled)
		client.EnableFeatureFlagForActor(TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor().VexiID())

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, TEST_FeatureFlag_E2E_TestFlag_GloballyDisabled))

		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled, getFakeUserActor()))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, TEST_FeatureFlag_E2E_TestFlag_GloballyDisabled, getFakeUserActor()))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor()))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, &FakeActor{id: "fake_user_2", stamp: ""}))
	})

	t.Run("disabling flags", func(t *testing.T) {
		client := newLocalClient()

		client.EnableFeatureFlagGlobally(TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled)
		client.EnableFeatureFlagForActor(TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor().VexiID())

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor()))

		client.DisableFeatureFlagGlobally(TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled)
		client.DisableFeatureFlagForActor(TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor().VexiID())

		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor()))
	})

	t.Run("reset flags", func(t *testing.T) {
		client := newLocalClient()

		client.EnableFeatureFlagGlobally(TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled)
		client.EnableFeatureFlagForActor(TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor().VexiID())

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor()))

		client.Reset()

		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner, getFakeUserActor()))
	})
}

func TestLocalFeatureFlagsClientFromConfig(t *testing.T) {
	ctx := context.Background()
	client := newLocalClientFromConfig(ctx)
	assert.Greater(t, len(client.flagsGlobal), 0)
	assert.Greater(t, len(client.flagsPerActor), 0)
}
