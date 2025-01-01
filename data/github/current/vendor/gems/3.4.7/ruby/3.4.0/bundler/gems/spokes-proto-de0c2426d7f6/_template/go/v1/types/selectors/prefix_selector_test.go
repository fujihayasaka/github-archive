package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewPrefixSelector(t *testing.T) {
	p1 := types.NewPrefix([]byte("refs/heads/"))
	p2 := types.NewPrefix([]byte("refs/tags/"))

	prefixes := NewPrefixSelector(p1, p2)
	require.Equal(t, &PrefixSelector{Prefixes: []*types.Prefix{p1, p2}}, prefixes)
}

func TestPrefixSelectorValidate(t *testing.T) {
	var nilPrefixSelector *PrefixSelector
	require.NoError(t, nilPrefixSelector.Validate())

	p1 := types.NewPrefix([]byte("refs/heads/"))
	p2 := types.NewPrefix([]byte("refs/tags/"))

	valid := NewPrefixSelector(p1, p2)
	require.NoError(t, valid.Validate())

	emptySelector := NewPrefixSelector()
	require.EqualError(t, emptySelector.Validate(), "twirp error invalid_argument: prefixes is required")

	invalidPrefix := types.NewPrefix([]byte{})
	invalidSelector := NewPrefixSelector(invalidPrefix)
	require.EqualError(t, invalidSelector.Validate(), "twirp error invalid_argument: prefix.prefix is required")
}
