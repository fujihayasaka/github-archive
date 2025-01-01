package views

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/github-telemetry-go/log"

	"github.com/github/notifyd/internal/email/testhelper"
)

func Test_RenderHTML(t *testing.T) {
	ctx := context.Background()

	cases := []struct {
		name    string
		layout  string
		fixture string
		view    *HTMLEmailView
	}{
		{
			name:    "Base layout with all attributes",
			layout:  "base",
			fixture: "email_html_view_base",
			view: &HTMLEmailView{
				Subject:        "Some Test subject",
				Body:           "<b>Test HTML body</b>",
				URL:            "https://github.com/github/github/issue/1",
				UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/ABCX",
				CanReply:       true,
				Reason:         "you commented on a thread",
			},
		},
		{
			name:    "Base layout with some attributes",
			layout:  "base",
			fixture: "email_html_view_base_without_all_attributes",
			view: &HTMLEmailView{
				Subject:        "Some Test subject",
				Body:           "<b>Test HTML body</b>",
				URL:            "https://github.com/github/github/issue/1",
				UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/ABCX",
				CanReply:       false,
				Reason:         "",
			},
		},
		{
			name:    "Base layout without unsubscribe url",
			layout:  "base",
			fixture: "email_html_view_base_without_unsubscribe_url",
			view: &HTMLEmailView{
				Subject:  "Some Test subject",
				Body:     "<b>Test HTML body</b>",
				URL:      "https://github.com/github/github/issue/1",
				CanReply: false,
				Reason:   "",
			},
		},
		{
			name:    "Primer layout",
			layout:  "primer",
			fixture: "email_html_view_primer",
			view: &HTMLEmailView{
				Subject:        "Some Test subject",
				Body:           "<b>Test HTML body</b>",
				URL:            "https://github.com/github/github/issue/1",
				UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/ABCX",
				CanReply:       true,
				Reason:         "you commented on a thread",
			},
		},
		{
			layout:  "Simple layout",
			fixture: "email_html_view_simple",
			view: &HTMLEmailView{
				Subject:        "Some Test subject",
				Body:           "<b>Test HTML body</b>",
				URL:            "https://github.com/github/github/issue/1",
				UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/ABCX",
				CanReply:       true,
				Reason:         "you commented on a thread",
			},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(ti *testing.T) {
			actual, err := test.view.Render(ctx, log.NewNullLogger(), "base")
			require.NoError(t, err)

			testhelper.IsEqualToFixture(ti, &testhelper.Fixture{Name: test.fixture}, []byte(actual))
		})
	}
}

func Test_RenderHTMLUnknownLayout(t *testing.T) {
	ctx := context.Background()

	view := &HTMLEmailView{
		Subject:        "Some Test subject",
		Body:           "<b>Test HTML body</b>",
		URL:            "https://github.com/github/github/issue/1",
		UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/ABCX",
		CanReply:       true,
		Reason:         "you commented on a thread",
	}

	actual, err := view.Render(ctx, log.NewNullLogger(), "unknown")
	require.NoError(t, err)

	// Reuse base fixture
	testhelper.IsEqualToFixture(t, &testhelper.Fixture{Name: "email_html_view_base"}, []byte(actual))
}

func Test_RenderText(t *testing.T) {
	ctx := context.Background()

	cases := []struct {
		name    string
		layout  string
		fixture string
		view    *TextEmailView
	}{
		{
			name:    "Base layout",
			layout:  "base",
			fixture: "email_text_view_base",
			view: &TextEmailView{
				Subject:        "Some Test subject",
				Body:           "Test TEXT body\nWith more lines",
				URL:            "https://github.com/github/github/issue/1",
				UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/ABCX",
				Reason:         "you commented on a thread",
				CanReply:       true,
				MessageID:      "<message-id>",
			},
		},
		{
			name:    "Base layout without all attributes",
			layout:  "base",
			fixture: "email_text_view_base_without_all_attributes",
			view: &TextEmailView{
				Subject:        "Some Test subject",
				Body:           "Test TEXT body\nWith more lines",
				URL:            "https://github.com/github/github/issue/1",
				UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/ABCX",
				Reason:         "you commented on a thread",
				CanReply:       false,
				MessageID:      "",
			},
		},
		{
			name:    "Base layout without unsubscribe url",
			layout:  "base",
			fixture: "email_text_view_base_without_unsubscribe_url",
			view: &TextEmailView{
				Subject:   "Some Test subject",
				Body:      "Test TEXT body\nWith more lines",
				URL:       "https://github.com/github/github/issue/1",
				Reason:    "you commented on a thread",
				CanReply:  false,
				MessageID: "",
			},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(ti *testing.T) {
			actual, err := test.view.Render(ctx, log.NewNullLogger(), "base")
			require.NoError(t, err)

			testhelper.IsEqualToFixture(ti, &testhelper.Fixture{Name: test.fixture}, []byte(actual))
		})
	}
}

func Test_RenderTextUnknownLayout(t *testing.T) {
	ctx := context.Background()

	view := &TextEmailView{
		Subject:        "Some Test subject",
		Body:           "Test TEXT body\nWith more lines",
		URL:            "https://github.com/github/github/issue/1",
		UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/ABCX",
		Reason:         "you commented on a thread",
		CanReply:       true,
		MessageID:      "<message-id>",
	}

	actual, err := view.Render(ctx, log.NewNullLogger(), "unknown")
	require.NoError(t, err)

	// Reuse base fixture
	testhelper.IsEqualToFixture(t, &testhelper.Fixture{Name: "email_text_view_base"}, []byte(actual))
}
