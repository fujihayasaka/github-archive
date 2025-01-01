package email

import (
	"errors"
	"io"

	"github.com/emersion/go-sasl"
	"github.com/emersion/go-smtp"
)

// The Backend implements SMTP server methods. We are reusing this to pass and
// validate test expectations
type Backend struct {
	Username string
	Password string
	// This is very the received data will be written for assertions in the test
	ReceivedDataChannel chan string
	ReceivedRcpts       string
	AllowAnonymousLogin bool
}

// NewSession creates a new session.
func (bkd *Backend) NewSession(_ *smtp.Conn) (smtp.Session, error) {
	return &Session{backend: bkd}, nil
}

// AnonymousLogin creates a new anonymous session.
func (bkd *Backend) AnonymousLogin(_ *smtp.Conn) (smtp.Session, error) {
	if bkd.AllowAnonymousLogin {
		return &Session{backend: bkd}, nil
	}
	return Session{backend: bkd}, errors.New("anonymous login not allowed")
}

// Login creates a new session.
func (bkd *Backend) Login(_ *smtp.Conn, username, password string) (smtp.Session, error) {
	if username != bkd.Username || password != bkd.Password {
		return Session{backend: bkd}, errors.New("invalid username or password")
	}
	return Session{backend: bkd}, nil
}

// A Session is returned after EHLO.
type Session struct {
	backend *Backend
}

// AuthMechanisms returns the supported authentication mechanisms.
func (s Session) AuthMechanisms() []string {
	return []string{sasl.Plain}
}

// Auth creates a new SASL server for the given mechanism.
func (s Session) Auth(mech string) (sasl.Server, error) {
	return sasl.NewPlainServer(func(identity, username, password string) error {
		if identity != "" && identity != username {
			return errors.New("invalid username or password")
		}
		if username != s.backend.Username || password != s.backend.Password {
			return errors.New("invalid username or password")
		}
		s.backend.AllowAnonymousLogin = true
		return nil
	}), nil
}

// Mail returns nil.
func (s Session) Mail(from string, opts *smtp.MailOptions) error {
	return nil
}

// Rcpt updates the received receipt.
func (s Session) Rcpt(to string, _ *smtp.RcptOptions) error {
	s.backend.ReceivedRcpts = to
	return nil
}

// Data writes the received data to the backend.
func (s Session) Data(r io.Reader) error {
	var b []byte
	var err error
	if b, err = io.ReadAll(r); err != nil {
		return err
	}
	s.backend.ReceivedDataChannel <- string(b)
	return nil
}

// Reset does nothing.
func (s Session) Reset() {}

// Logout returns nil.
func (s Session) Logout() error {
	return nil
}
