package email

import (
	"bufio"
	"context"
	"crypto/tls"
	"net"
	gomail "net/mail"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	"github.com/emersion/go-smtp"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/header"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func TestLogSend(t *testing.T) {
	r := require.New(t)
	notification := datastructures.Notification{
		NotificationID: "12345",
		UserID:         678,
		Subject:        "this is a notification",
		Body:           "<body><h1> hello </h1></body>",
		From:           header.NewAddressField("From", &gomail.Address{Name: "GitHub", Address: "notifications@github.com"}),
		To:             header.NewAddressField("To", &gomail.Address{Address: "rcpt@foo.bla"}),
	}

	sender := logSender{
		telem: logs.NullTelem,
	}

	err := sender.Send(context.Background(), &notification)
	r.NoError(err)
}

func TestSMTPSend(t *testing.T) {
	r := require.New(t)
	tests := []struct {
		name                 string
		backend              *Backend
		sender               Sender
		notification         datastructures.Notification
		expectedErrorMessage string
		errorIsRetriable     bool
		expectedDataReceived []string
	}{
		{
			name: "Dial error returns a retriable error",
			backend: &Backend{
				Username: "user",
				Password: "password",
				// this channel is capacity 1 so it has a buffer and doesn't force the
				// mail server to wait for the client when sending data. Otherwise the
				// test deadlocks
				ReceivedDataChannel: make(chan string, 1),
			},
			sender: NewSMTP(
				Config{
					Host:     "",
					Port:     "",
					Username: "user",
					Password: "password",
					UseAuth:  true,
					UseTLS:   false,
				},
				clock.NewMock(),
				logs.NullTelem,
				stats.NullStatter,
			),
			expectedErrorMessage: "dialing connection",
			errorIsRetriable:     true,
		},
		{
			name: "Sending email with wrong user or password fails",
			backend: &Backend{
				Username: "user",
				Password: "password",
				// this channel is capacity 1 so it has a buffer and doesn't force the
				// mail server to wait for the client when sending data. Otherwise the
				// test deadlocks
				ReceivedDataChannel: make(chan string, 1),
			},
			sender: NewSMTP(
				Config{
					Host:     "localhost",
					Port:     "2525",
					Username: "user",
					UseAuth:  true,
					UseTLS:   false,
				},
				clock.NewMock(),
				logs.NullTelem,
				stats.NullStatter,
			),
			expectedErrorMessage: "authenticating SMTP client",
			errorIsRetriable:     true,
		},
		{
			name: "Sending email with user and password works",
			backend: &Backend{
				Username: "user",
				Password: "password",
				// this channel is capacity 1 so it has a buffer and doesn't force the
				// mail server to wait for the client when sending data. Otherwise the
				// test deadlocks
				ReceivedDataChannel: make(chan string, 1),
			},
			sender: NewSMTP(
				Config{
					Host:     "localhost",
					Port:     "2525",
					Username: "user",
					Password: "password",
					UseAuth:  true,
					UseTLS:   false,
				},
				clock.NewMock(),
				logs.NullTelem,
				stats.NullStatter,
			),
			notification: datastructures.Notification{
				NotificationID: "12345",
				UserID:         678,
				Subject:        "this is a notification",
				Body:           `<body><h1> hello </h1><p> email test </p><span style="display: none">mark</span></body>`,
				CC:             header.NewAddressListField("Cc", []*gomail.Address{{Address: "rcpt@foo.bla"}}),
				From:           header.NewAddressField("From", &gomail.Address{Name: "GitHub", Address: "notifications@github.com"}),
				To:             header.NewRawField("To", `"owner/.repo" <.repo@noreply.github.com>`),
				Recipient:      "rcpt@foo.bla",
			},
			expectedDataReceived: []string{
				"Subject: this is a notification\r\n",
				"From: \"GitHub\" <notifications@github.com>\r\n",
				"To: \"owner/.repo\" <.repo@noreply.github.com>\r\n",
				"Cc: <rcpt@foo.bla>\r\n",
				"<body><h1> hello </h1><p> email test </p><span style=3D\"display: none\">mark=\r\n</span></body>",
			},
		},
		{
			name: "Sending email without user and password works if configured",
			backend: &Backend{
				AllowAnonymousLogin: true,
				// this channel is capacity 1 so it has a buffer and doesn't force the
				// mail server to wait for the client when sending data. Otherwise the
				// test deadlocks
				ReceivedDataChannel: make(chan string, 1),
			},
			sender: NewSMTP(
				Config{
					Host:    "localhost",
					Port:    "2525",
					UseAuth: false,
					UseTLS:  false,
				},
				clock.NewMock(),
				logs.NullTelem,
				stats.NullStatter,
			),
			notification: datastructures.Notification{
				NotificationID: "12345",
				UserID:         678,
				Subject:        "this is a notification",
				Body:           `<body><h1> hello </h1><p> email test </p><span style="display: none">mark</span></body>`,
				CC:             header.NewAddressListField("Cc", []*gomail.Address{{Address: "rcpt@foo.bla"}}),
				From:           header.NewAddressField("From", &gomail.Address{Name: "GitHub", Address: "notifications@github.com"}),
				To:             header.NewRawField("To", `"owner/.repo" <.repo@noreply.github.com>`),
				Recipient:      "rcpt@foo.bla",
			},
			expectedDataReceived: []string{
				"Subject: this is a notification\r\n",
				"From: \"GitHub\" <notifications@github.com>\r\n",
				"To: \"owner/.repo\" <.repo@noreply.github.com>\r\n",
				"Cc: <rcpt@foo.bla>\r\n",
				"<body><h1> hello </h1><p> email test </p><span style=3D\"display: none\">mark=\r\n</span></body>",
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cl, addr := runServer(t, test.backend)
			defer func() { _ = cl() }()
			waitForServer(t, addr)

			notification := test.notification
			err := test.sender.Send(context.Background(), &notification)

			if test.expectedErrorMessage != "" {
				r.Contains(err.Error(), test.expectedErrorMessage)
				r.Equal(test.errorIsRetriable, errors.IsRetriable(err))
				return
			}

			r.NoError(err)
			// we only expect to receive data on the channel if the send worked
			data := <-test.backend.ReceivedDataChannel
			for _, expected := range test.expectedDataReceived {
				r.Contains(data, expected)
			}
		})
	}
}

