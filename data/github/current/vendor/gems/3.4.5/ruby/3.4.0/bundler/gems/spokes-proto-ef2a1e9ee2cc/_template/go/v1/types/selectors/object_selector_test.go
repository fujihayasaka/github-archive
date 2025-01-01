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
				nil,
			),
		},
		{
			"by treeish and path and type",
			NewObjectSelectorByTreeishAndPathAndType(
				types.NewTreeishWithReference(types.DefaultBranch()),
				types.NewPath([]byte("a")),
				types.NewObjectTypeFromTypeString("commit"),
				nil,
			),
		},
		{
			"by treeish and path with symlink options",
			NewObjectSelectorByTreeishAndPath(
				types.NewTreeishWithReference(types.DefaultBranch()),
				types.NewPath([]byte("a")),
				&ObjectSelector_TreeishAndPath_SymlinkResolution{MaxDepth: 2},
			),
		},
		{
			"by id",
			NewObjectSelectorByObjectID(
				types.NewObjectID("1234567890123456789012345678901234567890"),
			),
		},
		{
			"by id and type",
			NewObjectSelectorByObjectIDAndType(
				types.NewObjectID("1234567890123456789012345678901234567890"),
				types.NewObjectTypeFromTypeString("commit"),
			),
		},
		{
			"by name",
			NewObjectSelectorByRevision(
				types.NewRevision([]byte("main")),
			),
		},
		{
			"by name and type",
			NewObjectSelectorByRevisionAndType(
				types.NewRevision([]byte("main")),
				types.NewObjectTypeFromTypeString("commit"),
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
			NewObjectSelectorByTreeishAndPath(nil, nil, nil),
			"twirp error invalid_argument: object_selector.treeish is required",
		},
		{
			"treeishandpath: missing path",
			NewObjectSelectorByTreeishAndPath(
				types.NewTreeishWithReference(types.DefaultBranch()),
				nil,
				nil,
			),
			"twirp error invalid_argument: object_selector.path is required",
		},
		{
			"treeishandpath: invalid symlink depth",
			NewObjectSelectorByTreeishAndPath(
				types.NewTreeishWithReference(types.DefaultBranch()),
				types.NewPath([]byte("a")),
				&ObjectSelector_TreeishAndPath_SymlinkResolution{MaxDepth: 45},
			),
			"twirp error invalid_argument: object_selector.symlink_resolution.max_depth must be between 0 and 40",
		},
		{
			"oidAndPath: missing oid",
			NewObjectSelectorByObjectID(nil),
			"twirp error invalid_argument: object_selector.object is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.selector.Validate(), tt.err)
		})
	}
}
