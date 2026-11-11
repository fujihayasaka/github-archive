package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewPushSelector(t *testing.T) {
	ref := types.NewReference([]byte("refs/heads/master"))
	before := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	after := types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")

	refUpdate := types.NewReferenceUpdate(ref, before, after)
	ps := NewPushSelector([]*types.ReferenceUpdate{refUpdate})
	require.Equal(t, &PushSelector{ReferenceUpdates: []*types.ReferenceUpdate{refUpdate}}, ps)
}

func TestPushSelectorValidate(t *testing.T) {
	var nilPushSelector *PushSelector
	require.NoError(t, nilPushSelector.Validate())

	ref := types.NewReference([]byte("refs/heads/master"))
	before := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	after := types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")

	refUpdate := types.NewReferenceUpdate(ref, before, after)

	valid := NewPushSelector([]*types.ReferenceUpdate{refUpdate})
	require.NoError(t, valid.Validate())

	emptySelector := NewPushSelector([]*types.ReferenceUpdate{})
	require.EqualError(t, emptySelector.Validate(), "twirp error invalid_argument: reference_updates is required")

	invalidRefUpdate := types.NewReferenceUpdate(nil, nil, nil)
	invalidSelector := NewPushSelector([]*types.ReferenceUpdate{invalidRefUpdate})
	require.EqualError(t, invalidSelector.Validate(), "twirp error invalid_argument: reference is required")
}
