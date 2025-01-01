package header

import (
	"context"
	"net/mail"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/github-telemetry-go/log"

	emailbody "github.com/github/notifyd/internal/email/body"
)

type frm struct {
	name  string
	email string
}

func (f *frm) GetName() string {
	return f.name
}

func (f *frm) GetEmail() string {
	return f.email
}

func Test_EmptyField(t *testing.T) {
	body := emailbody.NewBodyMock(t)
	field := NewEmptyField()
	field.AddTo(body)
}

func Test_RawField(t *testing.T) {
	body := emailbody.NewBodyMock(t)
	body.On("AddRawField", "Subject", "Raw")
	field := NewRawField("Subject", "Raw")
	field.AddTo(body)
}

func Test_TextField(t *testing.T) {
	body := emailbody.NewBodyMock(t)
	body.On("AddField", "Subject", "Text")
	field := NewTextField("Subject", "Text")
	field.AddTo(body)
}

func Test_AddressField(t *testing.T) {
	address := &mail.Address{Address: "jane@doe.io"}
	body := emailbody.NewBodyMock(t)
	body.On("AddAddress", "From", address)
	field := NewAddressField("From", address)
	field.AddTo(body)
}

func Test_AddressListField(t *testing.T) {
	list := []*mail.Address{{Address: "jane@doe.io"}}
	body := emailbody.NewBodyMock(t)
	body.On("AddAddressList", "From", list)
	field := NewAddressListField("From", list)
	field.AddTo(body)
}

func Test_BuildCC(t *testing.T) {
	reasons := []string{"subscribed", "mention"}
	domain := "test.com"

	body := emailbody.NewBodyMock(t)
	body.On("AddAddressList", "Cc", []*mail.Address{
		{Name: "Subscribed", Address: "subscribed@noreply.test.com"},
		{Name: "Mention", Address: "mention@noreply.test.com"},
	})
	field := BuildCC(reasons, domain)
	field.AddTo(body)
}

func Test_BuildCCWithRewrite(t *testing.T) {
	reasons := []string{"list_subscription", "thread_type_subscription"}
	domain := "test.com"

	body := emailbody.NewBodyMock(t)
	body.On("AddAddressList", "Cc", []*mail.Address{
		{Name: "Subscribed", Address: "subscribed@noreply.test.com"},
		{Name: "Subscribed", Address: "subscribed@noreply.test.com"},
	})
	field := BuildCC(reasons, domain)
	field.AddTo(body)
}

func Test_BuildToWithValidAddress(t *testing.T) {
	ctx := context.Background()
	to := `"owner/repo" <repo@noreply.github.com>`

	body := emailbody.NewBodyMock(t)
	body.On("AddAddress", "To", &mail.Address{Name: "owner/repo", Address: "repo@noreply.github.com"})
	field := BuildTo(ctx, log.NewNullLogger(), to)
	field.AddTo(body)
}

func Test_BuildToWithInvalidAddress(t *testing.T) {
	ctx := context.Background()
	to := `"owner/.repo" <.repo@noreply.github.com>`

	body := emailbody.NewBodyMock(t)
	body.On("AddRawField", "To", to)
	field := BuildTo(ctx, log.NewNullLogger(), to)
	field.AddTo(body)
}

func Test_BuildFrom(t *testing.T) {
	ctx := context.Background()
	defaultAddress := "notifications@noreply.github.com"
	cases := []struct {
		name     string
		from     *frm
		expected *mail.Address
	}{
		{
			name: "with all data",
			from: &frm{
				name:  "Jane Doe",
				email: "jane@doe.io",
			},
			expected: &mail.Address{Name: "Jane Doe", Address: "jane@doe.io"},
		},
		{
			name: "without name",
			from: &frm{
				email: "jane@doe.io",
			},
			expected: &mail.Address{Name: "GitHub", Address: "jane@doe.io"},
		},
		{
			name: "without email",
			from: &frm{
				name: "Jane Doe",
			},
			expected: &mail.Address{Name: "Jane Doe", Address: defaultAddress},
		},
		{
			name:     "without data",
			from:     &frm{},
			expected: &mail.Address{Name: "GitHub", Address: defaultAddress},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(ti *testing.T) {
			body := emailbody.NewBodyMock(t)
			body.On("AddAddress", "From", test.expected)
			field := BuildFrom(ctx, test.from, defaultAddress)
			field.AddTo(body)
		})
	}
}

func Test_BuildHeader(t *testing.T) {
	headers := map[string]string{
		"Content-Type": "text/plain",
	}
	reason := "mention"
	login := "janedoe"
	unsubscribe := ListUnsubscribe{
		URL:     "https://github.com/notifications/unsubscribe/ABC",
		Address: "unsub+ABC@reply.github.com",
	}
	replyTo := "reply+ABC@reply.github.com"

	expected := &Header{
		Fields: []Field{
			NewRawField("Content-Type", "text/plain"),
			NewTextField("X-GitHub-Reason", reason),
			NewTextField("X-GitHub-Recipient", login),
			unsubscribe,
			NewAddressField("Reply-To", &mail.Address{Address: replyTo}),
		},
	}

	actual := BuildHeader(headers, reason, login, unsubscribe, replyTo)

	require.Equal(t, expected, actual)
}

func Test_HeaderHasField(t *testing.T) {
	header := &Header{
		Fields: []Field{
			NewRawField("Message-ID", "<id>"),
		},
	}

	require.True(t, header.Has("Message-Id"))
	require.False(t, header.Has("Reply-To"))
}

func Test_HeaderGetField(t *testing.T) {
	header := &Header{
		Fields: []Field{
			NewRawField("Message-ID", "<id>"),
		},
	}

	require.Equal(t, "<id>", header.Get("Message-Id"))
	require.Equal(t, "", header.Get("Reply-To"))
}
