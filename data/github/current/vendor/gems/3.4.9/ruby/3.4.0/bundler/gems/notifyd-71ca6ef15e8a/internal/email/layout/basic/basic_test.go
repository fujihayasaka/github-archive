package basic

import (
	"context"
	"fmt"
	"reflect"
	"testing"

	"github.com/github/go-stats"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	emaildatastructures "github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/email/testhelper"
	"github.com/github/notifyd/internal/pkg/layouts"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
	pb_email "github.com/github/notifyd/proto/layouts/email"
)

// This is a bit of a meta test to make sure we don't forget to add new
// notification fields to the layout render method. Because we then end up
// with those fields being zero value and not properly handed through from the
// hydro message to the email sender.
func TestLayoutSetEveryNotificationField(t *testing.T) {
	r := require.New(t)
	layoutData := pb_email.Basic{
		Subject:  "mikrobi wants your attention",
		Body:     "Open this notification to read more about mikrobis issues",
		TextBody: "Text part of the notification",
		From:     &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
		Url:      "https://github.com",
		To:       "org/repo <repo@noreply.github.com>",
		UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
			Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
			Header: "https://github.com/notifications/unsubscribe/{token}",
		},
		ReasonsToWords: map[string]string{
			"mention": "you were mentioned",
			"comment": "you commented on a thread",
			"manual":  "you subscribed to a thread",
			"author":  "you authored a thread",
		},
		Headers: make(map[string]string),
	}

	layoutBytes, err := proto.Marshal(&layoutData)
	r.NoError(err)

	layout := anypb.Any{
		TypeUrl: TypeURL,
		Value:   layoutBytes,
	}
	msg := &emaildatastructures.Email{
		LayoutData: &layout,
		Reasons:    []string{"mention"},
	}

	postprocessor := pipeline.NewMinifier()

	p := NewProcessor(config.Config{}, logs.NullTelem, stats.NullStatter, postprocessor)
	notification, err := p.Process(context.Background(), tenancy.NewSingleTenant(), emaildatastructures.DeliverEmailData{
		Login: "",
		Email: "",
		AuthTokens: []emaildatastructures.AuthToken{
			{Scope: emaildatastructures.MuteAuthScope, Token: "token_value1"},
			{Scope: emaildatastructures.MuteListScope, Token: "token_value2"},
		},
	}, msg)
	r.NoError(err)

	s := reflect.ValueOf(notification).Elem()
	typeOfT := s.Type()
	for i := range s.NumField() {
		fieldName := typeOfT.Field(i).Name
		switch fieldName {
		// skip for things that aren't set through the layout
		case "NotificationID", "UserID", "CC", "Recipient", "Headers", "ReplyTo":
			continue
		default:
			f := s.Field(i)
			isZeroValue := reflect.DeepEqual(f.Interface(), reflect.Zero(f.Type()).Interface())
			r.False(isZeroValue, "'%s' should not be zero value", fieldName)
		}
	}
}

