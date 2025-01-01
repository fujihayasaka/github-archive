package twerrors_test

import (
	"strings"
	"testing"

	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestNewErrorHasCorrectStack(t *testing.T) {
	e := twerrors.NewError(twirp.AlreadyExists, "test")
	var s (interface{ StackTrace() errors.StackTrace })
	require.True(t, errors.As(e, &s))

	// The top frame is the error creation in this function
	bytes, err := s.StackTrace()[0].MarshalText()
	require.NoError(t, err)
	require.True(t, strings.HasPrefix(string(bytes), "github.com/github/turboscan/ts/twirp/twerrors_test.TestNewErrorHasCorrectStack"))
}
