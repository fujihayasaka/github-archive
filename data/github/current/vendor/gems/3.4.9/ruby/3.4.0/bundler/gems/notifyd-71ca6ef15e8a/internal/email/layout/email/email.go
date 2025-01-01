// Package email implements an email interface.
package email

// Email interface represents something that can be delivered as an email.
type Email interface {
	GetBody() ([]byte, error)
	GetMail() string
	GetTo() string
	GetRcpt() string
}
