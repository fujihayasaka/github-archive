package blobs

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/stretchr/testify/require"
)

var (
	ref                           = types.NewReference([]byte("refs/heads/main"))
	oid                           = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	readmePath                    = types.NewPath([]byte("README.md"))
	refUpdate                     = types.NewReferenceUpdate(ref, oid, oid)
	pushSelector                  = selectors.NewPushSelector([]*types.ReferenceUpdate{refUpdate})
	historicalPushSelector        = selectors.NewHistoricalPushSelector([]*types.ReferenceUpdate{refUpdate})
	forkPushSelector              = selectors.NewForkPushSelector(repository, []*types.ReferenceUpdate{refUpdate})
	quarantineObjectsSelector     = selectors.NewQuarantineObjectsSelector()
	objectIDSelector              = selectors.NewObjectIDSelector(oid)
	universalSelector             = selectors.NewUniversalSelector()
	invalidPushSelector           = selectors.NewPushSelector([]*types.ReferenceUpdate{})
	invalidHistoricalPushSelector = selectors.NewHistoricalPushSelector([]*types.ReferenceUpdate{})
	invalidForkPushSelector       = selectors.NewForkPushSelector(nil, []*types.ReferenceUpdate{})
	invalidObjectIDSelector       = selectors.NewObjectIDSelector()
	repository                    = types.NewRepository(1)
	commit                        = types.NewCommitObject(types.NewObjectID("2fbf3466625ed033492d740cce89c9fd3dd2204e"), uint64(10))
	tree                          = types.NewTreeObject(types.NewObjectID("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"), uint64(10))
	reqCtx                        = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
	reqCtxWithPushState           = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE, types.WithPushState([]byte("push state")))
)

func TestGetBlobContentsRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *GetBlobContentsRequest
		err  string
	}{
		{
			"empty",
			&GetBlobContentsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewGetBlobContentsRequestById(reqCtx, nil, oid),
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing blob",
			&GetBlobContentsRequest{RequestContext: reqCtx, Repository: repository},
			"twirp error invalid_argument: blob is required",
		},
		{
			"missing blob id",
			NewGetBlobContentsRequestById(reqCtx, repository, nil),
			"twirp error invalid_argument: blob.id is required",
		},
		{
			"missing blob ref path",
			&GetBlobContentsRequest{
				Repository:     repository,
				Blob:           &GetBlobContentsRequest_ByRefPath{},
				RequestContext: reqCtx,
			},
			"twirp error invalid_argument: blob.ref_path is required",
		},
		{
			"missing blob ref",
			NewGetBlobContentsRequestByRefPath(reqCtx, repository, nil, readmePath),
			"twirp error invalid_argument: blob.ref_path.reference is required",
		},
		{
			"missing blob path",
			NewGetBlobContentsRequestByRefPath(reqCtx, repository, ref, nil),
			"twirp error invalid_argument: blob.ref_path.path is required",
		},
		{
			"missing commit/tree object ID",
			NewGetBlobContentsRequestByObjectIDPath(reqCtx, repository, nil, readmePath),
			"twirp error invalid_argument: blob.object_id_path.oid is required",
		},
		{
			"missing blob path for ByObjectIdPath",
			NewGetBlobContentsRequestByObjectIDPath(reqCtx, repository, commit.GetOid(), nil),
			"twirp error invalid_argument: blob.object_id_path.path is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestGetBlobContentsRequestValidate(t *testing.T) {
	req := NewGetBlobContentsRequestById(reqCtx, repository, oid)
	require.NoError(t, req.Validate())

	req = NewGetBlobContentsRequestByRefPath(reqCtx, repository, ref, readmePath)
	require.NoError(t, req.Validate())
}

func TestListChangedBlobsRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ListChangedBlobsRequest
		err  string
	}{
		{
			"empty",
			&ListChangedBlobsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid commit order",
			&ListChangedBlobsRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListChangedBlobsRequest_COMMIT_ORDER_INVALID},
			"twirp error invalid_argument: commit_order is required",
		},
		{
			"missing selector",
			&ListChangedBlobsRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListChangedBlobsRequest_COMMIT_ORDER_TOPO},
			"twirp error invalid_argument: selector is required",
		},
		{
			"empty push selector",
			&ListChangedBlobsRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListChangedBlobsRequest_COMMIT_ORDER_TOPO, Selector: &ListChangedBlobsRequest_PushSelector{}},
			"twirp error invalid_argument: selector.push_selector is required",
		},
		{
			"invalid push selector",
			&ListChangedBlobsRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListChangedBlobsRequest_COMMIT_ORDER_TOPO, Selector: &ListChangedBlobsRequest_PushSelector{PushSelector: invalidPushSelector}},
			"twirp error invalid_argument: reference_updates is required",
		},
		{
			"empty fork push selector",
			&ListChangedBlobsRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListChangedBlobsRequest_COMMIT_ORDER_TOPO, Selector: &ListChangedBlobsRequest_ForkPushSelector{}},
			"twirp error invalid_argument: selector.fork_push_selector is required",
		},
		{
			"empty quarantine objects selector",
			&ListChangedBlobsRequest{RequestContext: reqCtxWithPushState, Repository: repository, CommitOrder: ListChangedBlobsRequest_COMMIT_ORDER_TOPO, Selector: &ListChangedBlobsRequest_QuarantineObjectsSelector{}},
			"twirp error invalid_argument: selector.quarantine_objects_selector is required",
		},
		{
			"invalid quarantine objects selector without push state in request",
			&ListChangedBlobsRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListChangedBlobsRequest_COMMIT_ORDER_TOPO, Selector: &ListChangedBlobsRequest_QuarantineObjectsSelector{QuarantineObjectsSelector: quarantineObjectsSelector}},
			"twirp error invalid_argument: request_context.push_state is required",
		},
		{
			"invalid fork push selector",
			&ListChangedBlobsRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListChangedBlobsRequest_COMMIT_ORDER_TOPO, Selector: &ListChangedBlobsRequest_ForkPushSelector{ForkPushSelector: invalidForkPushSelector}},
			"twirp error invalid_argument: base_repository is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestListChangedBlobsRequestValidate(t *testing.T) {
	req := NewListChangedBlobsRequestWithPushSelector(reqCtx, repository, pushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListChangedBlobsRequestWithForkPushSelector(reqCtx, repository, forkPushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListChangedBlobsRequestWithUniversalSelector(reqCtx, repository, nil)
	require.NoError(t, req.Validate())

	req = NewListChangedBlobsRequestWithQuarantineObjectsSelector(reqCtxWithPushState, repository, quarantineObjectsSelector, nil)
	require.NoError(t, req.Validate())
}

func TestListChangedBlobsRequestCommitOrder(t *testing.T) {
	req := NewListChangedBlobsRequestWithPushSelector(reqCtx, repository, pushSelector, nil)
	require.Equal(t, ListChangedBlobsRequest_COMMIT_ORDER_TOPO, req.CommitOrder)

	req = req.WithCommitOrder(ListChangedBlobsRequest_COMMIT_ORDER_REVERSE_CHRONOLOGICAL)
	require.Equal(t, ListChangedBlobsRequest_COMMIT_ORDER_REVERSE_CHRONOLOGICAL, req.CommitOrder)
}

func TestListReachableBlobsRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ListReachableBlobsRequest
		err  string
	}{
		{
			"empty",
			&ListReachableBlobsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing selector",
			&ListReachableBlobsRequest{RequestContext: reqCtx, Repository: repository},
			"twirp error invalid_argument: selector is required",
		},
		{
			"empty push selector",
			&ListReachableBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReachableBlobsRequest_PushSelector{}},
			"twirp error invalid_argument: selector.push_selector is required",
		},
		{
			"invalid push selector",
			&ListReachableBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReachableBlobsRequest_PushSelector{PushSelector: invalidPushSelector}},
			"twirp error invalid_argument: reference_updates is required",
		},
		{
			"empty fork push selector",
			&ListReachableBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReachableBlobsRequest_ForkPushSelector{}},
			"twirp error invalid_argument: selector.fork_push_selector is required",
		},
		{
			"invalid fork push selector",
			&ListReachableBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReachableBlobsRequest_ForkPushSelector{ForkPushSelector: invalidForkPushSelector}},
			"twirp error invalid_argument: base_repository is required",
		},
		{
			"empty historical push selector",
			&ListReachableBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReachableBlobsRequest_HistoricalPushSelector{}},
			"twirp error invalid_argument: selector.historical_push_selector is required",
		},
		{
			"invalid historical push selector",
			&ListReachableBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListReachableBlobsRequest_HistoricalPushSelector{HistoricalPushSelector: invalidHistoricalPushSelector}},
			"twirp error invalid_argument: reference_updates is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestListReachableBlobsRequestValidate(t *testing.T) {
	req := NewListReachableBlobsRequestWithPushSelector(reqCtx, repository, pushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListReachableBlobsRequestWithHistoricalPushSelector(reqCtx, repository, historicalPushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListReachableBlobsRequestWithForkPushSelector(reqCtx, repository, forkPushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListReachableBlobsRequestWithUniversalSelector(reqCtx, repository, nil)
	require.NoError(t, req.Validate())
}

func TestListBlobOriginRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ListBlobOriginRequest
		err  string
	}{
		{
			"empty",
			&ListBlobOriginRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid commit order",
			&ListBlobOriginRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListBlobOriginRequest_COMMIT_ORDER_INVALID},
			"twirp error invalid_argument: commit_order is required",
		},
		{
			"missing selector",
			&ListBlobOriginRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListBlobOriginRequest_COMMIT_ORDER_TOPO},
			"twirp error invalid_argument: selector is required",
		},
		{
			"empty object ID selector",
			&ListBlobOriginRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListBlobOriginRequest_COMMIT_ORDER_TOPO, Selector: &ListBlobOriginRequest_ObjectIdSelector{}},
			"twirp error invalid_argument: selector.object_id_selector is required",
		},
		{
			"invalid object ID selector",
			&ListBlobOriginRequest{RequestContext: reqCtx, Repository: repository, CommitOrder: ListBlobOriginRequest_COMMIT_ORDER_TOPO, Selector: &ListBlobOriginRequest_ObjectIdSelector{ObjectIdSelector: invalidObjectIDSelector}},
			"twirp error invalid_argument: oids is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestNewListBlobOriginRequest(t *testing.T) {
	req := NewListBlobOriginRequestWithObjectIDSelector(reqCtx, repository, []*types.ObjectID{}, nil)
	require.Error(t, req.Validate())

	req = NewListBlobOriginRequestWithObjectIDSelector(reqCtx, repository, []*types.ObjectID{oid}, nil)
	require.NoError(t, req.Validate())

	req = NewListBlobOriginRequestWithObjectIDPushSelector(reqCtx, repository, []*types.ObjectID{oid}, pushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListBlobOriginRequestWithObjectIDForkPushSelector(reqCtx, repository, []*types.ObjectID{oid}, forkPushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListBlobOriginRequestWithObjectIDUniversalSelector(reqCtx, repository, []*types.ObjectID{oid}, nil)
	require.NoError(t, req.Validate())
}

func TestNewListBlobOriginRequestCommitOrder(t *testing.T) {
	req := NewListBlobOriginRequestWithObjectIDPushSelector(reqCtx, repository, []*types.ObjectID{oid}, pushSelector, nil)
	require.Equal(t, ListBlobOriginRequest_COMMIT_ORDER_TOPO, req.CommitOrder)

	req = req.WithCommitOrder(ListBlobOriginRequest_COMMIT_ORDER_REVERSE_CHRONOLOGICAL)
	require.Equal(t, ListBlobOriginRequest_COMMIT_ORDER_REVERSE_CHRONOLOGICAL, req.CommitOrder)

	req = req.WithCommitOrder(ListBlobOriginRequest_COMMIT_ORDER_TOPO)
	require.Equal(t, ListBlobOriginRequest_COMMIT_ORDER_TOPO, req.CommitOrder)
}

func TestNewListBlobOriginRequestMaxCommitCount(t *testing.T) {
	req := NewListBlobOriginRequestWithObjectIDSelector(reqCtx, repository, []*types.ObjectID{}, nil)
	require.Error(t, req.Validate())

	req.WithMaxCommitCount(500)
	require.EqualValues(t, 500, req.MaxCommitCount)
}

func TestListPushedBlobsRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *ListPushedBlobsRequest
		err  string
	}{
		{
			"empty",
			&ListPushedBlobsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing selector",
			&ListPushedBlobsRequest{RequestContext: reqCtx, Repository: repository},
			"twirp error invalid_argument: selector is required",
		},
		{
			"empty push selector",
			&ListPushedBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListPushedBlobsRequest_PushSelector{}},
			"twirp error invalid_argument: selector.push_selector is required",
		},
		{
			"invalid push selector",
			&ListPushedBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListPushedBlobsRequest_PushSelector{PushSelector: invalidPushSelector}},
			"twirp error invalid_argument: reference_updates is required",
		},
		{
			"empty fork push selector",
			&ListPushedBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListPushedBlobsRequest_ForkPushSelector{}},
			"twirp error invalid_argument: selector.fork_push_selector is required",
		},
		{
			"invalid fork push selector",
			&ListPushedBlobsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListPushedBlobsRequest_ForkPushSelector{ForkPushSelector: invalidForkPushSelector}},
			"twirp error invalid_argument: base_repository is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestListPushedBlobsRequestValidate(t *testing.T) {
	req := NewListPushedBlobsRequestWithPushSelector(reqCtx, repository, pushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListPushedBlobsRequestWithForkPushSelector(reqCtx, repository, forkPushSelector, nil)
	require.NoError(t, req.Validate())
}
