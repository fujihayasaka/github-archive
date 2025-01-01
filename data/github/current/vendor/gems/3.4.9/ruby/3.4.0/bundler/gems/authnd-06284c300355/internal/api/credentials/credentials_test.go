package credentials

import (
	"testing"

	"github.com/github/authnd/internal/api/validators"
	"github.com/github/authnd/internal/common/publisher"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/github/authnd/internal/mocks"
	"github.com/golang/mock/gomock"
)

func createTestMockPublisher(t *testing.T) *mocks.MockPratEventPublisher {
	t.Helper()

	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	mockPublisher := mocks.NewMockPratEventPublisher(ctrl)

	return mockPublisher
}

func createTestCredentialManager(t *testing.T, mockPublisher publisher.PratEventPublisher) *CredentialManager {
	t.Helper()

	if mockPublisher == nil {
		newMockPublisher := createTestMockPublisher(t)
		newMockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(0)
		mockPublisher = newMockPublisher
	}

	dataStore := testfixtures.AuthStore
	return &CredentialManager{
		store:     dataStore,
		publisher: mockPublisher,
		mint: &validators.MintTokenValidator{
			Store: dataStore,
		},
	}
}
