package submodules

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"

	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	reqCtx             = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
	repository         = types.NewRepository(1)
	treeishOIDSelector = selectors.NewTreeishSelector(types.NewTreeishWithObjectID(types.NewObjectID("1234567890123456789012345678901234567890")))
	treeishRefSelector = selectors.NewTreeishSelector(types.NewTreeishWithReference(types.DefaultBranch()))
	paths              = []*types.Path{
		types.NewPath([]byte("path/to/file1")),
		types.NewPath([]byte("path/to/file2")),
	}
)

func TestNewReadSubmodulesRequestByOID(t *testing.T) {
	req := NewReadSubmodulesRequest(reqCtx, repository, treeishOIDSelector, paths...)
	require.Equal(t, req, &ReadSubmodulesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadSubmodulesRequest_TreeishSelector{TreeishSelector: treeishOIDSelector},
		Paths:          paths,
	})
}

func TestNewReadSubmodulesRequestByRef(t *testing.T) {
	req := NewReadSubmodulesRequest(reqCtx, repository, treeishRefSelector, paths...)
	require.Equal(t, req, &ReadSubmodulesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadSubmodulesRequest_TreeishSelector{TreeishSelector: treeishRefSelector},
		Paths:          paths,
	})
}

func TestReadSubmoduleRequestValidateErrors(t *testing.T) {
	tooManyPaths := make([]*types.Path, 1001)
	for i := 0; i < 1001; i++ {
		tooManyPaths[i] = types.NewPath([]byte("path/to/file%d"))
	}

	var tests = []struct {
		name string
		req  *ReadSubmodulesRequest
		err  string
	}{
		{
			"empty",
			&ReadSubmodulesRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewReadSubmodulesRequest(reqCtx, nil, treeishOIDSelector, paths...),
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing treeish",
			NewReadSubmodulesRequest(reqCtx, repository, nil, paths...),
			"twirp error invalid_argument: selector.treeish_selector is required",
		},
		{
			"missing paths",
			NewReadSubmodulesRequest(reqCtx, repository, treeishOIDSelector),
			"twirp error invalid_argument: paths is required",
		},
		{
			"empty paths",
			NewReadSubmodulesRequest(reqCtx, repository, treeishOIDSelector, []*types.Path{}...),
			"twirp error invalid_argument: paths is required",
		},
		{
			"invalid path",
			NewReadSubmodulesRequest(reqCtx, repository, treeishOIDSelector, tooManyPaths...),
			"twirp error invalid_argument: paths may contain up to 1000 items",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.req.Validate()
			require.EqualError(t, err, tt.err)
		})
	}
}
