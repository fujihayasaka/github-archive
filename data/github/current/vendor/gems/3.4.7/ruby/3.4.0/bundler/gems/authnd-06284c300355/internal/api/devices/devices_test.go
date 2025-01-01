package devices

import (
	"testing"
	"time"

	"github.com/github/authnd/internal/common/publisher"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/github/authnd/internal/mocks"
	"github.com/golang/mock/gomock"
)

func createTestMockPublisher(t *testing.T) *mocks.MockNotificationPublisher {
	t.Helper()

	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	mockPublisher := mocks.NewMockNotificationPublisher(ctrl)

	return mockPublisher
}

func createTestMobileDeviceManager(t *testing.T, now time.Time, mockPublisher publisher.NotificationPublisher) *MobileDeviceManager {
	t.Helper()

	return &MobileDeviceManager{
		store:     testfixtures.AuthStore,
		publisher: mockPublisher,
		nowFunc: func() time.Time {
			return now
		},
	}
}