func TestRender(t *testing.T) {
	tests := []*struct {
		name         string
		description  string
		reasons      []string
		recipient    string
		layoutData   pb_email.Basic
		replyToToken string
		fixture      string
	}{
		{
			name:        "All attributes provided",
			description: "It should return Notification struct with all the expected fields",
			reasons:     []string{"mentioned_directly-again", "subscribed"},
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
				To:      "list_email@test.com",
				UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
					Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
					Header: "https://github.com/notifications/unsubscribe/{token}",
				},
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
				ReasonsToWords: map[string]string{
					"subscribed": "you subscribed to a thread",
				},
			},
			fixture: "email_with_all_attributes",
		},
		{
			name:        "Missing Sender",
			description: "It should return Notification struct with all the expected fields",
			reasons:     []string{"mentioned_directly-again", "subscribed"},
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				To:      "list_email@test.com",
				UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
					Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
					Header: "https://github.com/notifications/unsubscribe/{token}",
				},
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
			},
			fixture: "email_without_sender",
		},
		{
			name:        "Missing Reasons",
			description: "It should return Notification struct with all the expected fields",
			reasons:     nil,
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
				UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
					Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
					Header: "https://github.com/notifications/unsubscribe/{token}",
				},
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
			},
			fixture: "email_without_reasons",
		},
		{
			name:        "Missing Headers",
			description: "It should return Notification struct with all the expected fields",
			reasons:     nil,
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
				UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
					Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
					Header: "https://github.com/notifications/unsubscribe/{token}",
				},
			},
			fixture: "email_without_extra_headers",
		},
		{
			name:        "Missing UnsubscribeUrlTemplates",
			description: "It should return Notification struct with all the expected fields",
			reasons:     nil,
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
			},
			fixture: "email_without_unsubscribe_url",
		},
		{
			name:         "Checks reply-to attribute",
			description:  "The header/body should contain the right values for Reply-To fields",
			reasons:      []string{"subscribed"},
			replyToToken: "reply-to-token-123",
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
				To:      "list_email@test.com",
				UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
					Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
					Header: "https://github.com/notifications/unsubscribe/{token}",
				},
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
			},
			fixture: "email_with_reply_to",
		},
		{
			name:         "Checks reply-to attribute and no unsubscribe",
			description:  "The header/body should contain the right values for Reply-To fields and no unsubscribe link",
			reasons:      []string{"subscribed"},
			replyToToken: "reply-to-token-123",
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
				To:      "list_email@test.com",
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
			},
			fixture: "email_with_reply_to_no_unsubscribe",
		},
		{
			name:        "Falls back to provided To field if it fails to parse the address",
			description: "The header should contain the original To field",
			reasons:     []string{"subscribed"},
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
				To:      `"user/.dotfiles" <.dotfiles@test.com>`,
				UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
					Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
					Header: "https://github.com/notifications/unsubscribe/{token}",
				},
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
			},
			fixture: "email_with_provided_to_field",
		},
		{
			name:        "With a text part",
			description: "It should return Notification struct with all the expected fields",
			reasons:     []string{"mentioned_directly-again", "subscribed"},
			layoutData: pb_email.Basic{
				Subject:  "mikrobi wants your attention",
				Body:     "<p>Open this notification to read more about mikrobis issues</p>",
				TextBody: "Open this notification to read more about mikrobis issues",
				From:     &pb_email.From{Email: "notifications@github.com", Name: "GitHub"},
				To:       "list_email@test.com",
				UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
					Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
					Header: "https://github.com/notifications/unsubscribe/{token}",
				},
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
				ReasonsToWords: map[string]string{
					"subscribed": "you subscribed to a thread",
				},
			},
			fixture: "email_with_text_part",
		},
	}

	cfg := config.Config{SenderDomain: "github.com", FromAddressName: "notifications"}
	for _, test := range tests {
		t.Run(test.name, func(ti *testing.T) {
			label := fmt.Sprintf("test name: %s", test.name)
			layoutBytes, err := proto.Marshal(&test.layoutData)
			require.NoError(ti, err, label)

			layout := anypb.Any{
				TypeUrl: TypeURL,
				Value:   layoutBytes,
			}
			msg := &emaildatastructures.Email{
				LayoutData: &layout,
				Reasons:    test.reasons,
			}

			postprocessor := pipeline.NewMinifier()

			p := NewProcessor(cfg, logs.NullTelem, stats.NullStatter, postprocessor)
			authTokens := []emaildatastructures.AuthToken{
				{Scope: emaildatastructures.MuteAuthScope, Token: "token_value1"},
				{Scope: emaildatastructures.MuteListScope, Token: "token_value2"},
			}
			if test.replyToToken != "" {
				authTokens = append(authTokens, emaildatastructures.AuthToken{Scope: emaildatastructures.EmailReplyScope, Token: test.replyToToken})
			}
			email, err := p.Process(context.Background(), tenancy.NewSingleTenant(), emaildatastructures.DeliverEmailData{
				Login:      "user-login",
				Email:      "user@test.com",
				AuthTokens: authTokens,
			}, msg)
			require.NoError(ti, err, label)

			actual, err := email.GetBody()
			require.NoError(ti, err, label)

			testhelper.IsEqualToFixture(ti, &testhelper.Fixture{Name: test.fixture}, actual)
		})
	}
}

