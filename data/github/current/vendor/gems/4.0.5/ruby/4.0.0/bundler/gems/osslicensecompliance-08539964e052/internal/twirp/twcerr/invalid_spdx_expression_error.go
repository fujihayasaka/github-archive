package twcerr

// This file contains custom Twirp error constructor for spdx expression errors.
//
// NOTE: The <file_name> determines the twirp custom errors public API.  See docs.go for more information.

import (
	"github.com/twitchtv/twirp"
)

const (
	// MetaInvalidSPDXExpression (optional) is a meta key holding the full invalid SPDX expression
	// that is accessible by the client through `err.Meta['invalid_spdx_expression']`.
	MetaInvalidSPDXExpression = "invalid_spdx_expression"
)

// NewInvalidSPDXExpressionError returns a Twirp error with extra metadata. The name of this function MUST
// match the name of this file, without its extension, converted to PascalCase, and prefixed with "New".
// The error name parameter to customizeError MUST be `"<filename_without_extension>"`.
// DO NOT RENAME THIS FUNCTION once the error is published.
//
// This is intended to be machine-detectable by clients (e.g. Ruby) via `err.Meta['error_name']`.
func NewInvalidSPDXExpressionError(baseError twirp.Error, invalidExpression string) error {
	return customizeError(
		baseError,
		"invalid_spdx_expression_error",
		invalidSPDXExpressionMessage(invalidExpression),
		map[string]string{MetaInvalidSPDXExpression: invalidExpression},
	)
}

// invalidSPDXExpressionMessage constructs an error message with the invalid SPDX expression,
// truncated to fit within messageMaxLen defined in errors.go.
func invalidSPDXExpressionMessage(invalidExpression string) string {
	msg := "invalid SPDX expression: " + invalidExpression
	if len(msg) >= messageMaxLen {
		const suffix = "..."
		return msg[:messageMaxLen-len(suffix)] + suffix
	}
	return msg
}
