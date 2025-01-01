package clients

import (
	"context"
	"errors"
	"strings"

	"github.com/stretchr/testify/mock"

	"github.com/github/notifyd/internal/pkg/devicetokens"
)

// MobileMock implements a MobileClient that is successful by default.
type MobileMock struct {
	mock.Mock
}

// SendNotification builds a mocked response that passes unless the token
// contains the word `fail`. In that case it is counted as a partial failed
// response.
func (m *MobileMock) SendNotification(ctx context.Context, notification Notification, deviceTokens devicetokens.Tokens) (Response, error) {
	m.Called(notification, deviceTokens)

	responses := Response{}
	for _, token := range deviceTokens {
		if strings.Contains(token.DeviceToken, "fail") {
			responses.FailedCount++
			responses.Failed = append(responses.Failed, token)
		} else {
			responses.DeliveredCount++
			responses.Delivered = append(responses.Delivered, token)
		}
	}

	return responses, nil
}

// FailingMobileMock implements a MobileClient that always fails.
type FailingMobileMock struct {
	mock.Mock
}

// SendNotification builds a mocked response that passes unless the token
// contains the word `fail`. In that case it is counted as a partial failed
// response.
func (m *FailingMobileMock) SendNotification(ctx context.Context, notification Notification, deviceTokens devicetokens.Tokens) (Response, error) {
	m.Called(notification, deviceTokens)

	responses := Response{}
	for _, token := range deviceTokens {
		responses.FailedCount++
		responses.Failed = append(responses.Failed, token)
	}

	return responses, errors.New("ups")
}
