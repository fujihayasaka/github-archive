// This file contains a mock implementation of the gitaccess.Client interface
// that is used for tests and standalone mode. It sidesteps the hard dependency
// on the monolith that would otherwise make it cumbersome to run the service for local
// development.
package mock

import (
	"context"

	"github.com/stretchr/testify/mock"
)

type MockFeaturesClient struct {
	mock.Mock
}

func (m *MockFeaturesClient) IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error) {
	args := m.Called(ctx, feature, actors)
	return args.Get(0).([]bool), args.Error(1)
}

func (m *MockFeaturesClient) IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error) {
	args := m.Called(ctx, feature, repositoryID)
	return args.Get(0).(bool), args.Error(1)
}

func NewMockFeaturesClient() *MockFeaturesClient {
	c := &MockFeaturesClient{}
	return c
}

func NewFeaturesClientAllOff() *MockFeaturesClient {
	featuresClient := NewMockFeaturesClient()
	featuresClient.Mock.On("IsFeatureFlagEnabledForRepository",
		mock.Anything,                 // context
		mock.AnythingOfType("string"), // feature name
		mock.AnythingOfType("uint64"), // repository id
	).Return(false, nil)
	return featuresClient
}

func NewFeaturesClientAllOn() *MockFeaturesClient {
	featuresClient := NewMockFeaturesClient()
	featuresClient.Mock.On("IsFeatureFlagEnabledForRepository",
		mock.Anything,                 // context
		mock.AnythingOfType("string"), // feature name
		mock.AnythingOfType("uint64"), // repository id
	).Return(true, nil)
	return featuresClient
}
