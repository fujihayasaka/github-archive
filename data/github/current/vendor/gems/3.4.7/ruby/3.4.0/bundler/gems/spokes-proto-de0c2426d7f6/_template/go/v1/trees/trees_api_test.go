package trees

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	repository = types.NewRepository(1)

	oid                    = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	treeish                = types.NewTreeishWithObjectID(oid)
	treeishSelector        = selectors.NewTreeishSelector(treeish)
	treeishAndPathSelector = selectors.NewTreeishAndPathSelector(treeish, types.NewPath([]byte("path")))

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
	req := NewListTreesRequestWithTreeishSelector(reqCtx, repository, treeishSelector, true, nil)
	require.Equal(t, req, &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishSelector{TreeishSelector: treeishSelector},
		Recursive:      true,
	})

	req = NewListTreesRequestWithTreeishAndPathSelector(reqCtx, repository, treeishAndPathSelector, true, nil)
	require.Equal(t, req, &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishAndPathSelector{TreeishAndPathSelector: treeishAndPathSelector},
		Recursive:      true,
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
			NewListTreesRequestWithTreeishSelector(reqCtx, nil, treeishSelector, false, nil),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewListTreesRequestWithTreeishSelector(reqCtx, &types.Repository{}, treeishSelector, false, nil),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing selector",
			&ListTreesRequest{RequestContext: reqCtx, Repository: repository, Selector: nil, Recursive: false},
			"twirp error invalid_argument: selector is required",
		},
		{
			"invalid treeish selector",
			NewListTreesRequestWithTreeishSelector(reqCtx, repository, selectors.NewTreeishSelector(nil), false, nil),
			"twirp error invalid_argument: treeish is required",
		},
		{
			"invalid treeish_and_path selector",
			NewListTreesRequestWithTreeishAndPathSelector(reqCtx, repository, selectors.NewTreeishAndPathSelector(treeish, nil), false, nil),
			"twirp error invalid_argument: path is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestListTreesRequestValidate(t *testing.T) {
	req := NewListTreesRequestWithTreeishSelector(reqCtx, repository, treeishSelector, true, nil)
	require.NoError(t, req.Validate())

	req = NewListTreesRequestWithTreeishAndPathSelector(reqCtx, repository, treeishAndPathSelector, true, nil)
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
