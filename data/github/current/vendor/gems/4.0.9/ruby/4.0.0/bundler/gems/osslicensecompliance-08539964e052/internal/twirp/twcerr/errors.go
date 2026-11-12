package twcerr

// This file contains custom Twirp error constructors and helpers.  To make custom errors accessible
// in the generated ruby gem, add helper methods in /script/templates/ruby/twirp/errors.rb

import (
	"github.com/twitchtv/twirp"
)

const (
	// MetaErrorName is a stable discriminator that clients can switch on.
	//
	// Twirp itself does not preserve server-side error *types* across the wire;
	// clients only receive code/message/meta.
	MetaErrorName = "error_name"

	// MetaCause is a meta key containing the cause of the baseError for the customized error
	// and is accessible by the client through `err.Meta['cause']`.
	MetaCause = "cause"

	metaValueMaxLen = 1024
	messageMaxLen   = 120
)

func customizeError(baseError twirp.Error, customErrorName, customErrorMsg string, customMetadata map[string]string) twirp.Error {
	err := twirp.NewError(baseError.Code(), customErrorMsg)
	err = withMeta(err, MetaErrorName, customErrorName)
	err = withMeta(err, MetaCause, baseError.Msg())

	// keep original metadata from baseError
	meta := baseError.MetaMap()
	for k, v := range meta {
		err = withMeta(err, k, v)
	}

	// add custom metadata
	for k, v := range customMetadata {
		err = withMeta(err, k, v)
	}
	return err
}

func withMeta(err twirp.Error, key, value string) twirp.Error {
	if value == "" {
		return err
	}
	if len(value) > metaValueMaxLen {
		value = value[:metaValueMaxLen]
	}
	return err.WithMeta(key, value)
}
