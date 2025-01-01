// Package twirperr contains methods for checking for Twirp status codes.
package twirperr

import (
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

func IsTwirpError(err error, codes ...twirp.ErrorCode) bool {
	var twirpErr twirp.Error
	if errors.As(err, &twirpErr) {
		for _, code := range codes {
			if twirpErr.Code() == code {
				return true
			}
		}

	}
	return false
}

// causer is an unexported github.com/pkg/errors interface that is exposing the
// underlying cause of an error.
type causer interface {
	Cause() error
}

// LastCause returns only the last cause, instead of the topmost error that
// does not implement causer, which is assumed to be the original cause. This
// allows us to keep the backtrace, as we use pkg/errors throughout our code
// base.
func LastCause(err error) error {
	if err == nil {
		return err
	}

	var cause causer
	if errors.As(err, &cause) {
		return cause.Cause()
	}

	return err
}