func TestRender_MultiTenant(t *testing.T) {
	tests := []*struct {
		name         string
		description  string
		reasons      []string
		recipient    string
		layoutData   pb_email.Basic
		replyToToken string
		fixture      string
	}{
		{
			name:         "Checks reply-to attribute",
			description:  "The header/body should contain the right values for Reply-To fields",
			reasons:      []string{"subscribed"},
			replyToToken: "reply-to-token-123",
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@avocado.ghe.com", Name: "GitHub"},
				To:      "list_email@test.com",
				UnsubscribeUrlTemplates: &pb_email.UnsubscribeUrlTemplates{
					Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
					Header: "https://github.com/notifications/unsubscribe/{token}",
				},
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
			},
			fixture: "email_with_reply_to_multi_tenant",
		},
		{
			name:         "Checks reply-to attribute and no unsubscribe",
			description:  "The header/body should contain the right values for Reply-To fields and no unsubscribe link",
			reasons:      []string{"subscribed"},
			replyToToken: "reply-to-token-123",
			layoutData: pb_email.Basic{
				Subject: "mikrobi wants your attention",
				Body:    "Open this notification to read more about mikrobis issues",
				From:    &pb_email.From{Email: "notifications@avocado.ghe.com", Name: "GitHub"},
				To:      "list_email@test.com",
				Headers: map[string]string{
					"TestHeader": "test-value",
				},
			},
			fixture: "email_with_reply_to_no_unsubscribe_multi_tenant",
		},
	}

	tenant := tenancy.NewMultiTenant()
	tenant = tenant.WithSlug("avocado")
	tenant = tenant.WithID(123)

	cfg := config.Config{SenderDomain: "ghe.com", FromAddressName: "notifications"}
	for _, test := range tests {
		t.Run(test.name, func(ti *testing.T) {
			label := fmt.Sprintf("test name: %s", test.name)
			layoutBytes, err := proto.Marshal(&test.layoutData)
			require.NoError(ti, err, label)

			layout := anypb.Any{
				TypeUrl: TypeURL,
				Value:   layoutBytes,
			}
			msg := &emaildatastructures.Email{
				LayoutData: &layout,
				Reasons:    test.reasons,
			}

			postprocessor := pipeline.NewMinifier()

			p := NewProcessor(cfg, logs.NullTelem, stats.NullStatter, postprocessor)
			authTokens := []emaildatastructures.AuthToken{
				{Scope: emaildatastructures.MuteAuthScope, Token: "token_value1"},
				{Scope: emaildatastructures.MuteListScope, Token: "token_value2"},
			}
			authTokens = append(authTokens, emaildatastructures.AuthToken{Scope: emaildatastructures.EmailReplyScope, Token: test.replyToToken})
			email, err := p.Process(context.Background(), tenant, emaildatastructures.DeliverEmailData{
				Login:      "user-login",
				Email:      "user@test.com",
				AuthTokens: authTokens,
			}, msg)
			require.NoError(ti, err, label)

			actual, err := email.GetBody()
			require.NoError(ti, err, label)

			testhelper.IsEqualToFixture(ti, &testhelper.Fixture{Name: test.fixture}, actual)
		})
	}
}

func TestRenderProtoError(t *testing.T) {
	r := require.New(t)
	randomBytes := []byte{23, 67, 102, 56}
	layout := anypb.Any{
		TypeUrl: TypeURL,
		Value:   randomBytes,
	}
	msg := &emaildatastructures.Email{
		LayoutData: &layout,
	}

	postprocessor := pipeline.NewMinifier()

	p := NewProcessor(config.Config{}, logs.NullTelem, stats.NullStatter, postprocessor)
	notification, err := p.Process(context.Background(), tenancy.NewSingleTenant(), emaildatastructures.DeliverEmailData{Email: "user@test.com", Login: "login"}, msg)

	r.Nil(notification)
	var unmarshallingErr layouts.UnmarshallingError
	r.ErrorAs(err, &unmarshallingErr)
}

func TestRenderTypeUrlError(t *testing.T) {
	r := require.New(t)

	layout := anypb.Any{
		TypeUrl: "testing/not-a-layout",
	}
	msg := &emaildatastructures.Email{
		LayoutData: &layout,
	}

	postprocessor := pipeline.NewMinifier()

	p := NewProcessor(config.Config{}, logs.NullTelem, stats.NullStatter, postprocessor)
	notification, err := p.Process(context.Background(), tenancy.NewSingleTenant(), emaildatastructures.DeliverEmailData{Email: "user@test.com", Login: "login"}, msg)

	r.Nil(notification)
	var typeErr layouts.TypeError
	r.ErrorAs(err, &typeErr)
}
