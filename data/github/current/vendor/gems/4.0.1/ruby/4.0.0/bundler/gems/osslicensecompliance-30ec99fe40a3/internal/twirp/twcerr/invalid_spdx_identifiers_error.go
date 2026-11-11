package twcerr

// This file contains custom Twirp error constructor for spdx identifier errors.
//
// NOTE: The <file_name> determines the twirp custom errors public API.  See docs.go for more information.

import (
	"strings"

	"github.com/twitchtv/twirp"
)

const (
	// MetaInvalidSPDXIdentifiers (optional) is a meta key containing a comma-separated list of invalid SPDX Identifiers
	// that is accessible by the client through `err.Meta['invalid_spdx_identifiers']`.
	MetaInvalidSPDXIdentifiers = "invalid_spdx_identifiers"
)

// NewInvalidSPDXIdentifiersError returns a Twirp error with extra metadata. The name of this function MUST
// match the name of this file, without its extension, converted to PascalCase, and prefixed with "New".
// The error name parameter to customizeError MUST be `"<filename_without_extension>"`.
// DO NOT RENAME THIS FUNCTION once the error is published.
//
// This is intended to be machine-detectable by clients (e.g. Ruby) via `err.Meta['error_name']`.
func NewInvalidSPDXIdentifiersError(baseError twirp.Error, invalidIDs []string) error {
	return customizeError(
		baseError,
		"invalid_spdx_identifiers_error",
		invalidSPDXIdentifiersMessage(invalidIDs),
		map[string]string{MetaInvalidSPDXIdentifiers: strings.Join(invalidIDs, ",")},
	)
}

// invalidSPDXIdentifiersMessage constructs an error message listing invalid SPDX IDs,
// truncated to fit within messageMaxLen defined in errors.go.
func invalidSPDXIdentifiersMessage(invalidIDs []string) string {
	prefix := "invalid SPDX license identifiers: "
	if len(prefix) >= messageMaxLen {
		return prefix[:messageMaxLen]
	}

	remaining := messageMaxLen - len(prefix)
	if len(invalidIDs) == 0 {
		return prefix
	}

	all := strings.Join(invalidIDs, ", ")
	if len(all) <= remaining {
		return prefix + all
	}

	// Truncate: include as many full IDs as possible (no partial IDs), then append "...".
	const suffix = ", ..."
	if remaining <= len(suffix) {
		return prefix[:messageMaxLen-len("...")] + "..."
	}

	budget := remaining - len(suffix)
	var b strings.Builder
	used := 0
	for i, id := range invalidIDs {
		sep := ""
		if i > 0 {
			sep = ", "
		}
		addition := sep + id
		if used+len(addition) > budget {
			break
		}
		addlen, err := b.WriteString(addition)
		if err != nil {
			// Should not happen with strings.Builder
			break
		}
		used += addlen
	}

	if b.Len() == 0 {
		return prefix + "..."
	}
	return prefix + b.String() + suffix
}
