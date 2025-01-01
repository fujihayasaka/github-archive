// Package main implements the entrypoint for the email-send tester.
package main

import (
	"context"
	"log"
	gomail "net/mail"
	"net/textproto"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/email"
	"github.com/github/notifyd/internal/email/body"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

type mail struct{}

func (m mail) GetBody() ([]byte, error) {
	b := body.New()
	b.AddAddressList("From", []*gomail.Address{{Name: "Test ケータイ", Address: "notifications@test.com"}})
	b.AddAddressList("Cc", []*gomail.Address{{Name: "Mention", Address: "mention@example.org"}, {Name: "Subscribed", Address: "subscribed@example.org"}})
	b.AddAddressList("To", []*gomail.Address{{Name: "owner/repo", Address: "repo@test.com"}})
	b.AddField("Subject", "This is a test ケータイ")
	b.AddPart("This is the TEXT part", textproto.MIMEHeader{
		"Content-Type": {"text/plain; charset=utf-8"},
	})
	b.AddPart(`This is <a href="https://github.com">the</a> <b style="color: red">HTML</b> part`, textproto.MIMEHeader{
		"Content-Type": {"text/html; charset=utf-8"},
	})

	data, err := b.Compose()
	if err != nil {
		return []byte{}, err
	}

	return data, nil
}

func (m mail) GetMail() string {
	return "from@test.com"
}

func (m mail) GetRcpt() string {
	return "rcpt@test.com"
}

func (m mail) GetTo() string {
	return "rcpt@test.com"
}

func main() {
	cfg := email.Config{
		Host: "localhost",
		Port: "1025",
	}

	sender := email.NewSMTP(cfg, clock.New(), logs.NullTelem, stats.NullStatter)
	if err := sender.Send(context.Background(), mail{}); err != nil {
		log.Fatal(err)
	}

	log.Print("Email sent!")
}
