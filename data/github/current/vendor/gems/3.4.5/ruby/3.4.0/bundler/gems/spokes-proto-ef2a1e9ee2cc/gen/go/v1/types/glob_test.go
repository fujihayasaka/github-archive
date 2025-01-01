package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewGlob(t *testing.T) {
	glob := []byte("refs/tags/*")
	g := NewGlob(glob)
	require.Equal(t, &Glob{Glob: glob}, g)
}

func TestGlobValidate(t *testing.T) {
	var g *Glob
	require.NoError(t, g.Validate())

	g = &Glob{}
	require.EqualError(t, g.Validate(), "twirp error invalid_argument: glob.glob is required")

	g = &Glob{Glob: []byte("")}
	require.EqualError(t, g.Validate(), "twirp error invalid_argument: glob.glob is required")

	g = NewGlob([]byte("refs/heads"))
	require.NoError(t, g.Validate())
}
