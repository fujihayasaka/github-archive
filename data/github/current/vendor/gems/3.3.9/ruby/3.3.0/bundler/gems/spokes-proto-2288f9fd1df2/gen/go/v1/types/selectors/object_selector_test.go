package selectors

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
)

func TestObjectSelectorValidate(t *testing.T) {
	var tests = []struct {
		name     string
		selector *ObjectSelector
	}{
		{
			"by treeish and path",
			NewObjectSelectorByTreeishAndPath(
				types.NewTreeishWithReference(types.DefaultBranch()),
				types.NewPath([]byte("a")),
			),
		},
		{
			"by id",
			NewObjectSelectorByObjectID(
				types.NewObjectID("1234567890123456789012345678901234567890"),
			),
		},
		{
			"by name",
			NewObjectSelectorByRevision(
				types.NewRevision([]byte("main")),
			),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.selector.Validate())
		})
	}
}

func TestObjectSelectorValidateErrors(t *testing.T) {
	var tests = []struct {
		name     string
		selector *ObjectSelector
		err      string
	}{
		{
			"empty",
			&ObjectSelector{},
			"twirp error invalid_argument: object_selector.object is required",
		},
		{
			"treeishandpath: missing treeish",
			NewObjectSelectorByTreeishAndPath(nil, nil),
			"twirp error invalid_argument: object_selector.treeish is required",
		},
		{
			"treeishandpath: missing path",
			NewObjectSelectorByTreeishAndPath(
				types.NewTreeishWithReference(types.DefaultBranch()),
				nil,
			),
			"twirp error invalid_argument: object_selector.path is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.selector.Validate(), tt.err)
		})
	}
}
