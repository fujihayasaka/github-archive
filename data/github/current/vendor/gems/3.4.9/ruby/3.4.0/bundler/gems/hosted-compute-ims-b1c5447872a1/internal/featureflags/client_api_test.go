package featureflags

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_featureflags"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

var mockFeaturesApi *mocks_featureflags.MockFeaturesAPI

func setupFeaturesApi(t *testing.T) (*gomock.Controller, *apiClient) {
	ctrl := gomock.NewController(t)
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)

	mockFeaturesApi = mocks_featureflags.NewMockFeaturesAPI(ctrl)

	client, err := newApiClient("test-url", "test-hmac", "test-stamp", logger)
	require.NoError(t, err)

	client.featuresAPI = mockFeaturesApi
	return ctrl, client
}

func TestFeatureFlagsClient_IsFeatureFlagEnabledGlobally(t *testing.T) {
	ctx := context.Background()

	t.Run("feature flag is enabled globally", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: true}, nil)

		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, "feature1"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledGlobally(ctx, "feature1")) // make sure that the second call is resolved from cache
	})

	t.Run("feature flag is disabled globally", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)

		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature1"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature1")) // make sure that the second call is resolved from cache
	})

	t.Run("failed to get feature flag state", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(2).Return(nil, fmt.Errorf("test"))

		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature1"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledGlobally(ctx, "feature1")) // make sure that the error is not cached
	})

	t.Run("every FF has own cache", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
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
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: true}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, gomock.Any()).Times(0)

		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA")) // make sure that the second call is resolved from cache
	})

	t.Run("feature flag is enabled for owner", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: true}, nil)

		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA")) // make sure that the second call is resolved from cache
	})

	t.Run("feature flag is disabled for owner", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: false}, nil)

		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA")) // make sure that the second call is resolved from cache
	})

	t.Run("failed to get feature flag state for owner", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(2).Return(nil, fmt.Errorf("test"))

		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA")) // make sure that the error is not cached
	})

	t.Run("fallback to false if failed to decode owner id", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(0)

		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "fake"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "fake")) // make sure that the second call is resolved from cache
	})

	t.Run("every FF and user has own cache", func(t *testing.T) {
		ctrl, client := setupFeaturesApi(t)
		defer ctrl.Finish()

		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Organization:49193816"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: true}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "Business:7347"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature2"}).Times(1).Return(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature2", ActorId: "Organization:49193816"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: false}, nil)
		mockFeaturesApi.EXPECT().CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{Feature: "feature2", ActorId: "Business:7347"}).Times(1).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: true}, nil)

		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "E_kgDNHLM"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature2", "O_kgDOAu6jWA"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature2", "E_kgDNHLM"))

		// make sure that the second call is resolved from cache
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "O_kgDOAu6jWA"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature1", "E_kgDNHLM"))
		assert.Equal(t, false, client.IsFeatureFlagEnabledForActor(ctx, "feature2", "O_kgDOAu6jWA"))
		assert.Equal(t, true, client.IsFeatureFlagEnabledForActor(ctx, "feature2", "E_kgDNHLM"))
	})
}
