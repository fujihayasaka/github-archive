package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewTreeishSelector(t *testing.T) {
	ref := types.NewReference([]byte("refs/heads/main"))

	treeish := types.NewTreeishWithReference(ref)
	ts := NewTreeishSelector(treeish)
	require.Equal(t, &TreeishSelector{Treeish: treeish}, ts)
}

func TestTreeishSelectorValidate(t *testing.T) {
	var nilTreeishSelector *TreeishSelector
	require.NoError(t, nilTreeishSelector.Validate())

	oid := types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")
	treeish := types.NewTreeishWithObjectID(oid)

	valid := NewTreeishSelector(treeish)
	require.NoError(t, valid.Validate())

	emptySelector := NewTreeishSelector(nil)
	require.EqualError(t, emptySelector.Validate(), "twirp error invalid_argument: treeish is required")

	invalidTreeish := types.NewTreeishWithObjectID(nil)
	invalidSelector := NewTreeishSelector(invalidTreeish)
	require.EqualError(t, invalidSelector.Validate(), "twirp error invalid_argument: treeish.oid is required")
}
