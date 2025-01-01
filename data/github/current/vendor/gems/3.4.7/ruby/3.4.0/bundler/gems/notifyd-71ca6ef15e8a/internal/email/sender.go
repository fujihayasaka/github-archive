package email

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/smtp"
	"net/textproto"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	emailpkg "github.com/github/notifyd/internal/email/layout/email"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
)

// Sender defines how an entity that would send an email needs to behave. Not all implementations
// deliver actual emails. Some only log results instead.
type Sender interface {
	// Send will deliver the given email.
	Send(ctx context.Context, email emailpkg.Email) error
}

// ErrUnknownSender is an error returned when the configured sender is not one of "smtp" or
// "logger"
var ErrUnknownSender = errors.New("unknown email sender type")

// logSender implements the Sender interface by logging that it would send en email rather than
// delivering it for real.
type logSender struct {
	telem *telemetry.Provider
}

// NewLog creates a new log sender.
func NewLog(telem *telemetry.Provider) Sender {
	return logSender{telem: telem}
}

// Send implements the interface for Sender
func (s logSender) Send(ctx context.Context, email emailpkg.Email) error {
	ctx = o11y.CtxSetPackage(ctx, "email")
	s.telem.Logger.
		WithFields(
			kvp.String("ctx", "logger"),
			kvp.String("gh.notifyd.email.from", email.GetMail()),
			kvp.String("gh.notifyd.email.to", email.GetTo())).
		WithContext(ctx).
		Info("email delivery")
	return nil
}

// smtpSender uses the provided credentials to deliver a real email.
type smtpSender struct {
	clock    clockpkg.Clock
	statter  stats.Client
	telem    *telemetry.Provider
	host     string
	username string
	password string
	address  string
	useAuth  bool
	useTLS   bool
}

// NewSMTP creates a new SMTP sender.
func NewSMTP(cfg Config, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) Sender {
	return &smtpSender{
		clock:    clock,
		statter:  statter,
		telem:    telem,
		host:     cfg.Host,
		username: cfg.Username,
		password: cfg.Password,
		address:  fmt.Sprintf("%s:%s", cfg.Host, cfg.Port),
		useAuth:  cfg.UseAuth,
		useTLS:   cfg.UseTLS,
	}
}

// Send performs an email send of a notification
//
// TODO: currently this uses the context only for logger field extraction but
// doesn't observe cancellation. We need to decide whether we want to stop
// SMTP execution if the context gets cancelled
func (s *smtpSender) Send(ctx context.Context, email emailpkg.Email) error {
	ctx = o11y.CtxSetPackage(ctx, "email")
	logger := s.telem.Logger.WithContext(ctx).WithFields(
		kvp.String("ctx", "smtp"),
		kvp.Bool("gh.notifyd.smtp.auth", s.useAuth),
		kvp.String("gh.notifyd.smtp.host", s.address))

	startTime := s.clock.Now()
	logger.Info("dialing")
	c, err := smtp.Dial(s.address)
	if err != nil {
		logger.WithError(err).Error("error connecting to smtp host")
		return errors.Wrap(err, "dialing connection").With(errors.MarkRetriable())
	}

	if err = s.smtpSend(ctx, email, c); err != nil {
		msg := "sending via smtp"
		// if we have a retriable error in some way we keep propagating that
		// attribute in the wrapped error
		if isRetriableSMTPError(err) {
			return errors.Wrap(err, msg).With(errors.MarkRetriable())
		}
		logger.WithError(err).Error("error: " + msg)
		return errors.Wrap(err, msg)
	}

	duration := s.clock.Since(startTime)
	s.statter.DistributionMs("email.send_duration", stats.Tags{
		"smtpHost": s.address,
		"status":   "success",
	}, duration)

	logger.WithFields(kvp.Duration("gh.duration_ms", duration)).Info("sent email")
	return nil
}

func (s *smtpSender) smtpSend(ctx context.Context, email emailpkg.Email, c *smtp.Client) error {
	logger := s.telem.Logger.WithContext(ctx).WithFields(
		kvp.String("ctx", "smtp"),
		kvp.Bool("gh.notifyd.smtp.auth", s.useAuth),
		kvp.String("gh.notifyd.smtp.host", s.address))

	if s.useTLS {
		//nolint:gosec // It is an internal server, we're aware, it is ok.
		if err := c.StartTLS(&tls.Config{InsecureSkipVerify: true}); err != nil {
			return errors.Wrap(err, "starting TLS connection").With(errors.MarkRetriable())
		}
	}
	logger.Info("dialed into host")

	if s.useAuth {
		auth := smtp.PlainAuth("", s.username, s.password, s.host)
		if err := c.Auth(auth); err != nil {
			return errors.Wrap(err, "authenticating SMTP client")
		}
		logger.Info("authenticated")
	} else {
		logger.Info("skipping SMTP auth ")
	}

	if err := c.Mail(email.GetMail()); err != nil {
		return errors.Wrap(err, fmt.Sprintf("unable to add SMTP sender: %s", email.GetMail()))
	}

	logger.Info("adding SMTP recipient")
	if err := c.Rcpt(email.GetRcpt()); err != nil {
		return errors.Wrap(err, "adding SMTP recipient")
	}

	logger.Info("opening SMTP email body")
	body, err := c.Data()
	if err != nil {
		return errors.Wrap(err, "opening SMTP body stream")
	}

	logger.Info("writing SMTP email body")
	content, err := email.GetBody()
	if err != nil {
		return errors.Wrap(err, "composing email body")
	}

	if _, err = body.Write(content); err != nil {
		logger.WithError(err).Error("error writing SMTP email body")
		return errors.Wrap(err, "writing SMTP email body")
	}

	logger.Info("closing SMTP email body")
	if err := body.Close(); err != nil {
		logger.WithError(err).Error("error closing SMTP body stream")
		return errors.Wrap(err, "closing SMTP body stream")
	}

	logger.Info("closing SMTP connection")
	if err := c.Quit(); err != nil {
		logger.WithError(err).Error("error closing SMTP connection")
		return errors.Wrap(err, "closing SMTP connection")
	}

	return nil
}

// isRetriableSMTPError examines an error to determine whether it's retriable.
// This was initially based on what RFC5321 (section 4.2.1
// "Reply Code Severities and Theory") because 5xx errors
// may also be caused by temporary issues or misconfigurations in the server.
// It was decided to implement a denylist instead of an allowlist to be more
// defensive against this kind of issues. Further details are available at
// https://github.com/github/notifyd/issues/3782
func isRetriableSMTPError(err error) bool {
	// shortcut in case the error is already marked retriable
	if errors.IsRetriable(err) {
		return true
	}
	// SMTP uses net/textproto for protocol parsing and directly passes its
	// errors through, see
	// https://github.com/golang/go/blob/5d5ed57b134b7a02259ff070864f753c9e601a18/src/net/textproto/reader.go#L287-L289
	var textprotoError *textproto.Error
	if ok := errors.As(err, &textprotoError); ok {
		// Add codes that mustn't be retried here.
		//nolint:gocritic,revive // This is a template that we'll fill in over time
		switch textprotoError.Code {
		default:
			return true
		}
	}
	return true
}
