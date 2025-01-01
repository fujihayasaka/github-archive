package selectors

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

var (
	nilRefSelector *types.Reference
	headRef        = types.NewReference([]byte("HEAD"))
	emptyRef       = types.NewReference([]byte(""))
	nilRef         = types.NewReference(nil)
)

func TestNewDistinctCommitsSelector(t *testing.T) {
	expected := &DistinctCommitsSelector{
		Reference:   headRef,
		Oid:         nil,
		ExcludeOids: createOidsArray(10),
	}
	got := NewDistinctCommitsSelector(headRef, nil, createOidsArray(10)...)

	require.Equal(t, expected, got)
}

func TestDistinctCommitsSelectorValidateError(t *testing.T) {
	var tests = []struct {
		name string
		rs   *DistinctCommitsSelector
		err  string
	}{
		{
			"reference field unpopulated",
			&DistinctCommitsSelector{},
			"twirp error invalid_argument: reference is required",
		},
		{
			"empty reference.name",
			NewDistinctCommitsSelector(emptyRef, nil),
			"twirp error invalid_argument: reference.name is required",
		},
		{
			"nil reference.name",
			NewDistinctCommitsSelector(nilRef, nil),
			"twirp error invalid_argument: reference.name is required",
		},
		{
			"too many exclude oids",
			NewDistinctCommitsSelector(headRef, nil, createOidsArray(11)...),
			"twirp error invalid_argument: exclude_oids may contain up to 10 items",
		},
		{
			"invalid ref oid",
			NewDistinctCommitsSelector(headRef, types.NewObjectID("invalid_oid")),
			"twirp error invalid_argument: object_id.id must be a valid object id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.rs.Validate(), tt.err)
		})
	}
}

func TestDistinctCommitsSelectorValidate(t *testing.T) {
	require.NoError(t, nilRefSelector.Validate())

	validSelector := NewDistinctCommitsSelector(headRef, nil)
	require.NoError(t, validSelector.Validate())
}

func createOidsArray(count int) []*types.ObjectID {
	oids := make([]*types.ObjectID, count)
	for i := 0; i < count; i++ {
		oids[i] = types.NewObjectID(fmt.Sprintf("%040x", i))
	}
	return oids
}
