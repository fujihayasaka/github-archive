package clients

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

type logging struct {
	telem *telemetry.Provider
}

// NewLoggingClient initializes a push MobileClient that logs notifications to the logger
// instead of sending anything to a real device.
func NewLoggingClient(telem *telemetry.Provider) MobileClient {
	return logging{telem: telem}
}

// SendNotification sends a notification to all devices listed in the deviceTokens slice.
// It always returns a successful Response for all deviceTokens
func (c logging) SendNotification(ctx context.Context, notification Notification, deviceTokens devicetokens.Tokens) (Response, error) {
	message := CreateMulticastMessage(notification, deviceTokens, false)
	title := message.APNS.Payload.Aps.Alert.Title
	subTitle := message.APNS.Payload.Aps.Alert.SubTitle
	category := message.APNS.Payload.Aps.Category
	tokens := fmtDeviceTokensForLogs(message.Tokens)

	c.telem.Logger.WithContext(ctx).Info(
		"Fake FCM message",
		kvp.String("title", title),
		kvp.String("subtitle", subTitle),
		kvp.String("tokens", tokens),
		kvp.String("category", category),
	)

	return Response{
		DeliveredCount: len(deviceTokens),
		Delivered:      deviceTokens,
	}, nil
}

// fmtDeviceTokensForLogs turns a slice of device tokens into a formatted string, obfuscating the
// tokens.
func fmtDeviceTokensForLogs(deviceToken []string) string {
	var truncated []string

	for _, token := range deviceToken {
		formatedToken := fmt.Sprintf("%q", logs.Obfuscate(token))
		truncated = append(truncated, formatedToken)
	}
	return fmt.Sprintf("[%s]", strings.Join(truncated, ", "))
}
