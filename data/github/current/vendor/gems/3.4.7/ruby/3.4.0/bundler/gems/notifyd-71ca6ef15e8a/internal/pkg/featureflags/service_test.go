package featureflags

import (
	"context"
	"errors"
	"testing"

	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestIsEnabled(t *testing.T) {
	ctx := context.Background()
	r := require.New(t)

	t.Run("returns true when flag is globally enabled", func(*testing.T) {
		featureflagMock := new(featuresClientMock)
		req := &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}
		mockResp := twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: true}
		featureflagMock.On("CheckGlobalFeature", mock.Anything, req).Return(&mockResp, nil)

		client := DotcomClient{FeaturesAPI: featureflagMock}

		resp, err := client.IsEnabled(ctx, "feature1")
		r.NoError(err)
		r.True(resp)
	})

	t.Run("returns false when flag is globally disabled", func(*testing.T) {
		featureflagMock := new(featuresClientMock)
		req := &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}
		mockResp := twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false}
		featureflagMock.On("CheckGlobalFeature", mock.Anything, req).Return(&mockResp, nil)

		client := DotcomClient{FeaturesAPI: featureflagMock}

		resp, err := client.IsEnabled(ctx, "feature1")
		r.NoError(err)
		r.False(resp)
	})

	t.Run("returns error when network request errors", func(*testing.T) {
		featureflagMock := new(featuresClientMock)
		req := &twirpFeatures.CheckGlobalFeatureRequest{Feature: "feature1"}
		expectedError := errors.New("boom")
		featureflagMock.On("CheckGlobalFeature", mock.Anything, req).Return(nil, expectedError)
		client := DotcomClient{FeaturesAPI: featureflagMock}

		_, err := client.IsEnabled(ctx, "feature1")
		r.ErrorIs(err, expectedError)
	})
}

func TestIsEnabledForActor(t *testing.T) {
	ctx := context.Background()
	r := require.New(t)

	t.Run("returns true when flag is enabled for actor", func(*testing.T) {
		featureflagMock := new(featuresClientMock)
		req := &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "User:1"}
		mockResp := twirpFeatures.CheckActorFeatureResponse{ActorId: "1", IsEnabled: true}
		featureflagMock.On("CheckActorFeature", mock.Anything, req).Return(&mockResp, nil)

		client := DotcomClient{FeaturesAPI: featureflagMock}

		resp, err := client.IsEnabledForActor(ctx, "feature1", 1)
		r.NoError(err)
		r.True(resp)
	})

	t.Run("returns false when flag is disabled for actor", func(*testing.T) {
		featureflagMock := new(featuresClientMock)
		req := &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "User:1"}
		mockResp := twirpFeatures.CheckActorFeatureResponse{ActorId: "1", IsEnabled: false}
		featureflagMock.On("CheckActorFeature", mock.Anything, req).Return(&mockResp, nil)

		client := DotcomClient{FeaturesAPI: featureflagMock}

		resp, err := client.IsEnabledForActor(ctx, "feature1", 1)
		r.NoError(err)
		r.False(resp)
	})

	t.Run("returns error when network request errors", func(*testing.T) {
		featureflagMock := new(featuresClientMock)
		req := &twirpFeatures.CheckActorFeatureRequest{Feature: "feature1", ActorId: "User:1"}
		expectedError := errors.New("boom")
		featureflagMock.On("CheckActorFeature", mock.Anything, req).Return(nil, expectedError)
		client := DotcomClient{FeaturesAPI: featureflagMock}

		_, err := client.IsEnabledForActor(ctx, "feature1", 1)
		r.ErrorIs(err, expectedError)
	})
}

func TestIsEnabledForActors(t *testing.T) {
	ctx := context.Background()
	r := require.New(t)

	t.Run("returns map of user ids to booleans as to whether the user is enabled or not", func(*testing.T) {
		featureflagMock := new(featuresClientMock)
		req := &twirpFeatures.CheckActorsFeatureRequest{Feature: "feature1", ActorIds: []string{"User:1", "User:2"}}
		mockResp := twirpFeatures.CheckActorsFeatureResponse{
			Results: []*twirpFeatures.ActorFeatureResult{
				{ActorId: "User:1", IsEnabled: true},
				{ActorId: "User:2", IsEnabled: false},
			},
		}
		featureflagMock.On("CheckActorsFeature", mock.Anything, req).Return(&mockResp, nil)

		client := DotcomClient{FeaturesAPI: featureflagMock}

		resp, err := client.IsEnabledForActors(ctx, "feature1", []int64{1, 2})
		r.NoError(err)
		r.Equal(map[string]bool{"User:1": true, "User:2": false}, resp)
	})

	t.Run("returns error when network request errors", func(*testing.T) {
		featureflagMock := new(featuresClientMock)
		req := &twirpFeatures.CheckActorsFeatureRequest{Feature: "feature1", ActorIds: []string{"User:1", "User:2"}}
		expectedError := errors.New("boom")
		featureflagMock.On("CheckActorsFeature", mock.Anything, req).Return(nil, expectedError)
		client := DotcomClient{FeaturesAPI: featureflagMock}

		_, err := client.IsEnabledForActors(ctx, "feature1", []int64{1, 2})
		r.ErrorIs(err, expectedError)
	})
}
