package datastructures

import (
	"fmt"
	gomail "net/mail"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/email/header"
	"github.com/github/notifyd/internal/email/testhelper"
)

func Test_composeHeader(t *testing.T) {
	from := header.NewAddressField("From", &gomail.Address{Name: "GitHub", Address: "notifications@github.com"})
	to := header.NewAddressField("To", &gomail.Address{Name: "owner/repo", Address: "repo@noreply.github.com"})

	html := `<p>This is the <b style="color: red">HTML</b> part</p>`
	text := "This is the TEXT part.\nWith some more content"

	tests := map[string]struct {
		notification Notification
		fixture      string
	}{
		"with a simple notification": {
			notification: Notification{
				NotificationID: "1",
				UserID:         1,
				Subject:        "Notification subject",
				Body:           html,
				From:           from,
				To:             to,
			},
			fixture: "email_with_simple_notification",
		},
		"with extra headers": {
			notification: Notification{
				NotificationID: "1",
				UserID:         1,
				Subject:        "Notification subject",
				Body:           html,
				From:           from,
				To:             to,
				Header: &header.Header{
					Fields: []header.Field{
						header.NewRawField("X-Extra-Header", "value"),
					},
				},
			},
			fixture: "email_with_extra_headers",
		},
		"with extra unallowed headers": {
			notification: Notification{
				NotificationID: "1",
				UserID:         1,
				Subject:        "Notification subject",
				Body:           html,
				From:           from,
				To:             to,
				Header: &header.Header{
					Fields: []header.Field{
						header.NewRawField("From", "forbidden"),
					},
				},
			},
			fixture: "email_with_extra_unallowed_headers",
		},
		"with a notification with a text body": {
			notification: Notification{
				NotificationID: "1",
				UserID:         1,
				Subject:        "Notification subject",
				Body:           html,
				TextBody:       text,
				From:           from,
				To:             to,
			},
			fixture: "email_with_text_part",
		},
	}

	for name, test := range tests {
		t.Run(name, func(ti *testing.T) {
			label := fmt.Sprintf("test name: %s", name)
			actual, err := test.notification.GetBody()
			require.NoError(ti, err, label)

			testhelper.IsEqualToFixture(ti, &testhelper.Fixture{Name: test.fixture}, actual)
		})
	}
}
