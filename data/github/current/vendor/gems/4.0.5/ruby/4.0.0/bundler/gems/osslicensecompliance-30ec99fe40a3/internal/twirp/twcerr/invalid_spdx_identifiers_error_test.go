package twcerr

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestInvalidSPDXIdentifiersMessage_NoTruncation(t *testing.T) {
	msg := invalidSPDXIdentifiersMessage([]string{"MIT-BAD-ID", "Apache-2.0-BAD-ID"})
	assert.NotContains(t, msg, "...", "expected no truncation, got %q", msg)
	assert.LessOrEqual(t, len(msg), messageMaxLen, "expected message len <= %d, got %d: %q", messageMaxLen, len(msg), msg)
}

func TestInvalidSPDXIdentifiersMessage_TruncatesWithEllipsis(t *testing.T) {
	ids := []string{
		"BSD-2-Clause-BAD-ID",
		"BSD-3-Clause-BAD-ID",
		"Apache-2.0-BAD-ID",
		"MIT-BAD-ID",
		"ISC-BAD-ID",
		"MPL-2.0-BAD-ID",
		"LGPL-2.1-only-BAD-ID",
		"GPL-3.0-only-BAD-ID",
		"CDDL-1.0-BAD-ID",
	}
	msg := invalidSPDXIdentifiersMessage(ids)
	assert.LessOrEqual(t, len(msg), messageMaxLen, "expected message len <= %d, got %d: %q", messageMaxLen, len(msg), msg)
	assert.True(t, strings.HasSuffix(msg, "..."), "expected message to end with ellipsis, got %q", msg)

	expected := "invalid SPDX license identifiers: BSD-2-Clause-BAD-ID, BSD-3-Clause-BAD-ID, Apache-2.0-BAD-ID, MIT-BAD-ID, ..."
	assert.Equal(t, expected, msg)
}

func TestInvalidSPDXIdentifiersMessage_TooLongSingleID(t *testing.T) {
	// Single ID that cannot fully fit; we should not include partial IDs.
	msg := invalidSPDXIdentifiersMessage([]string{strings.Repeat("A", messageMaxLen)})
	assert.LessOrEqual(t, len(msg), messageMaxLen, "expected message len <= %d, got %d: %q", messageMaxLen, len(msg), msg)
	assert.True(t, strings.HasSuffix(msg, "..."), "expected message to end with ellipsis, got %q", msg)
}

func TestInvalidSPDXIdentifiersError_ArgumentErrorWithTwirpFields(t *testing.T) {
	argumentName := "spdx_ids"
	invalidIDs := []string{"MIT-BAD-ID", "Apache-2.0-BAD-ID"}
	cause := "couldn't parse SPDX IDs"

	argError := twirp.InvalidArgumentError(argumentName, cause)
	err := NewInvalidSPDXIdentifiersError(argError, invalidIDs)

	// test baseError is properly wrapped
	var twerr twirp.Error
	require.ErrorAs(t, err, &twerr)
	assert.Equal(t, twirp.InvalidArgument, twerr.Code())
	assert.Equal(t, argumentName, twerr.Meta("argument"))

	// test customized fields
	assert.Equal(t, "invalid_spdx_identifiers_error", twerr.Meta(MetaErrorName))
	assert.Equal(t, argumentName+" "+cause, twerr.Meta(MetaCause))
	assert.Equal(t, "invalid SPDX license identifiers: MIT-BAD-ID, Apache-2.0-BAD-ID", twerr.Msg())
	assert.Equal(t, strings.Join(invalidIDs, ","), twerr.Meta(MetaInvalidSPDXIdentifiers))
}

func TestInvalidSPDXIdentifiersError_InternalErrorTwirpFields(t *testing.T) {
	invalidIDs := []string{"MIT-BAD-ID", "Apache-2.0-BAD-ID"}
	cause := "couldn't parse SPDX IDs"

	intError := twirp.InternalError(cause)
	err := NewInvalidSPDXIdentifiersError(intError, invalidIDs)

	// test baseError is properly wrapped
	var twerr twirp.Error
	require.ErrorAs(t, err, &twerr)
	assert.Equal(t, twirp.Internal, twerr.Code())

	// test customized fields
	assert.Equal(t, "invalid_spdx_identifiers_error", twerr.Meta(MetaErrorName))
	assert.Equal(t, cause, twerr.Meta(MetaCause))
	assert.Equal(t, "invalid SPDX license identifiers: MIT-BAD-ID, Apache-2.0-BAD-ID", twerr.Msg())
	assert.Equal(t, strings.Join(invalidIDs, ","), twerr.Meta(MetaInvalidSPDXIdentifiers))
}
