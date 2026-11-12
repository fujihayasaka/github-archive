package features

import (
	"context"
	"fmt"
	"testing"

	featuresapi "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

type MockFeaturesAPI struct {
	mock.Mock
}

// CheckActorFeature checks whether a feature flag is enabled for a specific actor_id.
func (m *MockFeaturesAPI) CheckActorFeature(_ context.Context, _ *featuresapi.CheckActorFeatureRequest) (*featuresapi.CheckActorFeatureResponse, error) {
	panic("should never be called")
}

// CheckActorsFeature checks whether a feature flag is enabled for the specified actor_ids.
func (m *MockFeaturesAPI) CheckActorsFeature(ctx context.Context, request *featuresapi.CheckActorsFeatureRequest) (*featuresapi.CheckActorsFeatureResponse, error) {
	ret := m.Called(ctx, request)
	result, err := ret[0], ret[1]

	if err == nil {
		return result.(*featuresapi.CheckActorsFeatureResponse), nil
	} else {
		return nil, err.(error)
	}
}

func (m *MockFeaturesAPI) CheckActorFeatures(_ context.Context, _ *featuresapi.CheckActorFeaturesRequest) (*featuresapi.CheckActorFeaturesResponse, error) {
	return nil, fmt.Errorf("should never be called; only included for compatibility")
}

// CheckGlobalFeature checks whether a feature flag is enabled globally.
func (m *MockFeaturesAPI) CheckGlobalFeature(ctx context.Context, request *featuresapi.CheckGlobalFeatureRequest) (*featuresapi.CheckGlobalFeatureResponse, error) {
	ret := m.Called(ctx, request)
	result, err := ret[0], ret[1]

	if err == nil {
		return result.(*featuresapi.CheckGlobalFeatureResponse), nil
	} else {
		return nil, err.(error)
	}
}

const testFeatureFlag = "some_feature_flag"

func TestIsFeatureEnabledGlobally(t *testing.T) {
	tests := []struct {
		desc        string
		featureFlag string
		actors      []string
		featuresRes *featuresapi.CheckGlobalFeatureResponse
		returnedErr error
		want        []bool
	}{
		{
			desc:        "returns true when API returns true",
			featureFlag: testFeatureFlag,
			featuresRes: &featuresapi.CheckGlobalFeatureResponse{
				IsEnabled: true,
			},
			want: []bool{true},
		},
		{
			desc:        "returns false when API returns false",
			featureFlag: testFeatureFlag,
			featuresRes: &featuresapi.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			want: []bool{false},
		},
		{
			desc:        "returns an error when API returns an error",
			featureFlag: testFeatureFlag,
			returnedErr: fmt.Errorf("something went wrong"),
			want:        nil,
		},
		{
			desc:        "returns false when feature is disabled globally and actor is submitted",
			featureFlag: testFeatureFlag,
			featuresRes: &featuresapi.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			actors: []string{"User:12345"},
			want:   []bool{false},
		},
		{
			desc:        "calls global version when actors is an empty slice",
			featureFlag: testFeatureFlag,
			featuresRes: &featuresapi.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			actors: []string{},
			want:   []bool{false},
		},
		{
			desc:        "calls global version when actors is nil",
			featureFlag: testFeatureFlag,
			featuresRes: &featuresapi.CheckGlobalFeatureResponse{
				IsEnabled: false,
			},
			actors: []string(nil),
			want:   []bool{false},
		},
	}

	// Tests using the twirpFeaturesClient (legacy implementation)
	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			m := &MockFeaturesAPI{}
			c := twirpFeaturesClient{client: m}

			req := &featuresapi.CheckGlobalFeatureRequest{
				Feature: tt.featureFlag,
			}
			m.On("CheckGlobalFeature", mock.Anything, req).Return(tt.featuresRes, tt.returnedErr)

			results, err := c.IsFeatureFlagEnabled(context.Background(), tt.featureFlag)

			m.AssertCalled(t, "CheckGlobalFeature", mock.Anything, req)
			m.AssertNotCalled(t, "CheckActorsFeature", mock.Anything, mock.Anything)

			if tt.returnedErr != nil {
				// unhappy path
				assert.Error(t, err)
				assert.Empty(t, results)
			} else {
				// happy path
				assert.NoError(t, err)
				assert.Equal(t, tt.want, results)
			}
		})
	}
}

func TestIsFeatureEnabledForActors(t *testing.T) {
	tests := []struct {
		desc        string
		featureFlag string
		actors      []string
		featuresRes *featuresapi.CheckActorsFeatureResponse
		returnedErr error
		want        []bool
	}{
		{
			desc:        "returns true when API returns true",
			featureFlag: testFeatureFlag,
			actors:      []string{"User:12345"},
			featuresRes: &featuresapi.CheckActorsFeatureResponse{
				Results: []*featuresapi.ActorFeatureResult{
					{
						ActorId:   "User:12345",
						IsEnabled: true,
					},
				},
			},
			want: []bool{true},
		},
		{
			desc:        "returns accurate isEnabled array for mixed actor enablement",
			featureFlag: testFeatureFlag,
			actors:      []string{"User:12345", "User:54321"},
			featuresRes: &featuresapi.CheckActorsFeatureResponse{
				Results: []*featuresapi.ActorFeatureResult{
					{
						ActorId:   "User:12345",
						IsEnabled: true,
					},
					{
						ActorId:   "User:54321",
						IsEnabled: false,
					},
				},
			},
			want: []bool{true, false},
		},
		{
			desc:        "returns error when bad request",
			featureFlag: testFeatureFlag,
			actors:      []string{"Bogus:12345"},
			returnedErr: fmt.Errorf("bad actor"),
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			m := &MockFeaturesAPI{}
			c := twirpFeaturesClient{client: m}

			req := &featuresapi.CheckActorsFeatureRequest{
				Feature:  tt.featureFlag,
				ActorIds: tt.actors,
			}

			m.On("CheckActorsFeature", mock.Anything, req).Return(tt.featuresRes, tt.returnedErr)

			results, err := c.IsFeatureFlagEnabled(context.Background(), tt.featureFlag, tt.actors...)

			m.AssertCalled(t, "CheckActorsFeature", mock.Anything, req)
			m.AssertNotCalled(t, "CheckGlobalFeature", mock.Anything, mock.Anything)

			if tt.returnedErr != nil {
				// unhappy path
				assert.Error(t, err)
				assert.Empty(t, results)
			} else {
				// happy path
				assert.NoError(t, err)
				assert.Equal(t, tt.want, results)
			}
		})
	}
}
