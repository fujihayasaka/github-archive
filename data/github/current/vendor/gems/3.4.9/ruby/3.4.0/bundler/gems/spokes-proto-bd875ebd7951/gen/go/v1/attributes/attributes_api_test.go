package attributes

import (
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	// Request data
	repository      = types.NewRepository(1)
	oid             = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	treeish         = types.NewTreeishWithObjectID(oid)
	treeishSelector = selectors.NewTreeishSelector(treeish)
	keySelector     = selectors.NewKeySelector([][]byte{[]byte("text"), []byte("diff")})
	pathA           = types.NewPath([]byte("a"))
	pathB           = types.NewPath([]byte("b"))
	pathC           = types.NewPath([]byte("c"))
	paths           = []*types.Path{pathA, pathB, pathC}
	reqCtx          = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)

	// Response data
	itemA = &AttributeItem{
		Path: pathA,
		Attributes: []*types.Attribute{
			{
				Key:   []byte("text"),
				Value: &types.Attribute_BoolValue{BoolValue: true},
			},
		},
	}
	itemB = &AttributeItem{
		Path: pathB,
		Attributes: []*types.Attribute{
			{
				Key:   []byte("text"),
				Value: &types.Attribute_BoolValue{BoolValue: false},
			},
		},
	}
	itemC = &AttributeItem{
		Path: pathC,
		Attributes: []*types.Attribute{
			{
				Key:   []byte("text"),
				Value: &types.Attribute_BoolValue{BoolValue: true},
			},
		},
	}
)

func TestNewReadAttributesRequest(t *testing.T) {
	req := NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, paths)
	require.Equal(t, req, &ReadAttributesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector},
		Paths:          paths,
		KeysSelector:   &ReadAttributesRequest_UniversalSelector{UniversalSelector: selectors.NewUniversalSelector()},
	})

	req = NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, paths, keySelector)
	require.Equal(t, req, &ReadAttributesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector},
		Paths:          paths,
		KeysSelector:   &ReadAttributesRequest_KeySelector{KeySelector: keySelector},
	})
}

func TestReadAttributesRequestValidate(t *testing.T) {
	tests := []struct {
		name string
		req  *ReadAttributesRequest
	}{
		{
			"universal selector",
			NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, paths),
		},
		{
			"key selector",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, paths, keySelector),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.req.Validate())
		})
	}
}

func TestReadAttributesRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *ReadAttributesRequest
		err  string
	}{
		{
			"empty",
			&ReadAttributesRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&ReadAttributesRequest{RequestContext: reqCtx},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: &types.Repository{Type: types.Repository_TYPE_REPOSITORY, Id: 0}},
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing selector",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository},
			"twirp error invalid_argument: selector is required",
		},
		{
			"missing selector.treeish_selector",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{}},
			"twirp error invalid_argument: selector.treeish_selector is required",
		},
		{
			"invalid selector.treeish_selector",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: selectors.NewTreeishSelector(types.NewTreeishWithObjectID(nil))}},
			"twirp error invalid_argument: treeish.oid is required",
		},
		{
			"empty paths",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector}},
			"twirp error invalid_argument: paths is required",
		},
		{
			"too many paths",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector}, Paths: make([]*types.Path, 1001)},
			"twirp error invalid_argument: paths may contain up to 1000 items",
		},
		{
			"missing path",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector}, Paths: []*types.Path{types.NewPath([]byte("a")), nil}},
			"twirp error invalid_argument: path is required",
		},
		{
			"missing path name",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector}, Paths: []*types.Path{types.NewPath([]byte("a")), types.NewPath([]byte(""))}},
			"twirp error invalid_argument: path.name is required",
		},
		{
			"missing keys_selector",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector}, Paths: paths},
			"twirp error invalid_argument: keys_selector is required",
		},
		{
			"missing keys_selector.key_selector",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector}, Paths: paths, KeysSelector: &ReadAttributesRequest_KeySelector{}},
			"twirp error invalid_argument: keys_selector.key_selector is required",
		},
		{
			"empty keys_selector.key_selector.keys",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector}, Paths: paths, KeysSelector: &ReadAttributesRequest_KeySelector{KeySelector: selectors.NewKeySelector(make([][]byte, 0))}},
			"twirp error invalid_argument: keys is required",
		},
		{
			"too many keys_selector.key_selector.keys",
			&ReadAttributesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ReadAttributesRequest_TreeishSelector{TreeishSelector: treeishSelector}, Paths: paths, KeysSelector: &ReadAttributesRequest_KeySelector{KeySelector: selectors.NewKeySelector(make([][]byte, 21))}},
			"twirp error invalid_argument: keys may contain up to 20 items",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestReadAttributesRequestSplit(t *testing.T) {
	tests := []struct {
		name     string
		req      *ReadAttributesRequest
		expected []*ReadAttributesRequest
	}{
		{
			"nil",
			nil,
			[]*ReadAttributesRequest{},
		},
		{
			"empty",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{}, keySelector),
			[]*ReadAttributesRequest{},
		},
		{
			"one path",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
			[]*ReadAttributesRequest{
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
			},
		},
		{
			"multiple paths",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, paths, keySelector),
			[]*ReadAttributesRequest{
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathB}, keySelector),
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathC}, keySelector),
			},
		},
		{
			"supports universal selector",
			NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, paths),
			[]*ReadAttributesRequest{
				NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}),
				NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, []*types.Path{pathB}),
				NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, []*types.Path{pathC}),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			splitReq := tt.req.Split()
			if tt.expected == nil {
				require.Nil(t, splitReq)
			} else {
				require.NotNil(t, splitReq)
				require.Equal(t, len(tt.expected), len(splitReq))
				for i := range tt.expected {
					require.Equal(t, prototext.Format(tt.expected[i]), prototext.Format(splitReq[i]))
					require.True(t, proto.Equal(tt.expected[i], splitReq[i]), "formatted protobufs are equal, but objects are not")
				}
			}
		})
	}
}

