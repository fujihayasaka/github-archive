package clients

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func Test_LoggingClient(t *testing.T) {
	r := require.New(t)
	notification := Notification{
		Title:    "@mikrobi mentioned you",
		SubTitle: "Issue #1",
		URL:      "https://github.com/github/github/issues/1",
		Type:     "mention",
	}
	tokens := devicetokens.Tokens{{DeviceToken: "device-token"}}

	client := NewLoggingClient(logs.NullTelem)
	response, err := client.SendNotification(context.Background(), notification, tokens)
	r.NoError(err)
	r.Equal(1, response.DeliveredCount)
	r.Equal(tokens, response.Delivered)
	r.Equal(0, response.FailedCount)
	r.Nil(response.Failed)
}
