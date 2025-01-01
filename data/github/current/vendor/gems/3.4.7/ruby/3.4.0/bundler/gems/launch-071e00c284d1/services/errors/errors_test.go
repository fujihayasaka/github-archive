package errors

import (
	"errors"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestErrors(t *testing.T) {
	t.Run("Test that NewUnimplementedError can format message without additional parameters", func(t *testing.T) {
		rpcerr := NewUnimplementedError("Something b0rk3d, herp derp.")
		assert.Error(t, rpcerr)
		assert.Equal(t, "twirp error unimplemented: Something b0rk3d, herp derp.", rpcerr.Error())
	})
	t.Run("Test that NewUnimplementedError can format message with additional parameters", func(t *testing.T) {
		rpcerr := NewUnimplementedError("%s b0rk3d, herp derp.", "Something")
		assert.Error(t, rpcerr)
		assert.Equal(t, "twirp error unimplemented: Something b0rk3d, herp derp.", rpcerr.Error())
	})
}

func Test_ExtractHTTPError(t *testing.T) {
	tcs := []struct {
		desc               string
		err                error
		expectedReturnCode int
		expectedMsg        string
		expectedIsOk       bool
	}{
		{
			desc:               "handles twirp InvalidArgument error",
			err:                twirp.NewError(twirp.InvalidArgument, "that argument was invalid"),
			expectedReturnCode: http.StatusUnprocessableEntity,
			expectedMsg:        "that argument was invalid",
			expectedIsOk:       true,
		},
		{
			desc:               "handles twirp FailedPrecondition error",
			err:                twirp.NewError(twirp.FailedPrecondition, "expected more cowbell"),
			expectedReturnCode: http.StatusUnprocessableEntity,
			expectedMsg:        "Bad request - expected more cowbell",
			expectedIsOk:       true,
		},
		{
			desc:               "handles twirp NotFound error",
			err:                twirp.NewError(twirp.NotFound, "oops! we could not find that"),
			expectedReturnCode: http.StatusNotFound,
			expectedMsg:        "oops! we could not find that",
			expectedIsOk:       true,
		},
		{
			desc:               "handle twirp PermissionDenied error",
			err:                twirp.NewError(twirp.PermissionDenied, "those permissions are sus"),
			expectedReturnCode: http.StatusForbidden,
			expectedMsg:        "Forbidden",
			expectedIsOk:       true,
		},
		{
			desc:               "handles twirp Unauthenticated error",
			err:                twirp.NewError(twirp.Unauthenticated, "that ID looks fake!"),
			expectedReturnCode: http.StatusUnauthorized,
			expectedMsg:        "Unauthorized",
			expectedIsOk:       true,
		},
		{
			desc:               "handles twirp ResourceExhausted error",
			err:                twirp.NewError(twirp.ResourceExhausted, "resources have been exhausted"),
			expectedReturnCode: http.StatusTooManyRequests,
			expectedMsg:        "resources have been exhausted",
			expectedIsOk:       true,
		},
		{
			desc:               "handles non-twirp error",
			err:                errors.New("this is not a Twirp error!"),
			expectedReturnCode: 0,
			expectedMsg:        "",
			expectedIsOk:       false,
		},
		{
			desc:               "handles nil error",
			err:                nil,
			expectedReturnCode: 0,
			expectedMsg:        "",
			expectedIsOk:       false,
		},
	}

	for _, tc := range tcs {
		t.Run(tc.desc, func(t *testing.T) {
			returnCode, msg, isOk := ExtractHTTPError(tc.err)
			require.Equal(t, tc.expectedReturnCode, returnCode, "return codes didn't match")
			require.Equal(t, tc.expectedMsg, msg, "error messages didn't match")
			require.Equal(t, tc.expectedIsOk, isOk, "'ok' indicators didn't match")
		})
	}
}
