package flipper_test

import (
	"context"
	"testing"

	"github.com/github/go-stats"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/github/turboghas/internal/flipper"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type featuresMock struct {
	mock.Mock
}

func (m *featuresMock) CheckActorFeature(ctx context.Context, k *twirpFeatures.CheckActorFeatureRequest) (*twirpFeatures.CheckActorFeatureResponse, error) {
	args := m.Called(ctx, k)
	return &twirpFeatures.CheckActorFeatureResponse{ActorId: k.ActorId, IsEnabled: args.Bool(0)}, args.Error(1)
}

func (m *featuresMock) CheckGlobalFeature(ctx context.Context, k *twirpFeatures.CheckGlobalFeatureRequest) (*twirpFeatures.CheckGlobalFeatureResponse, error) {
	args := m.Called(ctx, k)
	return &twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: args.Bool(0)}, args.Error(1)
}

func TestCache(t *testing.T) {
	api := &featuresMock{}
	api.On("CheckActorFeature", mock.Anything, &twirpFeatures.CheckActorFeatureRequest{Feature: "ghas_processor", ActorId: "Business:1"}).Return(true, nil).Once()
	api.On("CheckActorFeature", mock.Anything, &twirpFeatures.CheckActorFeatureRequest{Feature: "ghas_processor", ActorId: "Business:2"}).Return(false, nil).Once()

	api.On("CheckGlobalFeature", mock.Anything, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "ghas_processor_global"}).Return(true, nil).Once()
	api.On("CheckGlobalFeature", mock.Anything, &twirpFeatures.CheckGlobalFeatureRequest{Feature: "ghas_processor_global2"}).Return(false, nil).Once()

	f, err := flipper.New(api, stats.NullStatter)
	require.NoError(t, err)

	// Actor features

	{
		enabled, err := f.IsEnabled(context.Background(), "ghas_processor", "Business:1")
		require.NoError(t, err)
		require.True(t, enabled)
	}
	// second call should use the cache
	{
		enabled, err := f.IsEnabled(context.Background(), "ghas_processor", "Business:1")
		require.NoError(t, err)
		require.True(t, enabled)
	}
	{
		enabled, err := f.IsEnabled(context.Background(), "ghas_processor", "Business:2")
		require.NoError(t, err)
		require.False(t, enabled)
	}

	// Global features

	{
		enabled, err := f.IsGloballyEnabled(context.Background(), "ghas_processor_global")
		require.NoError(t, err)
		require.True(t, enabled)
	}
	// second call should use the cache
	{
		enabled, err := f.IsGloballyEnabled(context.Background(), "ghas_processor_global")
		require.NoError(t, err)
		require.True(t, enabled)
	}
	{
		enabled, err := f.IsGloballyEnabled(context.Background(), "ghas_processor_global2")
		require.NoError(t, err)
		require.False(t, enabled)
	}
}
