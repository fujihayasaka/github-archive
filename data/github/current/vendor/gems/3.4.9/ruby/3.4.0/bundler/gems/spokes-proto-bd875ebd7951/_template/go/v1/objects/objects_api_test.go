package objects

import (
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	repository = types.NewRepository(1)
	rev        = types.NewRevision([]byte("main@{2.days.ago}"))
	oid        = "1234567890123456789012345678901234567890"
	treeOid    = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	shortOid   = selectors.NewObjectSelectorByObjectIDAndType(
		types.NewObjectID(oid),
		types.NewObjectTypeFromTypeString("commit"),
	)
	invalidOid = selectors.NewObjectSelectorByObjectIDAndType(
		types.NewObjectID("1234567"),
		types.NewObjectTypeFromTypeString("notvalid"),
	)

	sel1 = selectors.NewObjectSelectorByTreeishAndPath(
		types.NewTreeishWithObjectID(types.NewObjectID(oid)),
		types.NewPath([]byte("a/b/c")),
		nil,
	)

	sel2 = selectors.NewObjectSelectorByTreeishAndPath(
		types.NewTreeishWithReference(types.DefaultBranch()),
		types.NewPath([]byte("d/e/f")),
		&selectors.ObjectSelector_TreeishAndPath_SymlinkResolution{MaxDepth: 2},
	)

	sel3 = selectors.NewObjectSelectorByObjectID(
		types.NewObjectID(oid),
	)

	reqCtx = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestNewResolveObjectRequest(t *testing.T) {
	req := NewResolveObjectRequest(reqCtx, repository, rev)
	require.Equal(t, req, &ResolveObjectRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		ObjectName:     rev,
	})
}

func TestResolveObjectRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ResolveObjectRequest
		err  string
	}{
		{
			"empty",
			&ResolveObjectRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewResolveObjectRequest(reqCtx, nil, rev),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewResolveObjectRequest(reqCtx, &types.Repository{}, rev),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing object name",
			NewResolveObjectRequest(reqCtx, repository, nil),
			"twirp error invalid_argument: object_name is required",
		},
		{
			"invalid objet name",
			NewResolveObjectRequest(reqCtx, repository, types.NewRevision(nil)),
			"twirp error invalid_argument: revision.name is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestResolveObjectRequestValidate(t *testing.T) {
	req := NewResolveObjectRequest(reqCtx, repository, rev)
	require.NoError(t, req.Validate())
}

func TestNewResolveObjectsRequest(t *testing.T) {
	req := NewResolveObjectsRequest(reqCtx, repository, sel1, sel2)
	require.Equal(t, req, &ResolveObjectsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selectors:      []*selectors.ObjectSelector{sel1, sel2},
	})
}

func TestResolveObjectsRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ResolveObjectsRequest
		err  string
	}{
		{
			"empty",
			&ResolveObjectsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewResolveObjectsRequest(reqCtx, nil, sel1),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewResolveObjectsRequest(reqCtx, &types.Repository{}, sel1),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"no selectors",
			NewResolveObjectsRequest(reqCtx, repository),
			"twirp error invalid_argument: selectors is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestResolveObjectsRequestValidate(t *testing.T) {
	req := NewResolveObjectsRequest(reqCtx, repository, sel1, sel2)
	require.NoError(t, req.Validate())
}

func TestResolveObjectsRequestSplit(t *testing.T) {
	var tests = []struct {
		name     string
		req      *ResolveObjectsRequest
		expected []*ResolveObjectsRequest
	}{
		{
			"nil",
			nil,
			[]*ResolveObjectsRequest{},
		},
		{
			"empty",
			NewResolveObjectsRequest(reqCtx, repository),
			[]*ResolveObjectsRequest{},
		},
		{
			"one object",
			NewResolveObjectsRequest(reqCtx, repository, sel1),
			[]*ResolveObjectsRequest{
				NewResolveObjectsRequest(reqCtx, repository, sel1),
			},
		},
		{
			"multiple objects",
			NewResolveObjectsRequest(reqCtx, repository, sel1, sel2),
			[]*ResolveObjectsRequest{
				NewResolveObjectsRequest(reqCtx, repository, sel1),
				NewResolveObjectsRequest(reqCtx, repository, sel2),
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
					// Compare by string to get a useful diff
					require.Equal(t, prototext.Format(tt.expected[i]), prototext.Format(splitReq[i]))
					require.True(t, proto.Equal(tt.expected[i], splitReq[i]), "formatted protobufs are equal, but objects are not")
				}
			}
		})
	}
}

