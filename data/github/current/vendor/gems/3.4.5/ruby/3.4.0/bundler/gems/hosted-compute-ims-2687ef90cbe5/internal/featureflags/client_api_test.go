package featureflags

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

var mockFeaturesApi *mocks_featureflags.MockFeaturesAPI

func setupFeaturesApi(ctx context.Context, t *testing.T) (*gomock.Controller, *apiClient) {
	ctrl := gomock.NewController(t)

	mockFeaturesApi = mocks_featureflags.NewMockFeaturesAPI(ctrl)

	client, err := newApiClient(ctx, "test-url", "test-hmac", "test-stamp")
	require.NoError(t, err)

	client.featuresAPI = mockFeaturesApi
	return ctrl, client
}

func TestFeatureFlagsClient_IsFeatureFlagEnabledGlobally(t *testing.T) {
	ctx := context.Background()

	t.Run("feature flag is enabled globally", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: true}, nil)

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, "feature1"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, "feature1")) // make sure that the second call is resolved from cache
	})

	t.Run("feature flag is disabled globally", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)

		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature1"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature1")) // make sure that the second call is resolved from cache
	})

	t.Run("failed to get feature flag state", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(2).Return(nil, fmt.Errorf("test"))

		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature1"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature1")) // make sure that the error is not cached
	})

	t.Run("every FF has own cache", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: true}, nil)
		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature2"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature3"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: true}, nil)

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, "feature1"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature2"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, "feature3"))

		// make sure that the second call is resolved from cache
		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, "feature1"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature2"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, "feature3"))
	})
}

func TestFeatureFlagsClient_IsFeatureFlagEnabledForOwner(t *testing.T) {
	ctx := context.Background()

	t.Run("feature flag is enabled globally", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: true}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, gomock.Any()).Times(0)

		actor, err := models.NewActorFromGlobalIdAndStamp("O_kgDOAu6jWA", "test")
		require.NoError(t, err)

		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor)) // make sure that the second call is resolved from cache
	})

	t.Run("feature flag is enabled for owner", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: true}, nil)

		actor, err := models.NewActorFromGlobalIdAndStamp("O_kgDOAu6jWA", "test")
		require.NoError(t, err)

		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor)) // make sure that the second call is resolved from cache
	})

	t.Run("feature flag is disabled for owner", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: false}, nil)

		actor, err := models.NewActorFromGlobalIdAndStamp("O_kgDOAu6jWA", "test")
		require.NoError(t, err)

		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor)) // make sure that the second call is resolved from cache
	})

	t.Run("failed to get feature flag state for owner", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(2).Return(nil, fmt.Errorf("test"))

		actor, err := models.NewActorFromGlobalIdAndStamp("O_kgDOAu6jWA", "test")
		require.NoError(t, err)

		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor)) // make sure that the error is not cached
	})

	t.Run("fallback to false if failed to decode owner id", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		actor, err := models.NewActorFromGlobalIdAndStamp("invalid_global_id", "test")
		require.Error(t, err)

		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor)) // make sure that the second call is resolved from cache
	})

	t.Run("every FF and user has own cache", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(ctx, t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: true}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Business:7347"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature2"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature2", ActorId: "Organization:49193816"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature2", ActorId: "Business:7347"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: true}, nil)

		actor1, err := models.NewActorFromGlobalIdAndStamp("O_kgDOAu6jWA", "test")
		require.NoError(t, err)
		actor2, err := models.NewActorFromGlobalIdAndStamp("E_kgDNHLM", "test")
		require.NoError(t, err)

		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor1))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor2))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature2", actor1))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature2", actor2))

		// make sure that the second call is resolved from cache
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor1))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", actor2))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature2", actor1))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature2", actor2))
	})
}
