package references

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	repository = types.NewRepository(1)

	invalidPrefixSelector = selectors.NewPrefixSelector()

	reqCtx = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)

	mainRef = types.NewReference([]byte("refs/heads/main"))
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
			"twirp error invalid_argument: prefixes is required",
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
			"twirp error invalid_argument: globs is required",
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
