// Package raw handles of the processing of the emails received with the Raw layout,
// which is used when the email body parts are already prerendered and require
// no further processing.
package raw

import (
	"context"
	"fmt"
	"net/textproto"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/proto"

	emaildatastructures "github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/header"
	"github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/layout/email"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/layouts"
	"github.com/github/notifyd/internal/pkg/tenancy"
	emailpb "github.com/github/notifyd/proto/layouts/email"
)

// TypeURL is the type url for the raw layout.
const TypeURL = "type.googleapis.com/notifyd.layouts.email.Raw"

// Processor represents a raw email layout processor.
type Processor struct {
	telem           *telemetry.Provider
	statter         stats.Client
	senderDomain    string
	fromAddressName string
}

// NewProcessor creates a new raw email layout processor.
func NewProcessor(cfg config.Config, telem *telemetry.Provider, statter stats.Client) Processor {
	return Processor{
		telem:           telem,
		statter:         statter,
		senderDomain:    cfg.SenderDomain,
		fromAddressName: cfg.FromAddressName,
	}
}

// Process performs the layout processing of an email.
func (p Processor) Process(ctx context.Context, tenant tenancy.Tenant, deliverEmailData emaildatastructures.DeliverEmailData, msg *emaildatastructures.Email) (email.Email, error) {
	var raw emailpb.Raw

	if typeURL := msg.LayoutData.GetTypeUrl(); typeURL != TypeURL {
		return nil, layouts.NewTypeError(typeURL)
	}

	if err := proto.Unmarshal(msg.LayoutData.GetValue(), &raw); err != nil {
		return nil, layouts.NewUnmarshallingError(err, TypeURL)
	}

	if len(raw.GetBody()) == 0 {
		return nil, errors.New("empty body")
	}

	parts := make([]part, len(raw.GetBody()))
	for i, p := range raw.GetBody() {
		headers := make(textproto.MIMEHeader)
		for key, value := range p.GetHeaders() {
			headers[key] = append(headers[key], value)
		}
		parts[i] = part{
			headers: headers,
			body:    p.GetContent(),
		}
	}

	return mail{
		subject:   raw.GetSubject(),
		from:      header.BuildFrom(ctx, raw.GetFrom(), p.generateFromEmail(tenant)),
		cc:        header.BuildCC(msg.Reasons, p.senderDomain),
		to:        header.BuildTo(ctx, p.telem.Logger, raw.GetTo()),
		recipient: deliverEmailData.Email,
		header: header.BuildHeader(
			raw.GetHeaders(),
			header.BuildReason(msg.Reasons),
			deliverEmailData.Login,
			header.ListUnsubscribe{},
			"",
		),
		parts: parts,
	}, nil
}

func (p Processor) generateFromEmail(tenant tenancy.Tenant) string {
	return fmt.Sprintf("%s@%s", p.fromAddressName, tenant.BuildDomain(p.senderDomain))
}
