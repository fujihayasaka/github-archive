package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewMergeObjectSelector(t *testing.T) {
	treeish := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	repo := types.NewRepository(1)

	sel := NewMergeObjectSelectorByOid(treeish, repo)
	require.Equal(t,
		&MergeObjectSelector{
			Object: &MergeObjectSelector_ByOid{
				ByOid: treeish,
			},
			SourceRepository: repo,
		},
		sel)
}

func TestMergeObjectSelectorValidate(t *testing.T) {
	treeish := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	repo := types.NewRepository(1)

	var tests = []struct {
		name     string
		selector *MergeObjectSelector
	}{
		{
			"by treeish OID",
			NewMergeObjectSelectorByOid(treeish, repo),
		},
		{
			"missing repo",
			NewMergeObjectSelectorByOid(treeish, nil),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.selector.Validate())
		})
	}
}

func TestMergeObjectSelectorValidateErrors(t *testing.T) {
	treeish := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	invalidTreeish := types.NewObjectID("this is not an object ID")
	invalidRepo := &types.Repository{
		Type: types.Repository_TYPE_INVALID,
		Id:   2,
	}

	var tests = []struct {
		name     string
		selector *MergeObjectSelector
		err      string
	}{
		{
			"missing head",
			&MergeObjectSelector{},
			"twirp error invalid_argument: merge_object_selector.object is required",
		},
		{
			"invalid head",
			NewMergeObjectSelectorByOid(invalidTreeish, nil),
			"twirp error invalid_argument: object_id.id must be a valid object id",
		},
		{
			"invalid repo",
			NewMergeObjectSelectorByOid(treeish, invalidRepo),
			"twirp error invalid_argument: repository.type type must be set",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.selector.Validate(), tt.err)
		})
	}
}
