package datastructures

import (
	"net/textproto"

	"github.com/github/notifyd/internal/email/body"
	"github.com/github/notifyd/internal/email/header"
)

// Notification represents an email notification.
type Notification struct {
	NotificationID string
	UserID         int32
	Subject        string
	Body           string
	TextBody       string
	URL            string
	UnsubscribeURL string
	Reasons        []string
	From           header.Field
	CC             header.Field
	To             header.Field
	Recipient      string
	Header         *header.Header
}

// GetBody returns the email body.
func (n *Notification) GetBody() ([]byte, error) {
	b := body.New()
	if n.From != nil {
		n.From.AddTo(b)
	}
	if n.To != nil {
		n.To.AddTo(b)
	}
	if n.CC != nil {
		n.CC.AddTo(b)
	}

	b.AddField("Subject", n.Subject)

	if n.Header != nil {
		for _, field := range n.Header.Fields {
			if header.IsIgnoredField(field.Key()) {
				continue
			}

			field.AddTo(b)
		}
	}

	if n.TextBody != "" {
		b.AddPart(n.TextBody, textproto.MIMEHeader{
			"Content-Type": {"text/plain; charset=utf-8"},
		})
	}

	b.AddPart(n.Body, textproto.MIMEHeader{
		"Content-Type": {"text/html; charset=utf-8"},
	})

	data, err := b.Compose()
	if err != nil {
		return []byte{}, err
	}

	return data, nil
}

// GetMail returns the from header.
func (n *Notification) GetMail() string {
	return n.From.Value()
}

// GetRcpt returns the recipient.
func (n *Notification) GetRcpt() string {
	return n.Recipient
}

// GetTo returns the to header.
func (n *Notification) GetTo() string {
	return n.To.Value()
}
