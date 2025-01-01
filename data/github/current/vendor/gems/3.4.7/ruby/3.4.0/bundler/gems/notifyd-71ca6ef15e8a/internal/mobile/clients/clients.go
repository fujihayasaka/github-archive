// Package clients implements mobile clients used to send push notifications.
package clients

import (
	"context"

	"github.com/github/notifyd/internal/pkg/devicetokens"
)

// Notification represents a push notification.
type Notification struct {
	NotificationID    string
	UserID            int64
	SubjectID         string
	Title             string
	SubTitle          string
	Body              string
	URL               string
	Type              string
	AvatarURL         string
	AuthorProfileName string
	AuthorUsername    string
	ThreadID          string
	ThreadType        string
	Username          string
}

// MobileClient is the interface that defines how we send a push notification.
//
// A MobileClient sends the passed notification to all passed deviceTokens. It returns
// a Response specifying the result of the delivery for each one of the tokens.
//
// If an error happens it returns the error and a response indicating that it
// has failed for all the tokens.
type MobileClient interface {
	SendNotification(ctx context.Context, notification Notification, deviceTokens devicetokens.Tokens) (Response, error)
}

// Response represents the result of a sent notification for each one of the
// given tokens.
type Response struct {
	FailedCount    int
	DeliveredCount int
	Failed         devicetokens.Tokens
	Delivered      devicetokens.Tokens
	Unregistered   devicetokens.Tokens
}
