package deltaingest

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/types"
)

func Test_transientErrorWrapping(t *testing.T) {
	err := newTransientError(errMoreToIngest, "foo/bar")
	require.Equal(t, types.NWOFromString("foo/bar"), nwoFromErr(err))

	errors.Is(err, errMoreToIngest)
	require.ErrorIs(t, err, errMoreToIngest)
	require.NotErrorIs(t, err, &permanentError{})
}