func TestResolveObjectsRequestJoin(t *testing.T) {
	var tests = []struct {
		name      string
		req       *ResolveObjectsRequest
		otherReqs []*ResolveObjectsRequest
		expected  *ResolveObjectsRequest
	}{
		{
			"nil",
			nil,
			[]*ResolveObjectsRequest{},
			nil,
		},
		{
			"empty",
			NewResolveObjectsRequest(reqCtx, repository),
			[]*ResolveObjectsRequest{},
			NewResolveObjectsRequest(reqCtx, repository),
		},
		{
			"empty with another req",
			NewResolveObjectsRequest(reqCtx, repository),
			[]*ResolveObjectsRequest{
				NewResolveObjectsRequest(reqCtx, repository, sel1),
			},
			NewResolveObjectsRequest(reqCtx, repository, sel1),
		},
		{
			"non-empty base req + one other",
			NewResolveObjectsRequest(reqCtx, repository, sel1),
			[]*ResolveObjectsRequest{
				NewResolveObjectsRequest(reqCtx, repository, sel2),
			},
			NewResolveObjectsRequest(reqCtx, repository, sel1, sel2),
		},
		{
			"req with multiple items",
			NewResolveObjectsRequest(reqCtx, repository, sel1),
			[]*ResolveObjectsRequest{
				NewResolveObjectsRequest(reqCtx, repository, sel2, sel3),
			},
			NewResolveObjectsRequest(reqCtx, repository, sel1, sel2, sel3),
		},
		{
			"base req + multiple others",
			NewResolveObjectsRequest(reqCtx, repository),
			[]*ResolveObjectsRequest{
				NewResolveObjectsRequest(reqCtx, repository, sel1, sel3),
				NewResolveObjectsRequest(reqCtx, repository, sel2),
			},
			NewResolveObjectsRequest(reqCtx, repository, sel1, sel3, sel2),
		},
		{
			"nil other req",
			NewResolveObjectsRequest(reqCtx, repository, sel1),
			[]*ResolveObjectsRequest{
				nil,
				NewResolveObjectsRequest(reqCtx, repository, sel3),
			},
			NewResolveObjectsRequest(reqCtx, repository, sel1, sel3),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			joinedReq := tt.req.Join(tt.otherReqs...)
			if tt.expected == nil {
				require.Nil(t, joinedReq)
			} else {
				require.NotNil(t, joinedReq)
				require.Equal(t, prototext.Format(tt.expected), prototext.Format(joinedReq)) // Compare by string to get a useful diff
				require.True(t, proto.Equal(tt.expected, joinedReq), "formatted protobufs are equal, but objects are not")
			}
		})
	}
}

func TestResolveObjectsResponseSplit(t *testing.T) {
	obj := &ResolveObjectsResponse_ResolvedItem{
		Item: &ResolveObjectsResponse_ResolvedItem_Object{
			Object: &types.Object{
				Type: types.Object_TYPE_COMMIT,
				Oid:  types.NewObjectID(oid),
			},
		},
	}
	errObj := &ResolveObjectsResponse_ResolvedItem{
		Item: &ResolveObjectsResponse_ResolvedItem_Error{
			Error: "missing",
		},
	}

	var tests = []struct {
		name     string
		resp     *ResolveObjectsResponse
		expected []*ResolveObjectsResponse
	}{
		{
			"nil",
			nil,
			[]*ResolveObjectsResponse{},
		},
		{
			"empty",
			NewResolveObjectsResponse(),
			[]*ResolveObjectsResponse{},
		},
		{
			"one object",
			NewResolveObjectsResponse(obj),
			[]*ResolveObjectsResponse{
				NewResolveObjectsResponse(obj),
			},
		},
		{
			"multiple objects",
			NewResolveObjectsResponse(obj, errObj),
			[]*ResolveObjectsResponse{
				NewResolveObjectsResponse(obj),
				NewResolveObjectsResponse(errObj),
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
					// Compare by string to get a useful diff
					require.Equal(t, prototext.Format(tt.expected[i]), prototext.Format(splitResp[i]))
					require.True(t, proto.Equal(tt.expected[i], splitResp[i]), "formatted protobufs are equal, but objects are not")
				}
			}
		})
	}
}

