package clients

import (
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/devicetokens"
)

func TestCreateMulticastMessage(t *testing.T) {
	r := require.New(t)
	notification := Notification{
		Title:             "@mikrobi mentioned you",
		SubTitle:          "Issue #123",
		URL:               "https://github.com/github/github/issues/123",
		Type:              "mention",
		AvatarURL:         "https://github.com/mikrobi.png",
		AuthorUsername:    "mikrobi",
		AuthorProfileName: "Jakob",
		ThreadID:          "I_123",
		ThreadType:        "Issue",
		Username:          "haldun",
		SubjectID:         "123",
	}

	deviceTokens := devicetokens.Tokens{
		{DeviceToken: "device-token-1"},
		{DeviceToken: "device-token-2"},
	}

	fcmNotification := CreateMulticastMessage(notification, deviceTokens, false)

	r.Equal(map[string]string{
		"url":                 notification.URL,
		"avatar_url":          notification.AvatarURL,
		"author_username":     notification.AuthorUsername,
		"author_profile_name": notification.AuthorProfileName,
		"thread_id":           notification.ThreadID,
		"thread_type":         notification.ThreadType,
		"username":            notification.Username,
		"subject_id":          notification.SubjectID,
	}, fcmNotification.Data)

	r.Equal(&messaging.ApsAlert{
		Title:    notification.Title,
		SubTitle: notification.SubTitle,
		Body:     notification.Body,
	}, fcmNotification.APNS.Payload.Aps.Alert)
	r.Equal(notification.Type, fcmNotification.APNS.Payload.Aps.Category)
	r.Equal("default", fcmNotification.APNS.Payload.Aps.Sound)
	r.True(fcmNotification.APNS.Payload.Aps.MutableContent)
	r.Equal(notification.ThreadID, fcmNotification.APNS.Payload.Aps.ThreadID)
	r.Equal(map[string]string{
		"title":               notification.Title,
		"subtitle":            notification.SubTitle,
		"body":                notification.Body,
		"url":                 notification.URL,
		"type":                notification.Type,
		"avatar_url":          notification.AvatarURL,
		"author_profile_name": notification.AuthorProfileName,
		"author_username":     notification.AuthorUsername,
		"thread_id":           notification.ThreadID,
		"thread_type":         notification.ThreadType,
		"username":            notification.Username,
		"subject_id":          notification.SubjectID,
	}, fcmNotification.Android.Data)
	r.ElementsMatch(fcmNotification.Tokens, []string{"device-token-1", "device-token-2"})
}

func TestZeroTTL(t *testing.T) {
	r := require.New(t)
	notification := Notification{}
	deviceTokens := devicetokens.Tokens{{DeviceToken: "token"}}
	fcmNotification := CreateMulticastMessage(notification, deviceTokens, true)

	r.Equal(time.Duration(0), *fcmNotification.Android.TTL)
	r.Equal(map[string]string{"TTL": "0"}, fcmNotification.Webpush.Headers)
}