func TestReadAttributesRequestJoin(t *testing.T) {
	tests := []struct {
		name      string
		req       *ReadAttributesRequest
		otherReqs []*ReadAttributesRequest
		expected  *ReadAttributesRequest
	}{
		{
			"nil",
			nil,
			[]*ReadAttributesRequest{},
			nil,
		},
		{
			"empty",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{}, keySelector),
			[]*ReadAttributesRequest{},
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{}, keySelector),
		},
		{
			"empty with another req",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{}, keySelector),
			[]*ReadAttributesRequest{
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
			},
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
		},
		{
			"non-empty base req + one other",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
			[]*ReadAttributesRequest{
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathB}, keySelector),
			},
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA, pathB}, keySelector),
		},
		{
			"req with multiple items",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
			[]*ReadAttributesRequest{
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathB, pathC}, keySelector),
			},
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, paths, keySelector),
		},
		{
			"base req + multiple others",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
			[]*ReadAttributesRequest{
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathB}, keySelector),
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathC}, keySelector),
			},
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, paths, keySelector),
		},
		{
			"nil other req",
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}, keySelector),
			[]*ReadAttributesRequest{
				nil,
				NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathB}, keySelector),
			},
			NewReadAttributesRequestWithKeySelector(reqCtx, repository, treeishSelector, []*types.Path{pathA, pathB}, keySelector),
		},
		{
			"supports universal selector",
			NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, []*types.Path{pathA}),
			[]*ReadAttributesRequest{
				NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, []*types.Path{pathB}),
				NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, []*types.Path{pathC}),
			},
			NewReadAttributesRequestWithUniversalSelector(reqCtx, repository, treeishSelector, paths),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			joinedReq := tt.req.Join(tt.otherReqs...)
			if tt.expected == nil {
				require.Nil(t, joinedReq)
			} else {
				require.NotNil(t, joinedReq)
				require.Equal(t, prototext.Format(tt.expected), prototext.Format(joinedReq))
				require.True(t, proto.Equal(tt.expected, joinedReq), "formatted protobufs are equal, but objects are not")
			}
		})
	}
}

func TestReadAttributesResponseSplit(t *testing.T) {
	tests := []struct {
		name     string
		resp     *ReadAttributesResponse
		expected []*ReadAttributesResponse
	}{
		{
			"nil",
			nil,
			[]*ReadAttributesResponse{},
		},
		{
			"empty",
			NewReadAttributesResponse(),
			[]*ReadAttributesResponse{},
		},
		{
			"one path",
			NewReadAttributesResponse(itemA),
			[]*ReadAttributesResponse{
				NewReadAttributesResponse(itemA),
			},
		},
		{
			"multiple paths",
			NewReadAttributesResponse(itemA, itemB),
			[]*ReadAttributesResponse{
				NewReadAttributesResponse(itemA),
				NewReadAttributesResponse(itemB),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			splitResp := tt.resp.Split()
			if tt.expected == nil {
				require.Nil(t, splitResp)
			} else {
				require.NotNil(t, splitResp)
				require.Equal(t, len(tt.expected), len(splitResp))
				for i := range tt.expected {
					require.Equal(t, prototext.Format(tt.expected[i]), prototext.Format(splitResp[i]))
					require.True(t, proto.Equal(tt.expected[i], splitResp[i]), "formatted protobufs are equal, but objects are not")
				}
			}
		})
	}
}

func TestReadAttributesResponseJoin(t *testing.T) {
	tests := []struct {
		name       string
		resp       *ReadAttributesResponse
		otherResps []*ReadAttributesResponse
		expected   *ReadAttributesResponse
	}{
		{
			"nil",
			nil,
			[]*ReadAttributesResponse{},
			nil,
		},
		{
			"empty",
			NewReadAttributesResponse(),
			[]*ReadAttributesResponse{},
			NewReadAttributesResponse(),
		},
		{
			"empty with another resp",
			NewReadAttributesResponse(),
			[]*ReadAttributesResponse{
				NewReadAttributesResponse(itemA),
			},
			NewReadAttributesResponse(itemA),
		},
		{
			"non-empty base resp + one other",
			NewReadAttributesResponse(itemA),
			[]*ReadAttributesResponse{
				NewReadAttributesResponse(itemB),
			},
			NewReadAttributesResponse(itemA, itemB),
		},
		{
			"resp with multiple items",
			NewReadAttributesResponse(itemA),
			[]*ReadAttributesResponse{
				NewReadAttributesResponse(itemB, itemC),
			},
			NewReadAttributesResponse(itemA, itemB, itemC),
		},
		{
			"base resp + multiple others",
			NewReadAttributesResponse(),
			[]*ReadAttributesResponse{
				NewReadAttributesResponse(itemA),
				NewReadAttributesResponse(itemB, itemC),
			},
			NewReadAttributesResponse(itemA, itemB, itemC),
		},
		{
			"nil other resp",
			NewReadAttributesResponse(itemA),
			[]*ReadAttributesResponse{
				nil,
				NewReadAttributesResponse(itemB),
			},
			NewReadAttributesResponse(itemA, itemB),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			joinedResp := tt.resp.Join(tt.otherResps...)
			if tt.expected == nil {
				require.Nil(t, joinedResp)
			} else {
				require.NotNil(t, joinedResp)
				require.Equal(t, prototext.Format(tt.expected), prototext.Format(joinedResp))
				require.True(t, proto.Equal(tt.expected, joinedResp), "formatted protobufs are equal, but objects are not")
			}
		})
	}
}
