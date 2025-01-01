package objects

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	repository = types.NewRepository(1)
	rev        = types.NewRevision([]byte("main@{2.days.ago}"))
	oid        = types.NewObjectID("1234567890123456789012345678901234567890")
	shortOid   = &ExpandOidsRequest_RevisionAndType{
		Revision:   types.NewRevision([]byte("1234567")),
		ObjectType: types.NewObjectTypeFromTypeString("commit"),
	}
	invalidOid = &ExpandOidsRequest_RevisionAndType{
		Revision:   types.NewRevision([]byte("1234567")),
		ObjectType: types.NewObjectTypeFromTypeString("notvalid"),
	}

	sel1 = selectors.NewObjectSelectorByTreeishAndPath(
		types.NewTreeishWithObjectID(oid),
		types.NewPath([]byte("a/b/c")),
	)

	sel2 = selectors.NewObjectSelectorByTreeishAndPath(
		types.NewTreeishWithReference(types.DefaultBranch()),
		types.NewPath([]byte("d/e/f")),
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

func TestNewExpandOidsRequest(t *testing.T) {
	req := NewExpandOidsRequest(reqCtx, repository, []*ExpandOidsRequest_RevisionAndType{shortOid})
	require.Equal(t, req, &ExpandOidsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Oids:           []*ExpandOidsRequest_RevisionAndType{shortOid},
	})
}

func TestExpandOidsRequest(t *testing.T) {
	req := NewExpandOidsRequest(reqCtx, repository, []*ExpandOidsRequest_RevisionAndType{shortOid})
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
			NewExpandOidsRequest(reqCtx, nil, []*ExpandOidsRequest_RevisionAndType{shortOid}),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewExpandOidsRequest(reqCtx, &types.Repository{}, []*ExpandOidsRequest_RevisionAndType{shortOid}),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing object oid",
			NewExpandOidsRequest(reqCtx, repository, nil),
			"twirp error invalid_argument: oids is required",
		},
		{
			"too many oids",
			NewExpandOidsRequest(reqCtx, repository, make([]*ExpandOidsRequest_RevisionAndType, 2000)),
			"twirp error invalid_argument: oids may contain up to 1000 items",
		},
		{
			"invalid object type",
			NewExpandOidsRequest(reqCtx, repository, []*ExpandOidsRequest_RevisionAndType{invalidOid}),
			"twirp error invalid_argument: type must be commit, tree, blob or tag",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}
