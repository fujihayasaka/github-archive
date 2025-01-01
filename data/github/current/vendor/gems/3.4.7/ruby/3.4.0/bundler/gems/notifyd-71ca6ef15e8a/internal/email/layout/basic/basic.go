// Package basic implements the basic email layout processor.
package basic

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/proto"

	emaildatastructures "github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/header"
	"github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/layout/email"
	"github.com/github/notifyd/internal/email/layout/views"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/pkg/layouts"
	"github.com/github/notifyd/internal/pkg/tenancy"
	pb_email "github.com/github/notifyd/proto/layouts/email"
)

const (
	emailLayout = "base"
	// TypeURL is the type url for the basic layout.
	TypeURL = "type.googleapis.com/notifyd.layouts.email.Basic"
	// the subdomain to use for reply emails (comment, unsubscribe, etc). This
	// will get prepended to senderDomain
	replySubdomain = "reply"
)

// Processor represents a basic email layout processor.
type Processor struct {
	telem           *telemetry.Provider
	statter         stats.Client
	postprocessor   pipeline.PostProcessor
	senderDomain    string
	fromAddressName string
}

// NewProcessor creates a new basic email layout processor.
func NewProcessor(cfg config.Config, telem *telemetry.Provider, statter stats.Client, postprocessor pipeline.PostProcessor) Processor {
	return Processor{
		telem:           telem,
		statter:         statter,
		postprocessor:   postprocessor,
		senderDomain:    cfg.SenderDomain,
		fromAddressName: cfg.FromAddressName,
	}
}

// Process performs the layout processing of an email.
func (p Processor) Process(ctx context.Context, tenant tenancy.Tenant, deliverEmailData emaildatastructures.DeliverEmailData, msg *emaildatastructures.Email) (email.Email, error) {
	logger := p.telem.Logger.WithContext(ctx)

	if typeURL := msg.LayoutData.GetTypeUrl(); typeURL != TypeURL {
		return nil, layouts.NewTypeError(typeURL)
	}

	var emailData pb_email.Basic
	if err := proto.Unmarshal(msg.LayoutData.GetValue(), &emailData); err != nil {
		return nil, layouts.NewUnmarshallingError(err, TypeURL)
	}

	footerURL, headerURL := makeUnsubscribeLinks(emailData.GetUnsubscribeUrlTemplates(), deliverEmailData.AuthTokens)
	emailToken := deliverEmailData.ReplyToToken()
	replyTo := p.generateReplyToEmail(tenant, emailToken)

	// NOTE: For the moment we are generating the unsub email address with the replyTo token
	//  This is the same Newsies does, and it's what is expected in the EmailUnsubscribeJob in Dotcom
	//  However, we don't generate the email token for all mails, on for those that can be replied
	//  This means we are not adding this mail address all the time.
	//  Ideally we should add this mail address with the same token as the headerUrl, but our tokens
	//  are too big.
	list := header.ListUnsubscribe{
		URL:     headerURL,
		Address: p.generateUnsubscribeEmail(tenant, emailToken),
	}

	notification := &emaildatastructures.Notification{
		Subject:        emailData.GetSubject(),
		Body:           emailData.GetBody(),
		TextBody:       emailData.GetTextBody(),
		URL:            emailData.GetUrl(),
		UnsubscribeURL: footerURL,
		From:           header.BuildFrom(ctx, emailData.GetFrom(), p.generateFromEmail(tenant)),
		CC:             header.BuildCC(msg.Reasons, tenant.BuildDomain(p.senderDomain)),
		To:             header.BuildTo(ctx, logger, emailData.GetTo()),
		Header: header.BuildHeader(
			emailData.GetHeaders(),
			header.BuildReason(msg.Reasons),
			deliverEmailData.Login,
			list,
			replyTo,
		),
		Recipient: deliverEmailData.Email,
		Reasons:   reasonSentence(msg.Reasons, emailData.GetReasonsToWords()),
	}

	logger.Info("building template")
	builder := views.NewTemplate(p.telem, p.statter, emailLayout, p.postprocessor)

	notification, err := builder.CreateTemplate(ctx, tenant, notification)
	if err != nil {
		logger.WithError(err).Info("sending plain text email due to error")
	}

	return notification, nil
}

func makeUnsubscribeLinks(unsubscribeURLTemplates *pb_email.UnsubscribeUrlTemplates, authTokens []emaildatastructures.AuthToken) (footerURL, headerURL string) {
	if unsubscribeURLTemplates == nil {
		return footerURL, headerURL
	}

	for _, authToken := range authTokens {
		switch authToken.Scope {
		case emaildatastructures.MuteAuthScope:
			footerURL = strings.ReplaceAll(unsubscribeURLTemplates.Footer, "{token}", authToken.Token)
		case emaildatastructures.MuteListScope:
			headerURL = strings.ReplaceAll(unsubscribeURLTemplates.Header, "{token}", authToken.Token)
		}
	}

	return footerURL, headerURL
}

// generateReplyToEmail turns a token into an email
// TODO: Return "net/mail".Address to build something like: "github/notifyd" <reply+{token}@reply.github.com>
func (p Processor) generateReplyToEmail(tenant tenancy.Tenant, token string) string {
	if token == "" {
		return ""
	}

	return fmt.Sprintf("reply+%s@%s.%s", token, replySubdomain, tenant.BuildDomain(p.senderDomain))
}

func (p Processor) generateUnsubscribeEmail(tenant tenancy.Tenant, token string) string {
	if token == "" {
		return ""
	}

	return fmt.Sprintf("unsub+%s@%s.%s", token, replySubdomain, tenant.BuildDomain(p.senderDomain))
}

func (p Processor) generateFromEmail(tenant tenancy.Tenant) string {
	return fmt.Sprintf("%s@%s", p.fromAddressName, tenant.BuildDomain(p.senderDomain))
}

// reasonSentence maps reasons to reason sentences, in order to use in templates
func reasonSentence(reasons []string, reasonMapping map[string]string) (r []string) {
	for _, reason := range reasons {
		reasonWords, ok := reasonMapping[reason]
		if ok {
			r = append(r, reasonWords)
		}
	}
	return r
}
