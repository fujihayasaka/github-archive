package clients

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/errors"
)

type fcm struct {
	app     *firebase.App
	zeroTTL bool
}

var zero = time.Duration(0)

// NewFCMClient Initialize a new client that will send notifications to FCM
func NewFCMClient(app *firebase.App, cfg Config) MobileClient {
	return fcm{
		app:     app,
		zeroTTL: cfg.ZeroTTL,
	}
}

// SendNotification sends a notification to the given device tokens through Google FCM.
func (c fcm) SendNotification(ctx context.Context, notification Notification, deviceTokens devicetokens.Tokens) (Response, error) {
	messagingClient, err := c.app.Messaging(ctx)
	if err != nil {
		return buildFailedResponse(deviceTokens), errors.Wrap(err, "failed to create Firebase Messaging client")
	}

	message := CreateMulticastMessage(notification, deviceTokens, c.zeroTTL)
	batchResponse, err := messagingClient.SendEachForMulticast(ctx, message)
	if err != nil {
		return buildFailedResponse(deviceTokens), errors.Wrap(err, "failed to send Firebase Messaging multicast message")
	}

	return buildResponse(batchResponse, deviceTokens), nil
}

func buildResponse(batchResponse *messaging.BatchResponse, deviceTokens devicetokens.Tokens) Response {
	response := Response{}

	// The FCM documentation for the messaging API states that the order of the
	// responses in a batched response is the same as the order of the tokens.
	//
	// That's why we rely on the order to build the response.
	// See: https://firebase.google.com/docs/cloud-messaging/send-message#:~:text=%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20%C2%A0%20//%20The%20order%20of%20responses%20corresponds%20to%20the%20order%20of%20the%20registration%20tokens.
	for idx, r := range batchResponse.Responses {
		if r.Success {
			response.Delivered = append(response.Delivered, deviceTokens[idx])
		} else {
			response.Failed = append(response.Failed, deviceTokens[idx])
			if messaging.IsUnregistered(r.Error) {
				response.Unregistered = append(response.Unregistered, deviceTokens[idx])
			}
		}
	}

	response.DeliveredCount = batchResponse.SuccessCount
	response.FailedCount = batchResponse.FailureCount

	return response
}

func buildFailedResponse(deviceTokens devicetokens.Tokens) Response {
	return Response{
		FailedCount: len(deviceTokens),
		Failed:      deviceTokens,
	}
}

// Config represents the configuration for the FCM client.
type Config struct {
	PrivateKey string `config:",env=GOOGLE_FCM_PRIVATE_KEY,required"`
	// ZeroTTL will set the TTL of FCM messages to 0, disabling storage of messages by Google
	// at the cost of higher chance of notification losses.
	// See https://firebase.google.com/docs/cloud-messaging/concept-options#ttl for details.
	ZeroTTL bool `config:"false,env=GOOGLE_FCM_ZERO_TTL"`
	// LogRequests controls whether FCM client requests are logged.
	LogRequests bool `config:"false,env=GOOGLE_FCM_LOG_REQUESTS"`
}

// NewFirebaseApp returns a struct that handles the Google FCM credentials and
// that the FCM client uses to authenticate against FCM servers.
func NewFirebaseApp(ctx context.Context, cfg Config, telem *telemetry.Provider) (*firebase.App, error) {
	privateKey := []byte(cfg.PrivateKey)
	options := []option.ClientOption{option.WithCredentialsJSON(privateKey)}
	if cfg.LogRequests {
		options = append(options, option.WithHTTPClient(&http.Client{Transport: newLogger(telem)}))
	}
	app, err := firebase.NewApp(ctx, nil, options...)
	if err != nil {
		return nil, errors.Wrap(err, "initializing FCM app")
	}

	return app, nil
}

// CreateMulticastMessage creates a new FCM message for the given notification and device tokens.
func CreateMulticastMessage(notification Notification, deviceTokens devicetokens.Tokens, zeroTTL bool) *messaging.MulticastMessage {
	tokens := []string{}
	for _, t := range deviceTokens {
		tokens = append(tokens, t.DeviceToken)
	}

	// Title, Body, Url and Type are considered mandatory fields while the rest are considered optional.
	// Optional fields can be included in structs as they can be automatically omitted when empty,
	// but they have to be manually filtered in maps.
	// See https://github.com/github/notifyd/issues/3930 for details.
	msg := &messaging.MulticastMessage{
		Android: &messaging.AndroidConfig{
			Data: map[string]string{
				"title": notification.Title,
				"body":  notification.Body,
				"url":   notification.URL,
				"type":  notification.Type,
			},
		},
		APNS: &messaging.APNSConfig{
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Alert: &messaging.ApsAlert{
						Title:    notification.Title,
						SubTitle: notification.SubTitle,
						Body:     notification.Body,
					},
					Category:       notification.Type,
					MutableContent: true,
					Sound:          "default",
					ThreadID:       notification.ThreadID,
				},
			},
		},
		Data: map[string]string{
			"url": notification.URL,
		},
		Tokens: tokens,
	}

	if zeroTTL {
		msg.Android.TTL = &zero
		if msg.APNS.Headers == nil {
			msg.APNS.Headers = make(map[string]string)
		}
		msg.APNS.Headers["apns-expiration"] = "0"
		if msg.Webpush == nil {
			msg.Webpush = &messaging.WebpushConfig{Headers: make(map[string]string)}
		} else if msg.Webpush.Headers == nil {
			msg.Webpush.Headers = make(map[string]string)
		}
		msg.Webpush.Headers["TTL"] = "0"
	}

	if notification.SubTitle != "" {
		msg.Android.Data["subtitle"] = notification.SubTitle
	}

	maybeSet(msg, "avatar_url", notification.AvatarURL)
	maybeSet(msg, "author_username", notification.AuthorUsername)
	maybeSet(msg, "author_profile_name", notification.AuthorProfileName)
	maybeSet(msg, "thread_id", notification.ThreadID)
	maybeSet(msg, "thread_type", notification.ThreadType)
	maybeSet(msg, "username", notification.Username)
	maybeSet(msg, "subject_id", notification.SubjectID)

	return msg
}

func maybeSet(msg *messaging.MulticastMessage, key, value string) {
	if value != "" {
		msg.Android.Data[key] = value
		msg.Data[key] = value
	}
}

type logger struct {
	telem *telemetry.Provider
}

func newLogger(telem *telemetry.Provider) logger {
	return logger{telem: telem}
}

func (l logger) RoundTrip(req *http.Request) (*http.Response, error) {
	var body bytes.Buffer
	_, _ = io.Copy(&body, req.Body)
	l.telem.Logger.WithFields(kvp.String("gh.notifyd.request.body", body.String())).Info("sending an FCM API request")
	return http.DefaultTransport.RoundTrip(req)
}
