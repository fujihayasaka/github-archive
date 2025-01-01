package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewRefGlobSelector(t *testing.T) {
	g1 := types.NewGlob([]byte("refs/heads/*"))
	g2 := types.NewGlob([]byte("refs/tags/*"))

	globs := NewRefGlobSelector(g1, g2)
	require.Equal(t, &RefGlobSelector{Include: []*types.Glob{g1, g2}}, globs)
}

func TestNewRefGlobSelectorWithExclude(t *testing.T) {
	g1 := types.NewGlob([]byte("refs/heads/*"))
	g2 := types.NewGlob([]byte("refs/tags/*"))
	g3 := types.NewGlob([]byte("refs/pull/*"))

	globs := NewRefGlobSelectorWithExclude([]*types.Glob{g1, g2}, []*types.Glob{g3})
	require.Equal(t, &RefGlobSelector{Include: []*types.Glob{g1, g2}, Exclude: []*types.Glob{g3}}, globs)
}

func TestRefGlobSelectorValidate(t *testing.T) {
	var nilRefGlobSelector *RefGlobSelector
	require.NoError(t, nilRefGlobSelector.Validate())

	g1 := types.NewGlob([]byte("refs/heads/*"))
	g2 := types.NewGlob([]byte("refs/tags/*"))

	valid := NewRefGlobSelector(g1, g2)
	require.NoError(t, valid.Validate())

	validWithExclude := NewRefGlobSelectorWithExclude([]*types.Glob{}, []*types.Glob{g1})
	require.NoError(t, validWithExclude.Validate())

	emptySelector := NewRefGlobSelector()
	require.EqualError(t, emptySelector.Validate(), "twirp error invalid_argument: include and/or exclude globs are required")

	invalidGlob := types.NewGlob([]byte(""))
	invalidSelector := NewRefGlobSelector(invalidGlob)
	require.EqualError(t, invalidSelector.Validate(), "twirp error invalid_argument: glob.glob is required")
}
