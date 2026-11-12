package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewObjectIDSelector(t *testing.T) {
	oid1 := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	oid2 := types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")

	oids := NewObjectIDSelector(oid1, oid2)
	require.Equal(t, &ObjectIDSelector{Oids: []*types.ObjectID{oid1, oid2}}, oids)
}

func TestObjectIDSelectorValidate(t *testing.T) {
	var nilObjectIDSelector *ObjectIDSelector
	require.NoError(t, nilObjectIDSelector.Validate())

	oid1 := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	oid2 := types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")

	valid := NewObjectIDSelector(oid1, oid2)
	require.NoError(t, valid.Validate())

	emptySelector := NewObjectIDSelector()
	require.EqualError(t, emptySelector.Validate(), "twirp error invalid_argument: oids is required")

	invalidObjectID := types.NewObjectID("")
	invalidSelector := NewObjectIDSelector(invalidObjectID)
	require.EqualError(t, invalidSelector.Validate(), "twirp error invalid_argument: object_id.id is required")
}
