package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewCommitishSelector(t *testing.T) {
	ref := types.NewReference([]byte("refs/heads/main"))

	commitish := types.NewCommitishWithReference(ref)
	ts := NewCommitishSelector(commitish)
	require.Equal(t, &CommitishSelector{Commitish: commitish}, ts)
}

func TestCommitishSelectorValidate(t *testing.T) {
	var nilCommitishSelector *CommitishSelector
	require.NoError(t, nilCommitishSelector.Validate())

	oid := types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")
	commitish := types.NewCommitishWithObjectID(oid)

	valid := NewCommitishSelector(commitish)
	require.NoError(t, valid.Validate())

	emptySelector := NewCommitishSelector(nil)
	require.EqualError(t, emptySelector.Validate(), "twirp error invalid_argument: commitish is required")

	invalidCommitish := types.NewCommitishWithObjectID(nil)
	invalidSelector := NewCommitishSelector(invalidCommitish)
	require.EqualError(t, invalidSelector.Validate(), "twirp error invalid_argument: commitish.oid is required")
}
