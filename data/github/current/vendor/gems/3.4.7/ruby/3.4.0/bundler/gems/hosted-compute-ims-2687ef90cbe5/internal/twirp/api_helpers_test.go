package twirp

import (
	"context"
	"testing"

	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/require"
)

func TestApiHelpers_IsCuratedImageDefinitionEnabledForActor(t *testing.T) {
	var (
		ctx               = context.Background()
		apiHelpers        = baseApiHandler{}
		defaultActor      = models.TEST_NewActorFromGlobaIdAndStamp(featureflags.TEST_FeatureFlag_FakeUser_GlobalID, "dotcom")
		defaultTwirpActor = &sharedapi.Actor{GlobalId: defaultActor.GlobalId()}
		invalidTwirpActor = &sharedapi.Actor{GlobalId: "invalid_global_id"}
	)

	featureFlagsClient := featureflags.TEST_SetupFeatureFlagsClient(t)

	t.Run("definition enabled", func(t *testing.T) {
		imageDef := &models.ImageDefinition{
			Id:          1,
			Enabled:     true,
			FeatureFlag: nil,
		}
		res := apiHelpers.isCuratedImageDefinitionEnabledForActor(ctx, imageDef, defaultTwirpActor)
		require.Equal(t, true, res)
	})

	t.Run("definition disabled", func(t *testing.T) {
		imageDef := &models.ImageDefinition{
			Id:          1,
			Enabled:     false,
			FeatureFlag: nil,
		}
		res := apiHelpers.isCuratedImageDefinitionEnabledForActor(ctx, imageDef, defaultTwirpActor)
		require.Equal(t, false, res)
	})

	t.Run("definition uses feature flag and disabled for actor", func(t *testing.T) {
		imageDef := &models.ImageDefinition{
			Id:          1,
			Enabled:     false,
			FeatureFlag: utils.ToPtr("test-feature-flag"),
		}

		featureFlagsClient.DisableFeatureFlagForActor(featureflags.FeatureFlag("test-feature-flag"), defaultActor.VexiID())

		res := apiHelpers.isCuratedImageDefinitionEnabledForActor(ctx, imageDef, defaultTwirpActor)
		require.Equal(t, false, res)
	})

	t.Run("definition uses feature flag and enabled for actor", func(t *testing.T) {
		imageDef := &models.ImageDefinition{
			Id:          1,
			Enabled:     false,
			FeatureFlag: utils.ToPtr("test-feature-flag"),
		}

		featureFlagsClient.EnableFeatureFlagForActor(featureflags.FeatureFlag("test-feature-flag"), defaultActor.VexiID())

		res := apiHelpers.isCuratedImageDefinitionEnabledForActor(ctx, imageDef, defaultTwirpActor)
		require.Equal(t, true, res)
	})

	t.Run("definition uses feature flag and invalid actor", func(t *testing.T) {
		imageDef := &models.ImageDefinition{
			Id:          1,
			Enabled:     false,
			FeatureFlag: utils.ToPtr("test-feature-flag"),
		}

		res := apiHelpers.isCuratedImageDefinitionEnabledForActor(ctx, imageDef, invalidTwirpActor)
		require.Equal(t, false, res)
	})
}

func TestApiHelpers_GetCustomerImageDefinitionsLimitForActor(t *testing.T) {
	var (
		ctx               = context.Background()
		apiHelpers        = baseApiHandler{}
		defaultActor      = models.TEST_NewActorFromGlobaIdAndStamp(featureflags.TEST_FeatureFlag_FakeUser_GlobalID, "dotcom")
		defaultTwirpActor = &sharedapi.Actor{GlobalId: defaultActor.GlobalId()}
		invalidTwirpActor = &sharedapi.Actor{GlobalId: "invalid_global_id"}
	)

	featureFlagsClient := featureflags.TEST_SetupFeatureFlagsClient(t)

	t.Run("return default limit if FF is disabled for actor", func(t *testing.T) {
		featureFlagsClient.DisableFeatureFlagForActor(featureflags.FeatureFlag_CustomerImageDefinitionsLimitIncrease, defaultActor.VexiID())

		limit := apiHelpers.getCustomerImageDefinitionsLimitForActor(ctx, defaultTwirpActor)
		require.Equal(t, 50, limit)
	})

	t.Run("return increased limit if FF is enabled for actor", func(t *testing.T) {
		featureFlagsClient.EnableFeatureFlagForActor(featureflags.FeatureFlag_CustomerImageDefinitionsLimitIncrease, defaultActor.VexiID())

		limit := apiHelpers.getCustomerImageDefinitionsLimitForActor(ctx, defaultTwirpActor)
		require.Equal(t, 250, limit)
	})

	t.Run("return default limit if actor is invalid", func(t *testing.T) {
		limit := apiHelpers.getCustomerImageDefinitionsLimitForActor(ctx, invalidTwirpActor)
		require.Equal(t, 50, limit)
	})
}

func TestApiHelpers_GetCustomerImageVersionsLimitForActor(t *testing.T) {
	var (
		ctx               = context.Background()
		apiHelpers        = baseApiHandler{}
		defaultActor      = models.TEST_NewActorFromGlobaIdAndStamp(featureflags.TEST_FeatureFlag_FakeUser_GlobalID, "dotcom")
		defaultTwirpActor = &sharedapi.Actor{GlobalId: defaultActor.GlobalId()}
		invalidTwirpActor = &sharedapi.Actor{GlobalId: "invalid_global_id"}
	)

	featureFlagsClient := featureflags.TEST_SetupFeatureFlagsClient(t)

	t.Run("return default limit if FF is disabled for actor", func(t *testing.T) {
		featureFlagsClient.DisableFeatureFlagForActor(featureflags.FeatureFlag_CustomerImageVersionsLimitIncrease, defaultActor.VexiID())

		limit := apiHelpers.getCustomerImageVersionsLimitForActor(ctx, defaultTwirpActor)
		require.Equal(t, int32(50), limit)
	})

	t.Run("return increased limit if FF is enabled for actor", func(t *testing.T) {
		featureFlagsClient.EnableFeatureFlagForActor(featureflags.FeatureFlag_CustomerImageVersionsLimitIncrease, defaultActor.VexiID())

		limit := apiHelpers.getCustomerImageVersionsLimitForActor(ctx, defaultTwirpActor)
		require.Equal(t, int32(250), limit)
	})

	t.Run("return default limit if actor is invalid", func(t *testing.T) {
		limit := apiHelpers.getCustomerImageVersionsLimitForActor(ctx, invalidTwirpActor)
		require.Equal(t, int32(50), limit)
	})
}
