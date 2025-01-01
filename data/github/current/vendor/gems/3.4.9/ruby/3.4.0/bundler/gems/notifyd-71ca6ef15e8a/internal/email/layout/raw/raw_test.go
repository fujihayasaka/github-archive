package raw

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/go-stats"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	emaildatastructures "github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/testhelper"
	"github.com/github/notifyd/internal/pkg/layouts"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
	emailpb "github.com/github/notifyd/proto/layouts/email"
)

func TestProcess(t *testing.T) {
	cfg := config.Config{SenderDomain: "github.com", FromAddressName: "notifications"}
	statter := stats.NullStatter

	// Simple Text part
	text := &emailpb.Part{
		Headers: map[string]string{
			"Content-Type":              "text/plain; charset=utf-8",
			"Content-Transfer-Encoding": "7bit",
		},
		Content: "This is the TEXT part",
	}

	// Encoded HTML part
	html := &emailpb.Part{
		Headers: map[string]string{
			"Content-Type":              "text/html; charset=utf-8",
			"Content-Transfer-Encoding": "quoted-printable",
		},
		Content: `<p>This is the <b style=3D"display: none">HTML</b> part</p>`,
	}

	cases := []*struct {
		name       string
		fixture    string
		reasons    []string
		layoutData emailpb.Raw
	}{
		{
			name:    "With all attributes",
			fixture: "email_with_all_attributes",
			reasons: []string{"mentioned_directly-again", "subscribed"},
			layoutData: emailpb.Raw{
				Subject: "mikrobi wants your attention",
				Body:    []*emailpb.Part{text, html},
				From:    &emailpb.From{Email: "notifications@github.com", Name: "GitHub"},
				To:      "list_email@test.com",
				Headers: map[string]string{
					"X-GitHub-Test": "test-value",
				},
			},
		},
		{
			name:    "Without sender",
			fixture: "email_without_sender",
			reasons: []string{"mentioned_directly-again", "subscribed"},
			layoutData: emailpb.Raw{
				Subject: "mikrobi wants your attention",
				Body:    []*emailpb.Part{text, html},
				To:      "list_email@test.com",
				Headers: map[string]string{
					"X-GitHub-Test": "test-value",
				},
			},
		},
		{
			name:    "Without reasons",
			fixture: "email_without_reasons",
			reasons: nil,
			layoutData: emailpb.Raw{
				Subject: "mikrobi wants your attention",
				Body:    []*emailpb.Part{text, html},
				From:    &emailpb.From{Email: "notifications@github.com", Name: "GitHub"},
				To:      "list_email@test.com",
				Headers: map[string]string{
					"X-GitHub-Test": "test-value",
				},
			},
		},
		{
			name:    "Without extra headers",
			fixture: "email_without_extra_headers",
			reasons: []string{"mentioned_directly-again", "subscribed"},
			layoutData: emailpb.Raw{
				Subject: "mikrobi wants your attention",
				Body:    []*emailpb.Part{text, html},
				From:    &emailpb.From{Email: "notifications@github.com", Name: "GitHub"},
				To:      "list_email@test.com",
			},
		},
		{
			name:    "With one part",
			fixture: "email_with_one_part",
			reasons: []string{"subscribed"},
			layoutData: emailpb.Raw{
				Subject: "mikrobi wants your attention",
				Body:    []*emailpb.Part{html},
				From:    &emailpb.From{Email: "notifications@github.com", Name: "GitHub"},
				To:      "list_email@test.com",
			},
		},
	}

	for _, test := range cases {
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

			p := NewProcessor(cfg, logs.NullTelem, statter)
			email, err := p.Process(context.Background(), tenancy.NewSingleTenant(), emaildatastructures.DeliverEmailData{Email: "user@test.com", Login: "user-login"}, msg)
			require.NoError(ti, err, label)

			actual, err := email.GetBody()
			require.NoError(ti, err, label)

			testhelper.IsEqualToFixture(ti, &testhelper.Fixture{Name: test.fixture}, actual)
		})
	}
}

func TestProcessProtoError(t *testing.T) {
	r := require.New(t)
	randomBytes := []byte{23, 67, 102, 56}
	layout := anypb.Any{
		TypeUrl: TypeURL,
		Value:   randomBytes,
	}
	msg := &emaildatastructures.Email{
		LayoutData: &layout,
	}

	p := NewProcessor(config.Config{}, logs.NullTelem, stats.NullStatter)
	email, err := p.Process(context.Background(), tenancy.NewSingleTenant(), emaildatastructures.DeliverEmailData{Email: "user@test.com", Login: "login"}, msg)

	r.Nil(email)
	var unmarshallingErr layouts.UnmarshallingError
	r.ErrorAs(err, &unmarshallingErr)
}

func TestProcessTypeURLError(t *testing.T) {
	r := require.New(t)
	layout := anypb.Any{
		TypeUrl: "testing/not-a-layout",
	}
	msg := &emaildatastructures.Email{
		LayoutData: &layout,
	}

	p := NewProcessor(config.Config{}, logs.NullTelem, stats.NullStatter)
	email, err := p.Process(context.Background(), tenancy.NewSingleTenant(), emaildatastructures.DeliverEmailData{Email: "user@test.com", Login: "login"}, msg)

	r.Nil(email)
	r.ErrorIs(err, layouts.NewTypeError("testing/not-a-layout"))
}

func TestProcessNoBodyError(t *testing.T) {
	r := require.New(t)

	layoutData := &emailpb.Raw{
		Subject: "mikrobi wants your attention",
		Body:    []*emailpb.Part{},
		From:    &emailpb.From{Email: "notifications@github.com", Name: "GitHub"},
		To:      "list_email@test.com",
		Headers: map[string]string{
			"TestHeader": "test-value",
		},
	}
	layoutBytes, err := proto.Marshal(layoutData)
	r.NoError(err)

	layout := anypb.Any{
		TypeUrl: TypeURL,
		Value:   layoutBytes,
	}
	msg := &emaildatastructures.Email{
		LayoutData: &layout,
		Reasons:    []string{"mentioned_directly-again", "subscribed"},
	}

	cfg := config.Config{SenderDomain: "github.com", FromAddressName: "notifications"}

	p := NewProcessor(cfg, logs.NullTelem, stats.NullStatter)
	_, err = p.Process(context.Background(), tenancy.NewSingleTenant(), emaildatastructures.DeliverEmailData{Email: "user@test.com", Login: "login"}, msg)

	r.ErrorContains(err, "empty body")
}
