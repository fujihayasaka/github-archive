package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewPrefix(t *testing.T) {
	prefix := []byte("refs/heads")
	p := NewPrefix(prefix)
	require.Equal(t, &Prefix{Prefix: prefix}, p)
}

func TestPrefixValidateErrors(t *testing.T) {
	p := &Prefix{}
	require.EqualError(t, p.Validate(), "twirp error invalid_argument: prefix.prefix is required")
}

func TestPrefixValidate(t *testing.T) {
	var p *Prefix
	require.NoError(t, p.Validate())

	p = NewPrefix([]byte("refs/heads"))
	require.NoError(t, p.Validate())
}
