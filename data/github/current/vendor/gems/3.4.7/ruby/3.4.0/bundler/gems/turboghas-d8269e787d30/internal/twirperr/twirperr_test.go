package twirperr_test

import (
	"testing"

	"github.com/github/turboghas/internal/twirperr"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestIsTwirpError(t *testing.T) {
	require.True(t, twirperr.IsTwirpError(twirp.NotFoundError(""), twirp.NotFound))
	require.False(t, twirperr.IsTwirpError(twirp.InternalError(""), twirp.NotFound))
	require.False(t, twirperr.IsTwirpError(errors.New(""), twirp.NotFound))
	require.True(t, twirperr.IsTwirpError(twirp.NotFoundError(""), twirp.FailedPrecondition, twirp.NotFound))
	require.True(t, twirperr.IsTwirpError(twirp.NewError(twirp.FailedPrecondition, ""), twirp.FailedPrecondition, twirp.NotFound))
}
