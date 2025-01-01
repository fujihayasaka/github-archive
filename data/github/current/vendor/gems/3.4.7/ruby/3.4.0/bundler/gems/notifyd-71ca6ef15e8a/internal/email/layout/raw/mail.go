package raw

import (
	"net/textproto"

	"github.com/github/notifyd/internal/email/body"
	"github.com/github/notifyd/internal/email/header"
)

type part struct {
	headers textproto.MIMEHeader
	body    string
}

type mail struct {
	subject   string
	from      header.Field
	cc        header.Field
	to        header.Field
	recipient string
	header    *header.Header
	parts     []part
}

func (m mail) GetBody() ([]byte, error) {
	b := body.New()
	if m.from != nil {
		m.from.AddTo(b)
	}
	if m.to != nil {
		m.to.AddTo(b)
	}
	if m.cc != nil {
		m.cc.AddTo(b)
	}

	b.AddField("Subject", m.subject)

	if m.header != nil {
		for _, field := range m.header.Fields {
			if !header.IsIgnoredField(field.Key()) {
				field.AddTo(b)
			}
		}
	}

	for _, p := range m.parts {
		b.AddEncodedPart(p.body, p.headers)
	}

	data, err := b.Compose()
	if err != nil {
		return []byte{}, err
	}

	return data, nil
}

func (m mail) GetMail() string {
	return m.from.Value()
}

func (m mail) GetRcpt() string {
	return m.recipient
}

func (m mail) GetTo() string {
	return m.to.Value()
}