func TestResolveObjectsResponseJoin(t *testing.T) {
	obj1 := &ResolveObjectsResponse_ResolvedItem{
		Item: &ResolveObjectsResponse_ResolvedItem_Object{
			Object: &types.Object{
				Type: types.Object_TYPE_COMMIT,
				Oid:  types.NewObjectID(oid),
			},
		},
	}
	obj2 := &ResolveObjectsResponse_ResolvedItem{
		Item: &ResolveObjectsResponse_ResolvedItem_Object{
			Object: &types.Object{
				Type: types.Object_TYPE_TREE,
				Oid:  types.NewObjectID(treeOid),
			},
		},
	}
	errObj := &ResolveObjectsResponse_ResolvedItem{
		Item: &ResolveObjectsResponse_ResolvedItem_Error{
			Error: "missing",
		},
	}

	var tests = []struct {
		name       string
		resp       *ResolveObjectsResponse
		otherResps []*ResolveObjectsResponse
		expected   *ResolveObjectsResponse
	}{
		{
			"nil",
			nil,
			[]*ResolveObjectsResponse{},
			nil,
		},
		{
			"empty",
			NewResolveObjectsResponse(),
			[]*ResolveObjectsResponse{},
			NewResolveObjectsResponse(),
		},
		{
			"empty with another resp",
			NewResolveObjectsResponse(),
			[]*ResolveObjectsResponse{
				NewResolveObjectsResponse(obj1),
			},
			NewResolveObjectsResponse(obj1),
		},
		{
			"non-empty base resp + one other",
			NewResolveObjectsResponse(obj1),
			[]*ResolveObjectsResponse{
				NewResolveObjectsResponse(obj2),
			},
			NewResolveObjectsResponse(obj1, obj2),
		},
		{
			"resp with multiple items",
			NewResolveObjectsResponse(obj1),
			[]*ResolveObjectsResponse{
				NewResolveObjectsResponse(obj2, errObj),
			},
			NewResolveObjectsResponse(obj1, obj2, errObj),
		},
		{
			"base resp + multiple others",
			NewResolveObjectsResponse(),
			[]*ResolveObjectsResponse{
				NewResolveObjectsResponse(obj1, errObj),
				NewResolveObjectsResponse(obj2),
			},
			NewResolveObjectsResponse(obj1, errObj, obj2),
		},
		{
			"nil other resp",
			NewResolveObjectsResponse(obj1),
			[]*ResolveObjectsResponse{
				nil,
				NewResolveObjectsResponse(errObj),
			},
			NewResolveObjectsResponse(obj1, errObj),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			joinedResp := tt.resp.Join(tt.otherResps...)
			if tt.expected == nil {
				require.Nil(t, joinedResp)
			} else {
				require.NotNil(t, joinedResp)
				require.Equal(t, prototext.Format(tt.expected), prototext.Format(joinedResp)) // Compare by string to get a useful diff
				require.True(t, proto.Equal(tt.expected, joinedResp), "formatted protobufs are equal, but objects are not")
			}
		})
	}
}

func buildReadObjectsRequestInput(oids []string, _types []string) []*selectors.ObjectSelector {
	var input []*selectors.ObjectSelector
	for i, oid := range oids {
		ot := selectors.NewObjectSelectorByObjectIDAndType(
			types.NewObjectID(oid),
			types.NewObjectTypeFromTypeString(_types[i]),
		)
		input = append(input, ot)
	}
	return input
}

func TestNewReadObjectsRequest(t *testing.T) {
	req := NewReadObjectsRequest(reqCtx, repository, buildReadObjectsRequestInput([]string{oid}, []string{"commit"})...)
	require.Equal(t, req, &ReadObjectsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selectors:      buildReadObjectsRequestInput([]string{oid}, []string{"commit"}),
	})
}

func TestReadObjectsRequest(t *testing.T) {
	req := NewReadObjectsRequest(reqCtx, repository, buildReadObjectsRequestInput([]string{oid}, []string{"commit"})...)
	require.NoError(t, req.Validate())
}

func TestReadObjectsRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ReadObjectsRequest
		err  string
	}{
		{
			"empty",
			&ReadObjectsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewReadObjectsRequest(reqCtx, nil, buildReadObjectsRequestInput([]string{oid}, []string{"commit"})...),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewReadObjectsRequest(reqCtx, &types.Repository{}, buildReadObjectsRequestInput([]string{oid}, []string{"commit"})...),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing object oid",
			NewReadObjectsRequest(reqCtx, repository, buildReadObjectsRequestInput([]string{""}, []string{"commit"})...),
			"twirp error invalid_argument: object_id.id is required",
		},
		{
			"nil selector",
			NewReadObjectsRequest(reqCtx, repository, nil),
			"twirp error invalid_argument: selector is required",
		},
		{
			"invalid object type",
			NewReadObjectsRequest(reqCtx, repository, buildReadObjectsRequestInput([]string{oid}, []string{"notvalid"})...),
			"twirp error invalid_argument: type must be commit, tree, blob or tag",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestNewExpandOidsRequest(t *testing.T) {
	req := NewExpandOidsRequest(reqCtx, repository, []*selectors.ObjectSelector{shortOid})
	require.Equal(t, req, &ExpandOidsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selectors:      []*selectors.ObjectSelector{shortOid},
	})
}

func TestExpandOidsRequest(t *testing.T) {
	req := NewExpandOidsRequest(reqCtx, repository, []*selectors.ObjectSelector{shortOid})
	require.NoError(t, req.Validate())
}

func TestExpandOidsRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ExpandOidsRequest
		err  string
	}{
		{
			"empty",
			&ExpandOidsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewExpandOidsRequest(reqCtx, nil, []*selectors.ObjectSelector{shortOid}),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewExpandOidsRequest(reqCtx, &types.Repository{}, []*selectors.ObjectSelector{shortOid}),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing object oid",
			NewExpandOidsRequest(reqCtx, repository, nil),
			"twirp error invalid_argument: selectors is required",
		},
		{
			"too many oids",
			NewExpandOidsRequest(reqCtx, repository, make([]*selectors.ObjectSelector, 2000)),
			"twirp error invalid_argument: selectors may contain up to 1000 items",
		},
		{
			"invalid object type",
			NewExpandOidsRequest(reqCtx, repository, []*selectors.ObjectSelector{invalidOid}),
			"twirp error invalid_argument: type must be commit, tree, blob or tag",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}
