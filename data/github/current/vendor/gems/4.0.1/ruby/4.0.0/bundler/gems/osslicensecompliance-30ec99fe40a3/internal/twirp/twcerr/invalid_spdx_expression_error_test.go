package twcerr

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestInvalidSPDXExpressionMessage_NoTruncation(t *testing.T) {
	msg := invalidSPDXExpressionMessage("MIT-BAD-ID AND Apache-2.0-BAD-ID")
	assert.NotContains(t, msg, "...", "expected no truncation, got %q", msg)
	assert.LessOrEqual(t, len(msg), messageMaxLen, "expected message len <= %d, got %d: %q", messageMaxLen, len(msg), msg)
}

func TestInvalidSPDXExpressionMessage_TruncatesWithEllipsis(t *testing.T) {
	expression := strings.Join([]string{
		"BSD-2-Clause-BAD-ID",
		"BSD-3-Clause-BAD-ID",
		"Apache-2.0-BAD-ID",
		"MIT-BAD-ID",
		"ISC-BAD-ID",
		"MPL-2.0-BAD-ID",
		"LGPL-2.1-only-BAD-ID",
		"GPL-3.0-only-BAD-ID",
		"CDDL-1.0-BAD-ID",
	}, " OR ")
	msg := invalidSPDXExpressionMessage(expression)
	assert.LessOrEqual(t, len(msg), messageMaxLen, "expected message len <= %d, got %d: %q", messageMaxLen, len(msg), msg)
	assert.True(t, strings.HasSuffix(msg, "..."), "expected message to end with ellipsis, got %q", msg)

	expected := "invalid SPDX expression: BSD-2-Clause-BAD-ID OR BSD-3-Clause-BAD-ID OR Apache-2.0-BAD-ID OR MIT-BAD-ID OR ISC-BAD-ID ..."
	assert.Equal(t, expected, msg)
}

func TestInvalidSPDXExpressionError_ArgumentErrorWithTwirpFields(t *testing.T) {
	argumentName := "spdx_expression"
	cause := "couldn't parse SPDX expression"
	invalidExpression := "MIT AND bad-id"

	argError := twirp.InvalidArgumentError(argumentName, cause)
	err := NewInvalidSPDXExpressionError(argError, invalidExpression)

	// test baseError is properly wrapped
	var twerr twirp.Error
	require.ErrorAs(t, err, &twerr)
	assert.Equal(t, twirp.InvalidArgument, twerr.Code())
	assert.Equal(t, argumentName, twerr.Meta("argument"))

	// test customized fields
	assert.Equal(t, "invalid_spdx_expression_error", twerr.Meta(MetaErrorName))
	assert.Equal(t, argumentName+" "+cause, twerr.Meta(MetaCause))
	assert.Equal(t, "invalid SPDX expression: MIT AND bad-id", twerr.Msg())
	assert.Equal(t, invalidExpression, twerr.Meta(MetaInvalidSPDXExpression))
}

func TestInvalidSPDXExpressionError_InternalErrorTwirpFields(t *testing.T) {
	cause := "couldn't parse SPDX expression"
	invalidExpression := "MIT AND bad-id"

	intError := twirp.InternalError(cause)
	err := NewInvalidSPDXExpressionError(intError, invalidExpression)

	// test baseError is properly wrapped
	var twerr twirp.Error
	require.ErrorAs(t, err, &twerr)
	assert.Equal(t, twirp.Internal, twerr.Code())

	// test customized fields
	assert.Equal(t, "invalid_spdx_expression_error", twerr.Meta(MetaErrorName))
	assert.Equal(t, cause, twerr.Meta(MetaCause))
	assert.Equal(t, "invalid SPDX expression: MIT AND bad-id", twerr.Msg())
	assert.Equal(t, invalidExpression, twerr.Meta(MetaInvalidSPDXExpression))
}
