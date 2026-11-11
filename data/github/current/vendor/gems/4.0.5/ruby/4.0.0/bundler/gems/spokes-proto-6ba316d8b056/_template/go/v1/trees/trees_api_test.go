package trees

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	repository = types.NewRepository(1)

	oid                    = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	treeish                = types.NewTreeishWithObjectID(oid)
	treeishSelector        = selectors.NewTreeishSelector(treeish)
	treeishAndPathSelector = selectors.NewTreeishAndPathSelector(treeish, types.NewPath([]byte("path")))
	cursor                 = &types.Cursor{Cursor: []byte("abcdef")}

	start         = types.NewReference([]byte("refs/heads/main"))
	end           = types.NewReference([]byte("refs/heads/new-branch"))
	treeishStart  = types.NewTreeishWithReference(start)
	treeishEnd    = types.NewTreeishWithReference(end)
	paths         = []*types.Path{types.NewPath([]byte("path"))}
	rangeSelector = selectors.NewRangeSelector(treeishStart, treeishEnd, paths)
	reqCtx        = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
	objectType    = types.NewObjectTypeFromTypeString("commit")
)

func TestNewListTreesRequest(t *testing.T) {
	req := NewListTreesRequestWithTreeishSelector(reqCtx, repository, treeishSelector).WithRecursive()
	require.Equal(t, req, &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishSelector{TreeishSelector: treeishSelector},
		Recursive:      true,
	})

	req = NewListTreesRequestWithTreeishAndPathSelector(reqCtx, repository, treeishAndPathSelector).WithFlattenPaths().WithCursor(cursor)
	require.Equal(t, req, &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishAndPathSelector{TreeishAndPathSelector: treeishAndPathSelector},
		FlattenPaths:   true,
		Cursor:         cursor,
	})

	req = NewListTreesRequestWithTreeishSelector(reqCtx, repository, treeishSelector).WithIncludeEol()
	require.Equal(t, req, &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishSelector{TreeishSelector: treeishSelector},
		IncludeEol:     true,
	})
}

func TestListTreesRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ListTreesRequest
		err  string
	}{
		{
			"empty",
			&ListTreesRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewListTreesRequestWithTreeishSelector(reqCtx, nil, treeishSelector),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewListTreesRequestWithTreeishSelector(reqCtx, &types.Repository{}, treeishSelector),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing selector",
			&ListTreesRequest{RequestContext: reqCtx, Repository: repository, Selector: nil, Recursive: false},
			"twirp error invalid_argument: selector is required",
		},
		{
			"invalid treeish selector",
			NewListTreesRequestWithTreeishSelector(reqCtx, repository, selectors.NewTreeishSelector(nil)),
			"twirp error invalid_argument: treeish is required",
		},
		{
			"invalid treeish_and_path selector",
			NewListTreesRequestWithTreeishAndPathSelector(reqCtx, repository, selectors.NewTreeishAndPathSelector(treeish, nil)),
			"twirp error invalid_argument: path is required",
		},
		{
			"invalid pathspec",
			NewListTreesRequestWithTreeishSelector(reqCtx, repository, treeishSelector).WithPathspec(&types.Pathspec{
				Items: []*types.PathspecItem{
					{
						Patterns: []*types.Pattern{{Pattern: []byte("docs/*.md")}},
					},
				},
			}),
			"twirp error invalid_argument: pattern_type must be one of: literal, glob, wildcard",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestListTreesRequestValidate(t *testing.T) {
	req := NewListTreesRequestWithTreeishSelector(reqCtx, repository, treeishSelector).WithRecursive()
	require.NoError(t, req.Validate())

	req = NewListTreesRequestWithTreeishAndPathSelector(reqCtx, repository, treeishAndPathSelector).WithRecursive()
	require.NoError(t, req.Validate())
}

func TestNewCompareTreesRequest(t *testing.T) {
	req := NewCompareTreesRequestWithRangeSelector(reqCtx, repository, rangeSelector, true, false, nil)
	require.Equal(t, req, &CompareTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &CompareTreesRequest_RangeSelector{RangeSelector: rangeSelector},
		Recursive:      true,
	})

	req = NewCompareTreesRequestWithRangeSelector(reqCtx, repository, rangeSelector, false, true, nil)
	require.Equal(t, req, &CompareTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &CompareTreesRequest_RangeSelector{RangeSelector: rangeSelector},
		IncludeRenames: true,
	})
}

func TestCompareTreesRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *CompareTreesRequest
		err  string
	}{
		{
			"empty",
			&CompareTreesRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewCompareTreesRequestWithRangeSelector(reqCtx, nil, rangeSelector, false, false, nil),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewCompareTreesRequestWithRangeSelector(reqCtx, &types.Repository{}, rangeSelector, false, false, nil),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing selector",
			&CompareTreesRequest{RequestContext: reqCtx, Repository: repository, Selector: nil, Recursive: false, IncludeRenames: false},
			"twirp error invalid_argument: selector is required",
		},
		{
			"invalid range selector",
			NewCompareTreesRequestWithRangeSelector(reqCtx, repository, selectors.NewRangeSelector(nil, nil, nil), false, false, nil),
			"twirp error invalid_argument: start is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestCompareTreesRequestValidate(t *testing.T) {
	req := NewCompareTreesRequestWithRangeSelector(reqCtx, repository, rangeSelector, true, true, nil)
	require.NoError(t, req.Validate())
}

func TestNewReadTreeEntryOidRequest(t *testing.T) {
	req := NewReadTreeEntryOidRequest(reqCtx, repository, treeishSelector, paths[0], objectType)
	require.Equal(t, req, &ReadTreeEntryOidRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadTreeEntryOidRequest_TreeishSelector{TreeishSelector: treeishSelector},
		Path:           paths[0],
		Type:           objectType,
	})
	require.NoError(t, req.Validate())
}

func TestReadTreeEntryOidRequestValidateOptional(t *testing.T) {
	var tests = []struct {
		name string
		req  *ReadTreeEntryOidRequest
	}{
		{
			"missing path",
			NewReadTreeEntryOidRequest(reqCtx, repository, treeishSelector, nil, objectType),
		},
		{
			"missing type",
			NewReadTreeEntryOidRequest(reqCtx, repository, treeishSelector, paths[0], nil),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.req.Validate())
		})
	}
}

func TestReadTreeEntryOidRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ReadTreeEntryOidRequest
		err  string
	}{
		{
			"empty",
			&ReadTreeEntryOidRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewReadTreeEntryOidRequest(reqCtx, nil, treeishSelector, nil, nil),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewReadTreeEntryOidRequest(reqCtx, &types.Repository{}, treeishSelector, nil, nil),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing selector",
			&ReadTreeEntryOidRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				Selector:       nil,
			},
			"twirp error invalid_argument: selector is required",
		},
		{
			"missing treeish selector",
			NewReadTreeEntryOidRequest(reqCtx, repository, nil, nil, nil),
			"twirp error invalid_argument: selector.treeish_selector is required",
		},
		{
			"invalid treeish selector",
			NewReadTreeEntryOidRequest(reqCtx, repository, selectors.NewTreeishSelector(nil), nil, nil),
			"twirp error invalid_argument: treeish is required",
		},
		{
			"invalid path",
			NewReadTreeEntryOidRequest(reqCtx, repository, treeishSelector, types.NewPath([]byte{}), nil),
			"twirp error invalid_argument: path.name is required",
		},
		{
			"invalid type",
			NewReadTreeEntryOidRequest(reqCtx, repository, treeishSelector, nil, types.NewObjectTypeFromTypeString("invalid")),
			"twirp error invalid_argument: type must be commit, tree, blob or tag",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestNewCreateTreeRequest(t *testing.T) {
	// CreateTree specific test variables
	reqCtxWithTransaction := types.NewRequestContext(
		types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
		types.WithTransactionState([]byte("transaction")),
	)
	baseTreeOid := types.NewObjectID("abcdef1234567890abcdef1234567890abcdef12")
	treeEntry1 := &CreateTreeRequest_TreeEntry{
		Path: types.NewPath([]byte("file1.txt")),
		Oid:  types.NewObjectID("1111111111111111111111111111111111111111"),
		Mode: types.NewMode(0100644), // regular file
	}
	treeEntry2 := &CreateTreeRequest_TreeEntry{
		Path: types.NewPath([]byte("dir/file2.txt")),
		Oid:  types.NewObjectID("2222222222222222222222222222222222222222"),
		Mode: types.NewMode(0100644), // regular file
	}

	t.Run("with base tree and single entry", func(t *testing.T) {
		req := NewCreateTreeRequest(reqCtxWithTransaction, repository, baseTreeOid, treeEntry1)
		require.Equal(t, req, &CreateTreeRequest{
			RequestContext: reqCtxWithTransaction,
			Repository:     repository,
			BaseTree:       baseTreeOid,
			Entries:        []*CreateTreeRequest_TreeEntry{treeEntry1},
		})
	})

	t.Run("with base tree and multiple entries", func(t *testing.T) {
		req := NewCreateTreeRequest(reqCtxWithTransaction, repository, baseTreeOid, treeEntry1, treeEntry2)
		require.Equal(t, req, &CreateTreeRequest{
			RequestContext: reqCtxWithTransaction,
			Repository:     repository,
			BaseTree:       baseTreeOid,
			Entries:        []*CreateTreeRequest_TreeEntry{treeEntry1, treeEntry2},
		})
	})

	t.Run("without base tree", func(t *testing.T) {
		req := NewCreateTreeRequest(reqCtxWithTransaction, repository, nil, treeEntry1)
		require.Equal(t, req, &CreateTreeRequest{
			RequestContext: reqCtxWithTransaction,
			Repository:     repository,
			BaseTree:       nil,
			Entries:        []*CreateTreeRequest_TreeEntry{treeEntry1},
		})
	})
}

func TestCreateTreeRequestValidate(t *testing.T) {
	// CreateTree specific test variables
	reqCtxWithTransaction := types.NewRequestContext(
		types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
		types.WithTransactionState([]byte("transaction")),
	)
	baseTreeOid := types.NewObjectID("abcdef1234567890abcdef1234567890abcdef12")
	treeEntry1 := &CreateTreeRequest_TreeEntry{
		Path: types.NewPath([]byte("file1.txt")),
		Oid:  types.NewObjectID("1111111111111111111111111111111111111111"),
		Mode: types.NewMode(0100644), // regular file
	}
	treeEntry2 := &CreateTreeRequest_TreeEntry{
		Path: types.NewPath([]byte("dir/file2.txt")),
		Oid:  types.NewObjectID("2222222222222222222222222222222222222222"),
		Mode: types.NewMode(0100644), // regular file
	}

	t.Run("valid request with base tree", func(t *testing.T) {
		req := NewCreateTreeRequest(reqCtxWithTransaction, repository, baseTreeOid, treeEntry1)
		require.NoError(t, req.Validate())
	})

	t.Run("valid request without base tree", func(t *testing.T) {
		req := NewCreateTreeRequest(reqCtxWithTransaction, repository, nil, treeEntry1)
		require.NoError(t, req.Validate())
	})

	t.Run("valid request with multiple entries", func(t *testing.T) {
		req := NewCreateTreeRequest(reqCtxWithTransaction, repository, baseTreeOid, treeEntry1, treeEntry2)
		require.NoError(t, req.Validate())
	})

	t.Run("valid request with no entries", func(t *testing.T) {
		req := NewCreateTreeRequest(reqCtxWithTransaction, repository, baseTreeOid)
		require.NoError(t, req.Validate())
	})
}

func TestCreateTreeRequestValidateErrors(t *testing.T) {
	// CreateTree specific test variables
	reqCtxWithTransaction := types.NewRequestContext(
		types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
		types.WithTransactionState([]byte("transaction")),
	)
	baseTreeOid := types.NewObjectID("abcdef1234567890abcdef1234567890abcdef12")
	treeEntry1 := &CreateTreeRequest_TreeEntry{
		Path: types.NewPath([]byte("file1.txt")),
		Oid:  types.NewObjectID("1111111111111111111111111111111111111111"),
		Mode: types.NewMode(0100644), // regular file
	}

	var tests = []struct {
		name string
		req  *CreateTreeRequest
		err  string
	}{
		{
			"empty",
			&CreateTreeRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewCreateTreeRequest(reqCtxWithTransaction, nil, baseTreeOid, treeEntry1),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewCreateTreeRequest(reqCtxWithTransaction, &types.Repository{}, baseTreeOid, treeEntry1),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing request_context",
			&CreateTreeRequest{
				Repository: repository,
				BaseTree:   baseTreeOid,
				Entries:    []*CreateTreeRequest_TreeEntry{treeEntry1},
			},
			"twirp error invalid_argument: request_context is required",
		},
		{
			"missing transaction_state",
			NewCreateTreeRequest(reqCtx, repository, baseTreeOid, treeEntry1),
			"twirp error invalid_argument: request_context.transaction_state is required",
		},
		{
			"invalid base tree",
			NewCreateTreeRequest(reqCtxWithTransaction, repository, types.NewObjectID("invalid"), treeEntry1),
			"twirp error invalid_argument: object_id.id must be a valid object id",
		},
		{
			"nil entry in list",
			&CreateTreeRequest{
				RequestContext: reqCtxWithTransaction,
				Repository:     repository,
				BaseTree:       baseTreeOid,
				Entries:        []*CreateTreeRequest_TreeEntry{nil},
			},
			"twirp error invalid_argument: entries is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestNewCreateTreeRequestEntry(t *testing.T) {
	mode := &types.Mode{Mode: 0o100644} // Regular file mode
	oid := &types.ObjectID{Id: "a1b2c3d4e5f6789012345678901234567890abcd"}
	path := &types.Path{Name: []byte("file.txt")}

	entry := NewCreateTreeRequestEntry(mode, oid, path)

	require.NotNil(t, entry)
	require.Equal(t, mode, entry.Mode)
	require.Equal(t, oid, entry.Oid)
	require.Equal(t, path, entry.Path)
}

func TestCreateTreeEntryValidate(t *testing.T) {
	validMode := &types.Mode{Mode: 0o100644} // Regular file mode
	validOid := &types.ObjectID{Id: "a1b2c3d4e5f6789012345678901234567890abcd"}
	validPath := &types.Path{Name: []byte("file.txt")}

	t.Run("valid tree entry", func(t *testing.T) {
		entry := &CreateTreeRequest_TreeEntry{
			Mode: validMode,
			Oid:  validOid,
			Path: validPath,
		}
		require.NoError(t, entry.Validate())
	})

	t.Run("nil tree entry", func(t *testing.T) {
		var entry *CreateTreeRequest_TreeEntry
		require.NoError(t, entry.Validate())
	})

	t.Run("missing mode", func(t *testing.T) {
		entry := &CreateTreeRequest_TreeEntry{
			Oid:  validOid,
			Path: validPath,
		}
		err := entry.Validate()
		require.Error(t, err)
		require.Equal(t, twirp.RequiredArgumentError("mode"), err)
	})

	t.Run("invalid mode", func(t *testing.T) {
		invalidMode := &types.Mode{} // Empty mode (Mode: 0) should be invalid
		entry := &CreateTreeRequest_TreeEntry{
			Mode: invalidMode,
			Oid:  validOid,
			Path: validPath,
		}
		err := entry.Validate()
		require.Error(t, err)
		require.Equal(t, twirp.RequiredArgumentError("mode.mode"), err)
	})

	t.Run("invalid mode value", func(t *testing.T) {
		invalidMode := &types.Mode{Mode: 0o123456} // Invalid mode value
		entry := &CreateTreeRequest_TreeEntry{
			Mode: invalidMode,
			Oid:  validOid,
			Path: validPath,
		}
		err := entry.Validate()
		require.Error(t, err)
		require.Equal(t, twirp.InvalidArgumentError("mode.mode", "invalid mode"), err)
	})

	t.Run("missing oid", func(t *testing.T) {
		entry := &CreateTreeRequest_TreeEntry{
			Mode: validMode,
			Path: validPath,
		}
		err := entry.Validate()
		require.Error(t, err)
		require.Equal(t, twirp.RequiredArgumentError("oid"), err)
	})

	t.Run("invalid oid", func(t *testing.T) {
		invalidOid := &types.ObjectID{} // Empty oid (Id: "") should be invalid
		entry := &CreateTreeRequest_TreeEntry{
			Mode: validMode,
			Oid:  invalidOid,
			Path: validPath,
		}
		err := entry.Validate()
		require.Error(t, err)
		require.Equal(t, twirp.InvalidArgumentError("object_id.id", "is required"), err)
	})

	t.Run("missing path", func(t *testing.T) {
		entry := &CreateTreeRequest_TreeEntry{
			Mode: validMode,
			Oid:  validOid,
		}
		err := entry.Validate()
		require.Error(t, err)
		require.Equal(t, twirp.RequiredArgumentError("path"), err)
	})

	t.Run("invalid path", func(t *testing.T) {
		invalidPath := &types.Path{} // Empty path (Name: nil) should be invalid
		entry := &CreateTreeRequest_TreeEntry{
			Mode: validMode,
			Oid:  validOid,
			Path: invalidPath,
		}
		err := entry.Validate()
		require.Error(t, err)
		require.Equal(t, twirp.RequiredArgumentError("path.name"), err)
	})
}
