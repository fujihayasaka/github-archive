// Package errutil provides a collection of error-related utility functions.
package errutil

import (
	"github.com/pkg/errors"

	tstwirp "github.com/github/turboscan/ts/twirp"
	matwirp "github.com/github/turboscan/ts/twirp/managed_analyses"
	"github.com/twitchtv/twirp"
)

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

// IsBenign returns true if the error can happen in normal operation.
// These errors should be measured, but not logged as errors.
func IsBenign(twerr twirp.Error) bool {
	switch twerr.Code() { //nolint:exhaustive // We have tight exhaustive checks, mainly for GORM, but here using a default case is ok.
	case twirp.NotFound:
		return true
	case twirp.InvalidArgument:
		return twerr.Msg() == tstwirp.ErrorMsgAnalysisIsNotDeletable || twerr.Msg() == tstwirp.ErrorMsgMissingDeletionConfirmation
	case twirp.AlreadyExists:
		return twerr.Msg() == matwirp.ErrorMsgCodeqlConfigConflict
	default:
		return false
	}
}