func waitForServer(t *testing.T, addr string) {
	t.Helper()

	maxWaitTimeMS := 1000
	waitTimeMS := 50
	for {
		if maxWaitTimeMS <= 0 {
			t.Fatal("Test SMTP server didn't start in time")
		}
		// check that the socket is open
		c, err := net.Dial("tcp", addr)
		if err != nil {
			maxWaitTimeMS -= waitTimeMS
			time.Sleep(time.Duration(waitTimeMS) * time.Millisecond)
			continue
		}

		// make sure the mail server responds properly
		scanner := bufio.NewScanner(c)
		scanner.Scan()
		if scanner.Text() != "220 localhost ESMTP Service Ready" {
			t.Fatal("Invalid greeting:", scanner.Text())
		}

		break
	}
}

func runServer(t *testing.T, backend *Backend) (func() error, string) {
	t.Helper()

	s := smtp.NewServer(backend)
	s.Addr = ":2525"
	s.Domain = "localhost"
	s.AllowInsecureAuth = true

	cer, err := tls.LoadX509KeyPair("testdata/localhost.crt", "testdata/localhost.key")
	require.NoError(t, err)
	s.TLSConfig = &tls.Config{Certificates: []tls.Certificate{cer}, MinVersion: tls.VersionTLS12}

	go func() {
		if err := s.ListenAndServe(); err != nil {
			assert.NoError(t, err)
		}
	}()

	return s.Close, s.Addr
}
