package references

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	repository = types.NewRepository(1)

	invalidPrefixSelector = selectors.NewPrefixSelector()

	reqCtx = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)

	mainRef = types.NewReference([]byte("refs/heads/main"))
	devRef  = types.NewReference([]byte("refs/heads/dev"))
	testRef = types.NewReference([]byte("refs/heads/test"))
	oid     = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
)

func TestResolveReferencesRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ResolveReferencesRequest
		err  string
	}{
		{
			"empty",
			&ResolveReferencesRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewResolveReferencesRequest(reqCtx, nil, mainRef),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewResolveReferencesRequest(reqCtx, &types.Repository{}, mainRef),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing references",
			&ResolveReferencesRequest{RequestContext: reqCtx, Repository: repository},
			"twirp error invalid_argument: references is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestResolveReferencesRequestReferenceLimit(t *testing.T) {
	refs := make([]*types.Reference, 10001)
	for i := range refs {
		refs[i] = types.NewReference([]byte(fmt.Sprint("refs/heads/branch", i)))
	}

	req := &ResolveReferencesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		References:     refs,
	}

	expectedErr := "twirp error invalid_argument: references may contain up to 10000 items"

	require.EqualError(t, req.Validate(), expectedErr)
}

func TestResolveReferencesRequestSplit(t *testing.T) {
	var tests = []struct {
		name     string
		req      *ResolveReferencesRequest
		expected []*ResolveReferencesRequest
	}{
		{
			"nil",
			nil,
			[]*ResolveReferencesRequest{},
		},
		{
			"empty",
			NewResolveReferencesRequest(reqCtx, repository),
			[]*ResolveReferencesRequest{},
		},
		{
			"one ref",
			NewResolveReferencesRequest(reqCtx, repository, mainRef),
			[]*ResolveReferencesRequest{
				NewResolveReferencesRequest(reqCtx, repository, mainRef),
			},
		},
		{
			"multiple refs",
			NewResolveReferencesRequest(reqCtx, repository, mainRef, devRef),
			[]*ResolveReferencesRequest{
				NewResolveReferencesRequest(reqCtx, repository, mainRef),
				NewResolveReferencesRequest(reqCtx, repository, devRef),
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

func TestResolveReferencesRequestJoin(t *testing.T) {
	var tests = []struct {
		name      string
		req       *ResolveReferencesRequest
		otherReqs []*ResolveReferencesRequest
		expected  *ResolveReferencesRequest
	}{
		{
			"nil",
			nil,
			[]*ResolveReferencesRequest{},
			nil,
		},
		{
			"empty",
			NewResolveReferencesRequest(reqCtx, repository),
			[]*ResolveReferencesRequest{},
			NewResolveReferencesRequest(reqCtx, repository),
		},
		{
			"empty with another req",
			NewResolveReferencesRequest(reqCtx, repository),
			[]*ResolveReferencesRequest{
				NewResolveReferencesRequest(reqCtx, repository, mainRef),
			},
			NewResolveReferencesRequest(reqCtx, repository, mainRef),
		},
		{
			"non-empty base req + one other",
			NewResolveReferencesRequest(reqCtx, repository, mainRef),
			[]*ResolveReferencesRequest{
				NewResolveReferencesRequest(reqCtx, repository, devRef),
			},
			NewResolveReferencesRequest(reqCtx, repository, mainRef, devRef),
		},
		{
			"req with multiple items",
			NewResolveReferencesRequest(reqCtx, repository, mainRef),
			[]*ResolveReferencesRequest{
				NewResolveReferencesRequest(reqCtx, repository, devRef, testRef),
			},
			NewResolveReferencesRequest(reqCtx, repository, mainRef, devRef, testRef),
		},
		{
			"base req + multiple others",
			NewResolveReferencesRequest(reqCtx, repository),
			[]*ResolveReferencesRequest{
				NewResolveReferencesRequest(reqCtx, repository, mainRef, testRef),
				NewResolveReferencesRequest(reqCtx, repository, devRef),
			},
			NewResolveReferencesRequest(reqCtx, repository, mainRef, testRef, devRef),
		},
		{
			"nil other req",
			NewResolveReferencesRequest(reqCtx, repository, mainRef),
			[]*ResolveReferencesRequest{
				nil,
				NewResolveReferencesRequest(reqCtx, repository, testRef),
			},
			NewResolveReferencesRequest(reqCtx, repository, mainRef, testRef),
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

func TestResolveReferencesResponseSplit(t *testing.T) {
	mainRefItem := &ResolveReferencesResponse_ResolvedReference{
		Reference: mainRef,
		Oid:       oid,
	}
	devRefItem := &ResolveReferencesResponse_ResolvedReference{
		Reference: devRef,
		Error:     "missing",
	}

	var tests = []struct {
		name     string
		req      *ResolveReferencesResponse
		expected []*ResolveReferencesResponse
	}{
		{
			"nil",
			nil,
			[]*ResolveReferencesResponse{},
		},
		{
			"empty",
			NewResolveReferencesResponse(),
			[]*ResolveReferencesResponse{},
		},
		{
			"one ref",
			NewResolveReferencesResponse(mainRefItem),
			[]*ResolveReferencesResponse{
				NewResolveReferencesResponse(mainRefItem),
			},
		},
		{
			"multiple refs",
			NewResolveReferencesResponse(mainRefItem, devRefItem),
			[]*ResolveReferencesResponse{
				NewResolveReferencesResponse(mainRefItem),
				NewResolveReferencesResponse(devRefItem),
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

func TestResolveReferencesResponseJoin(t *testing.T) {
	mainRefItem := &ResolveReferencesResponse_ResolvedReference{
		Reference: mainRef,
		Oid:       oid,
	}
	devRefItem := &ResolveReferencesResponse_ResolvedReference{
		Reference: devRef,
		Error:     "missing",
	}
	testRefItem := &ResolveReferencesResponse_ResolvedReference{
		Reference: testRef,
		Oid:       oid,
	}

	var tests = []struct {
		name      string
		req       *ResolveReferencesResponse
		otherReqs []*ResolveReferencesResponse
		expected  *ResolveReferencesResponse
	}{
		{
			"nil",
			nil,
			[]*ResolveReferencesResponse{},
			nil,
		},
		{
			"empty",
			NewResolveReferencesResponse(),
			[]*ResolveReferencesResponse{},
			NewResolveReferencesResponse(),
		},
		{
			"empty with another resp",
			NewResolveReferencesResponse(),
			[]*ResolveReferencesResponse{
				NewResolveReferencesResponse(mainRefItem),
			},
			NewResolveReferencesResponse(mainRefItem),
		},
		{
			"non-empty base resp + one other",
			NewResolveReferencesResponse(mainRefItem),
			[]*ResolveReferencesResponse{
				NewResolveReferencesResponse(devRefItem),
			},
			NewResolveReferencesResponse(mainRefItem, devRefItem),
		},
		{
			"resp with multiple items",
			NewResolveReferencesResponse(mainRefItem),
			[]*ResolveReferencesResponse{
				NewResolveReferencesResponse(devRefItem, testRefItem),
			},
			NewResolveReferencesResponse(mainRefItem, devRefItem, testRefItem),
		},
		{
			"base resp + multiple others",
			NewResolveReferencesResponse(),
			[]*ResolveReferencesResponse{
				NewResolveReferencesResponse(mainRefItem, testRefItem),
				NewResolveReferencesResponse(devRefItem),
			},
			NewResolveReferencesResponse(mainRefItem, testRefItem, devRefItem),
		},
		{
			"nil other resp",
			NewResolveReferencesResponse(mainRefItem),
			[]*ResolveReferencesResponse{
				nil,
				NewResolveReferencesResponse(testRefItem),
			},
			NewResolveReferencesResponse(mainRefItem, testRefItem),
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

func TestNewListReferencesRequest(t *testing.T) {
	req := NewListReferencesRequestWithUniversalSelector(reqCtx, repository, nil)
	require.Equal(t, req.Repository, repository)
}

func TestListReferencesRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ListReferencesRequest
		err  string
	}{
		{
			"empty",
			&ListReferencesRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewListReferencesRequestWithUniversalSelector(reqCtx, nil, nil),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewListReferencesRequestWithUniversalSelector(reqCtx, &types.Repository{}, nil),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing selector",
			&ListReferencesRequest{RequestContext: reqCtx, Repository: repository, Selector: nil},
			"twirp error invalid_argument: selector is required",
		},
		{
			"empty prefix selector",
			&ListReferencesRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReferencesRequest_PrefixSelector{}},
			"twirp error invalid_argument: selector.prefix_selector is required",
		},
		{
			"invalid prefix selector",
			NewListReferencesRequestWithPrefixSelector(reqCtx, repository, invalidPrefixSelector, nil),
			"twirp error invalid_argument: include and/or exclude prefixes are required",
		},
		{
			"invalid points_at",
			&ListReferencesRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				Selector: &ListReferencesRequest_UniversalSelector{
					UniversalSelector: selectors.NewUniversalSelector(),
				},
				RefListOptions: &RefListOptions{PointsAt: []*types.ObjectID{&types.ObjectID{}}},
			},
			"twirp error invalid_argument: ref_list_options invalid RefListOptions: twirp error invalid_argument: points_at invalid ObjectID: twirp error invalid_argument: object_id.id is required",
		},
		{
			"invalid contains",
			&ListReferencesRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				Selector: &ListReferencesRequest_UniversalSelector{
					UniversalSelector: selectors.NewUniversalSelector(),
				},
				RefListOptions: &RefListOptions{Contains: []*types.ObjectID{&types.ObjectID{}}},
			},
			"twirp error invalid_argument: ref_list_options invalid RefListOptions: twirp error invalid_argument: contains invalid ObjectID: twirp error invalid_argument: object_id.id is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestListReferencesWithDetailsRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ListReferencesWithDetailsRequest
		err  string
	}{
		{
			"empty",
			&ListReferencesWithDetailsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			&ListReferencesWithDetailsRequest{RequestContext: reqCtx, Repository: &types.Repository{}},
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing selector",
			&ListReferencesWithDetailsRequest{RequestContext: reqCtx, Repository: repository, Selector: nil},
			"twirp error invalid_argument: selector is required",
		},
		{
			"empty ref_glob selector",
			&ListReferencesWithDetailsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReferencesWithDetailsRequest_RefGlobSelector{}},
			"twirp error invalid_argument: selector.ref_glob_selector is required",
		},
		{
			"invalid ref_glob selector",
			&ListReferencesWithDetailsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReferencesWithDetailsRequest_RefGlobSelector{RefGlobSelector: selectors.NewRefGlobSelector()}},
			"twirp error invalid_argument: include and/or exclude globs are required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestUpdateDefaultBranch(t *testing.T) {
	var tests = []struct {
		name string
		req  *UpdateDefaultBranchRequest
		err  string
	}{
		{
			"empty",
			&UpdateDefaultBranchRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			&UpdateDefaultBranchRequest{Repository: &types.Repository{}},
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"no new_value",
			&UpdateDefaultBranchRequest{Repository: repository},
			"twirp error invalid_argument: new_value is required",
		},
		{
			"invalid new_value",
			&UpdateDefaultBranchRequest{Repository: repository, NewValue: &types.Reference{Name: []byte("bad")}},
			"twirp error invalid_argument: reference.name must have a 'refs/' prefix or be HEAD",
		},
		{
			"invalid new_value, cannot be HEAD",
			&UpdateDefaultBranchRequest{Repository: repository, NewValue: &types.Reference{
				Name: []byte("HEAD"),
			}},
			"twirp error invalid_argument: new_value cannot be HEAD",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestReferencesExist(t *testing.T) {
	var tests = []struct {
		name string
		req  *ReferencesExistRequest
		err  string
	}{
		{
			"empty",
			&ReferencesExistRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			&ReferencesExistRequest{Repository: &types.Repository{}},
			"twirp error invalid_argument: repository.id is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}
