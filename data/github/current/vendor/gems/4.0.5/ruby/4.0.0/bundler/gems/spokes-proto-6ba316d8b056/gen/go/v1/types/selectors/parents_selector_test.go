package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

var (
	oid1 = types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	oid2 = types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")
)

func TestNewParentsSelector(t *testing.T) {
	// Single parent
	parents := NewParentsSelector(oid1)
	require.Equal(t, &ParentsSelector{Parents: []*types.ObjectID{oid1}}, parents)

	// Multiple parents
	parents = NewParentsSelector(oid1, oid2)
	require.Equal(t, &ParentsSelector{Parents: []*types.ObjectID{oid1, oid2}}, parents)
}

func TestParentsSelectorValidate(t *testing.T) {
	var tests = []struct {
		name     string
		selector *ParentsSelector
	}{
		{
			"single parent",
			NewParentsSelector(oid1),
		},
		{
			"multiple parents",
			NewParentsSelector(oid1, oid2),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.selector.Validate())
		})
	}
}

func TestParentsSelectorValidateErrors(t *testing.T) {
	var tests = []struct {
		name     string
		selector *ParentsSelector
		err      string
	}{
		{
			"missing parents",
			&ParentsSelector{},
			"twirp error invalid_argument: parents_selector.parents is required",
		},
		{
			"nil parent",
			NewParentsSelector(nil, oid2),
			"twirp error invalid_argument: parents_selector.parents is required",
		},
		{
			"invalid parent",
			NewParentsSelector(&types.ObjectID{}, oid2),
			"twirp error invalid_argument: object_id.id is required",
		},
		{
			"too many parents",
			NewParentsSelector(oid1, oid1, oid1, oid1, oid1, oid1, oid1, oid1, oid1, oid1, oid1),
			"twirp error invalid_argument: parents_selector.parents may contain up to 10 parents",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.selector.Validate(), tt.err)
		})
	}
}
