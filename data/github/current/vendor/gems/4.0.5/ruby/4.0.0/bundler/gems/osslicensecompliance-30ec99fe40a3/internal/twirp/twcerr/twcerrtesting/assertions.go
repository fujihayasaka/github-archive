// Package twcerrtesting provides helper functions for asserting OSS License Compliance
// custom Twirp errors are properly constructed and wrapped in tests.
package twcerrtesting

import (
	"fmt"
	"strings"
	"testing"

	"github.com/github/osslicensecompliance/internal/twirp/twcerr"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// AssertInvalidSPDXExpressionErr asserts that the provided error is a twirp.Error with the expected base error code, message, and metadata for an invalid SPDX expression error.
func AssertInvalidSPDXExpressionErr(t *testing.T, err error, twirpErrCode twirp.ErrorCode, cause, invalidExpression string, argumentName ...string) {
	errMsg, twerrMsg, msgerr := expectedInvalidSPDXExpressionErrorMsg(twirpErrCode, invalidExpression)
	require.NoError(t, msgerr, "unexpected error when generating expected error message: %v", msgerr)

	twerr := assertBaseError(t, err, twirpErrCode, twerrMsg, errMsg, argumentName...)
	assertCustomError(t, twerr, "invalid_spdx_expression_error", cause, map[string]string{
		twcerr.MetaInvalidSPDXExpression: invalidExpression,
	})
}

// AssertInvalidSPDXIdentifiersErr asserts that the provided error is a twirp.Error with the expected base error code, message, and metadata for an invalid SPDX identifiers error.
func AssertInvalidSPDXIdentifiersErr(t *testing.T, err error, twirpErrCode twirp.ErrorCode, cause string, invalidLicenses []string, argumentName ...string) {
	errMsg, twerrMsg, msgerr := expectedInvalidSPDXIdentifiersErrorMsg(twirpErrCode, invalidLicenses)
	require.NoError(t, msgerr, "unexpected error when generating expected error message: %v", msgerr)

	twerr := assertBaseError(t, err, twirpErrCode, twerrMsg, errMsg, argumentName...)
	assertCustomError(t, twerr, "invalid_spdx_identifiers_error", cause, map[string]string{
		twcerr.MetaInvalidSPDXIdentifiers: strings.Join(invalidLicenses, ","),
	})
}

func assertBaseError(t *testing.T, err error, expectedTwirpCode twirp.ErrorCode, expectedTwirpMsg, expectedErrMsg string, argumentName ...string) twirp.Error {
	// test baseError is properly wrapped
	var twerr twirp.Error
	require.Error(t, err)
	require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
	assert.Equal(t, expectedTwirpCode, twerr.Code(), "error code should match the expected Twirp error code")
	assert.Equal(t, expectedTwirpMsg, twerr.Msg(), "twirp error message should match expected Twirp error message")
	assert.Equal(t, expectedErrMsg, err.Error(), "full error message should match expected error message")
	assertOptionalArgumentName(t, twerr, expectedTwirpCode, argumentName)
	return twerr
}

func assertCustomError(t *testing.T, twerr twirp.Error, metaErrorName, metaCause string, additionalMetadata map[string]string) {
	// test customized fields
	assert.Equal(t, metaErrorName, twerr.Meta(twcerr.MetaErrorName))
	assert.Equal(t, metaCause, twerr.Meta(twcerr.MetaCause))
	for metaKey := range additionalMetadata {
		assert.Equal(t, additionalMetadata[metaKey], twerr.Meta(metaKey), "metadata value for key %s should match expected value", metaKey)
	}
}

func assertOptionalArgumentName(t *testing.T, twerr twirp.Error, twirpErrCode twirp.ErrorCode, argumentName []string) {
	if twirpErrCode != twirp.InvalidArgument {
		// argument should only be included for InvalidArgument errors, so we ignore the optional argument name parameter in this case
		require.Equal(t, 0, len(argumentName), "argumentName should not be passed for non-InvalidArgument errors")
		return
	}

	require.Len(t, argumentName, 1, "argumentName is required for InvalidArgument errors")
	expectedArgumentName := argumentName[0]
	require.NotEmpty(t, expectedArgumentName, "argumentName must be non-empty for InvalidArgument errors")
	assert.Equal(t, expectedArgumentName, twerr.Meta("argument"), "argument meta should match the expected argument name")
}

func expectedInvalidSPDXExpressionErrorMsg(twirpErrCode twirp.ErrorCode, invalidExpression string) (errMsg, twerrMsg string, err error) {
	twerrMsg = fmt.Sprintf("invalid SPDX expression: %s", invalidExpression)
	switch twirpErrCode {
	case twirp.Internal:
		errMsg = fmt.Sprintf("twirp error internal: %s", twerrMsg)
		return errMsg, twerrMsg, nil
	case twirp.InvalidArgument:
		errMsg = fmt.Sprintf("twirp error invalid_argument: %s", twerrMsg)
		return errMsg, twerrMsg, nil
	}
	return "", "", fmt.Errorf("unexpected Twirp error code: %s", twirpErrCode)
}

func expectedInvalidSPDXIdentifiersErrorMsg(twirpErrCode twirp.ErrorCode, invalidLicenses []string) (errMsg, twerrMsg string, err error) {
	twerrMsg = fmt.Sprintf("invalid SPDX license identifiers: %v", strings.Join(invalidLicenses, ","))
	switch twirpErrCode {
	case twirp.Internal:
		errMsg = fmt.Sprintf("twirp error internal: %s", twerrMsg)
		return errMsg, twerrMsg, nil
	case twirp.InvalidArgument:
		errMsg = fmt.Sprintf("twirp error invalid_argument: %s", twerrMsg)
		return errMsg, twerrMsg, nil
	}
	return "", "", fmt.Errorf("unexpected Twirp error code: %s", twirpErrCode)
}
