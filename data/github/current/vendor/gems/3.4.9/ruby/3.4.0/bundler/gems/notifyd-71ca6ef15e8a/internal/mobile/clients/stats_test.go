package clients

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	ghstats "github.com/github/go-stats"
	"github.com/github/go-stats/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/devicetokens"
)

func TestClient_SendNotification(t *testing.T) {
	ctx := context.Background()
	r := require.New(t)
	notification := Notification{}
	tokens := devicetokens.Tokens{{ID: 1, UserID: 1, DeviceToken: "1"}}

	t.Run("when it success sending the push", func(t *testing.T) {
		mockClient := new(MobileMock)
		statter := mocks.NewClient(t)
		clock := clock.NewMock()
		client := NewStatsClient(mockClient, clock, statter)
		mockClient.On("SendNotification", notification, tokens).
			Run(func(mock.Arguments) { clock.Add(5 * time.Second) })
		statter.On("DistributionMs", "push_notifications.time", ghstats.Tags{"status": "success"}, 5*time.Second)
		statter.On("Counter", "push_notifications.count", ghstats.Tags{"status": "success"}, int64(1))
		statter.On("Counter", "push_notifications.tokens.count", ghstats.Tags{"status": "delivered"}, int64(1))
		statter.On("Counter", "push_notifications.tokens.count", ghstats.Tags{"status": "failed"}, int64(0))

		response, err := client.SendNotification(ctx, notification, tokens)
		r.NoError(err)
		mockClient.AssertExpectations(t)
		r.Len(tokens, response.DeliveredCount)
	})

	t.Run("when it fails sending the push", func(t *testing.T) {
		mockClient := new(FailingMobileMock)
		statter := mocks.NewClient(t)
		clock := clock.NewMock()
		client := NewStatsClient(mockClient, clock, statter)
		mockClient.On("SendNotification", notification, tokens).
			Run(func(mock.Arguments) { clock.Add(5 * time.Second) }).
			Return(Response{}, errors.New("ups"))
		statter.On("DistributionMs", "push_notifications.time", ghstats.Tags{"status": "failed"}, 5*time.Second)
		statter.On("Counter", "push_notifications.count", ghstats.Tags{"status": "failed"}, int64(1))
		statter.On("Counter", "push_notifications.tokens.count", ghstats.Tags{"status": "delivered"}, int64(0))
		statter.On("Counter", "push_notifications.tokens.count", ghstats.Tags{"status": "failed"}, int64(1))

		_, err := client.SendNotification(ctx, notification, tokens)
		r.Error(err, "ups")
		mockClient.AssertExpectations(t)
	})
}
