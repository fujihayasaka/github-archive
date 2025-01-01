package blobs

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/twitchtv/twirp"
)

func NewGetBlobContentsRequestById(reqCtx *types.RequestContext, repository *types.Repository, id *types.ObjectID) *GetBlobContentsRequest {
	return &GetBlobContentsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Blob:           &GetBlobContentsRequest_ById{ById: id},
	}
}

func NewGetBlobContentsRequestByRefPath(reqCtx *types.RequestContext, repository *types.Repository, ref *types.Reference, path *types.Path) *GetBlobContentsRequest {
	return &GetBlobContentsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Blob: &GetBlobContentsRequest_ByRefPath{
			ByRefPath: &GetBlobContentsRequest_RefPath{
				Reference: ref,
				Path:      path,
			},
		},
	}
}

// NewGetBlobContentsRequestByObjectIDPath returns a GetBlobContentsRequest to get a blob at a path given a commit or tree.
func NewGetBlobContentsRequestByObjectIDPath(reqCtx *types.RequestContext, repository *types.Repository, oid *types.ObjectID, path *types.Path) *GetBlobContentsRequest {
	return &GetBlobContentsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Blob: &GetBlobContentsRequest_ByObjectIdPath{
			ByObjectIdPath: &GetBlobContentsRequest_ObjectIDPath{
				Oid:  oid,
				Path: path,
			},
		},
	}
}

func (req *GetBlobContentsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch b := req.GetBlob().(type) {
	case *GetBlobContentsRequest_ById:
		if b.ById == nil {
			return twirp.RequiredArgumentError("blob.id")
		}

		if err := b.ById.Validate(); err != nil {
			return err
		}
	case *GetBlobContentsRequest_ByRefPath:
		if b.ByRefPath == nil {
			return twirp.RequiredArgumentError("blob.ref_path")
		}

		ref := b.ByRefPath.Reference
		path := b.ByRefPath.Path

		if ref == nil {
			return twirp.RequiredArgumentError("blob.ref_path.reference")
		}

		if err := ref.Validate(); err != nil {
			return err
		}

		if path == nil {
			return twirp.RequiredArgumentError("blob.ref_path.path")
		}

		if err := path.Validate(); err != nil {
			return err
		}
	case *GetBlobContentsRequest_ByObjectIdPath:
		if b.ByObjectIdPath == nil {
			return twirp.RequiredArgumentError("blob.object_id_path")
		}

		oid := b.ByObjectIdPath.Oid
		path := b.ByObjectIdPath.Path

		if oid == nil {
			return twirp.RequiredArgumentError("blob.object_id_path.oid")
		}

		if err := oid.Validate(); err != nil {
			return err
		}

		if path == nil {
			return twirp.RequiredArgumentError("blob.object_id_path.path")
		}

		if err := path.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("blob")
	}

	return nil
}

func NewListChangedBlobsRequestWithPushSelector(reqCtx *types.RequestContext, r *types.Repository, ps *selectors.PushSelector, cursor *types.Cursor) *ListChangedBlobsRequest {
	return &ListChangedBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListChangedBlobsRequest_PushSelector{PushSelector: ps},
		Cursor:         cursor,
		CommitOrder:    ListChangedBlobsRequest_COMMIT_ORDER_TOPO,
	}
}

func NewListChangedBlobsRequestWithQuarantineObjectsSelector(reqCtx *types.RequestContext, r *types.Repository, ps *selectors.QuarantineObjectsSelector, cursor *types.Cursor) *ListChangedBlobsRequest {
	return &ListChangedBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListChangedBlobsRequest_QuarantineObjectsSelector{QuarantineObjectsSelector: ps},
		Cursor:         cursor,
		CommitOrder:    ListChangedBlobsRequest_COMMIT_ORDER_TOPO,
	}
}

func NewListChangedBlobsRequestWithForkPushSelector(reqCtx *types.RequestContext, r *types.Repository, fps *selectors.ForkPushSelector, cursor *types.Cursor) *ListChangedBlobsRequest {
	return &ListChangedBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListChangedBlobsRequest_ForkPushSelector{ForkPushSelector: fps},
		Cursor:         cursor,
		CommitOrder:    ListChangedBlobsRequest_COMMIT_ORDER_TOPO,
	}
}

func NewListChangedBlobsRequestWithUniversalSelector(reqCtx *types.RequestContext, r *types.Repository, cursor *types.Cursor) *ListChangedBlobsRequest {
	us := selectors.NewUniversalSelector()
	return &ListChangedBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListChangedBlobsRequest_UniversalSelector{UniversalSelector: us},
		Cursor:         cursor,
		CommitOrder:    ListChangedBlobsRequest_COMMIT_ORDER_TOPO,
	}
}

func (req *ListChangedBlobsRequest) WithCommitOrder(commitOrder ListChangedBlobsRequest_CommitOrder) *ListChangedBlobsRequest {
	req.CommitOrder = commitOrder
	return req
}

func (req *ListChangedBlobsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetCommitOrder() == ListChangedBlobsRequest_COMMIT_ORDER_INVALID {
		return twirp.RequiredArgumentError("commit_order")
	}

	if req.GetSelector() == nil {
		return twirp.RequiredArgumentError("selector")
	}

	switch s := req.GetSelector().(type) {
	case *ListChangedBlobsRequest_PushSelector:
		if s.PushSelector == nil {
			return twirp.RequiredArgumentError("selector.push_selector")
		}

		return s.PushSelector.Validate()
	case *ListChangedBlobsRequest_ForkPushSelector:
		if s.ForkPushSelector == nil {
			return twirp.RequiredArgumentError("selector.fork_push_selector")
		}

		return s.ForkPushSelector.Validate()
	case *ListChangedBlobsRequest_QuarantineObjectsSelector:
		if s.QuarantineObjectsSelector == nil {
			return twirp.RequiredArgumentError("selector.quarantine_objects_selector")
		}

		if req.GetRequestContext().GetPushState() == nil {
			return twirp.RequiredArgumentError("request_context.push_state")
		}

		return s.QuarantineObjectsSelector.Validate()
	case *ListChangedBlobsRequest_UniversalSelector:
		return s.UniversalSelector.Validate()
	}

	return twirp.InvalidArgumentError("selector", "selector type known")
}

func NewListReachableBlobsRequestWithPushSelector(reqCtx *types.RequestContext, r *types.Repository, ps *selectors.PushSelector, cursor *types.Cursor) *ListReachableBlobsRequest {
	return &ListReachableBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListReachableBlobsRequest_PushSelector{PushSelector: ps},
		Cursor:         cursor,
	}
}

func NewListReachableBlobsRequestWithHistoricalPushSelector(reqCtx *types.RequestContext, r *types.Repository, hps *selectors.HistoricalPushSelector, cursor *types.Cursor) *ListReachableBlobsRequest {
	return &ListReachableBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListReachableBlobsRequest_HistoricalPushSelector{HistoricalPushSelector: hps},
		Cursor:         cursor,
	}
}

func NewListReachableBlobsRequestWithForkPushSelector(reqCtx *types.RequestContext, r *types.Repository, fps *selectors.ForkPushSelector, cursor *types.Cursor) *ListReachableBlobsRequest {
	return &ListReachableBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListReachableBlobsRequest_ForkPushSelector{ForkPushSelector: fps},
		Cursor:         cursor,
	}
}

func NewListReachableBlobsRequestWithUniversalSelector(reqCtx *types.RequestContext, r *types.Repository, cursor *types.Cursor) *ListReachableBlobsRequest {
	us := selectors.NewUniversalSelector()
	return &ListReachableBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListReachableBlobsRequest_UniversalSelector{UniversalSelector: us},
		Cursor:         cursor,
	}
}

func (req *ListReachableBlobsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetSelector() == nil {
		return twirp.RequiredArgumentError("selector")
	}

	switch s := req.GetSelector().(type) {
	case *ListReachableBlobsRequest_PushSelector:
		if s.PushSelector == nil {
			return twirp.RequiredArgumentError("selector.push_selector")
		}

		if err := s.PushSelector.Validate(); err != nil {
			return err
		}
	case *ListReachableBlobsRequest_HistoricalPushSelector:
		if s.HistoricalPushSelector == nil {
			return twirp.RequiredArgumentError("selector.historical_push_selector")
		}

		if err := s.HistoricalPushSelector.Validate(); err != nil {
			return err
		}
	case *ListReachableBlobsRequest_ForkPushSelector:
		if s.ForkPushSelector == nil {
			return twirp.RequiredArgumentError("selector.fork_push_selector")
		}

		if err := s.ForkPushSelector.Validate(); err != nil {
			return err
		}
	case *ListReachableBlobsRequest_UniversalSelector:
		return s.UniversalSelector.Validate()
	}

	return nil
}

// NewListBlobOriginRequestWithObjectIDSelector returns a ListBlobOriginRequest with the UniversalSelector
func NewListBlobOriginRequestWithObjectIDSelector(reqCtx *types.RequestContext, repository *types.Repository, oids []*types.ObjectID, cursor *types.Cursor) *ListBlobOriginRequest {
	return NewListBlobOriginRequestWithObjectIDUniversalSelector(reqCtx, repository, oids, cursor)
}

func NewListBlobOriginRequestWithObjectIDPushSelector(reqCtx *types.RequestContext, repository *types.Repository, oids []*types.ObjectID, ps *selectors.PushSelector, cursor *types.Cursor) *ListBlobOriginRequest {
	return &ListBlobOriginRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListBlobOriginRequest_ObjectIdSelector{ObjectIdSelector: selectors.NewObjectIDSelector(oids...)},
		RefSelector:    &ListBlobOriginRequest_PushSelector{PushSelector: ps},
		Cursor:         cursor,
		CommitOrder:    ListBlobOriginRequest_COMMIT_ORDER_TOPO,
	}
}

func NewListBlobOriginRequestWithObjectIDForkPushSelector(reqCtx *types.RequestContext, repository *types.Repository, oids []*types.ObjectID, fps *selectors.ForkPushSelector, cursor *types.Cursor) *ListBlobOriginRequest {
	return &ListBlobOriginRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListBlobOriginRequest_ObjectIdSelector{ObjectIdSelector: selectors.NewObjectIDSelector(oids...)},
		RefSelector:    &ListBlobOriginRequest_ForkPushSelector{ForkPushSelector: fps},
		Cursor:         cursor,
		CommitOrder:    ListBlobOriginRequest_COMMIT_ORDER_TOPO,
	}
}

func NewListBlobOriginRequestWithObjectIDUniversalSelector(reqCtx *types.RequestContext, repository *types.Repository, oids []*types.ObjectID, cursor *types.Cursor) *ListBlobOriginRequest {
	return &ListBlobOriginRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListBlobOriginRequest_ObjectIdSelector{ObjectIdSelector: selectors.NewObjectIDSelector(oids...)},
		RefSelector:    &ListBlobOriginRequest_UniversalSelector{UniversalSelector: selectors.NewUniversalSelector()},
		Cursor:         cursor,
		CommitOrder:    ListBlobOriginRequest_COMMIT_ORDER_TOPO,
	}
}

func (req *ListBlobOriginRequest) WithCommitOrder(commitOrder ListBlobOriginRequest_CommitOrder) *ListBlobOriginRequest {
	req.CommitOrder = commitOrder
	return req
}

func (req *ListBlobOriginRequest) WithMaxCommitCount(maxCommitCount uint) *ListBlobOriginRequest {
	req.MaxCommitCount = uint32(maxCommitCount)
	return req
}

func (req *ListBlobOriginRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetCommitOrder() == ListBlobOriginRequest_COMMIT_ORDER_INVALID {
		return twirp.RequiredArgumentError("commit_order")
	}

	if req.GetSelector() == nil {
		return twirp.RequiredArgumentError("selector")
	}

	switch s := req.GetSelector().(type) {
	case *ListBlobOriginRequest_ObjectIdSelector:
		if s.ObjectIdSelector == nil {
			return twirp.RequiredArgumentError("selector.object_id_selector")
		}
		if err := s.ObjectIdSelector.Validate(); err != nil {
			return err
		}
	}

	if selector := req.GetRefSelector(); selector != nil {
		switch s := selector.(type) {
		case *ListBlobOriginRequest_ForkPushSelector:
			if s.ForkPushSelector == nil {
				return twirp.RequiredArgumentError("ref_selector.fork_push_selector")
			}

			if err := s.ForkPushSelector.Validate(); err != nil {
				return err
			}
		case *ListBlobOriginRequest_PushSelector:
			if s.PushSelector == nil {
				return twirp.RequiredArgumentError("ref_selector.push_selector")
			}
			if err := s.PushSelector.Validate(); err != nil {
				return err
			}
		case *ListBlobOriginRequest_UniversalSelector:
			if err := s.UniversalSelector.Validate(); err != nil {
				return err
			}
		default:
			return twirp.RequiredArgumentError("ref_selector")
		}
	}
	return nil
}

func NewListPushedBlobsRequestWithPushSelector(reqCtx *types.RequestContext, r *types.Repository, ps *selectors.PushSelector, cursor *types.Cursor) *ListPushedBlobsRequest {
	return &ListPushedBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListPushedBlobsRequest_PushSelector{PushSelector: ps},
		Cursor:         cursor,
	}
}

func NewListPushedBlobsRequestWithForkPushSelector(reqCtx *types.RequestContext, r *types.Repository, ps *selectors.ForkPushSelector, cursor *types.Cursor) *ListPushedBlobsRequest {
	return &ListPushedBlobsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListPushedBlobsRequest_ForkPushSelector{ForkPushSelector: ps},
		Cursor:         cursor,
	}
}

func (req *ListPushedBlobsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetSelector() == nil {
		return twirp.RequiredArgumentError("selector")
	}

	switch s := req.GetSelector().(type) {
	case *ListPushedBlobsRequest_PushSelector:
		if s.PushSelector == nil {
			return twirp.RequiredArgumentError("selector.push_selector")
		}

		return s.PushSelector.Validate()
	case *ListPushedBlobsRequest_ForkPushSelector:
		if s.ForkPushSelector == nil {
			return twirp.RequiredArgumentError("selector.fork_push_selector")
		}

		return s.ForkPushSelector.Validate()
	}

	return twirp.InvalidArgumentError("selector", "selector type known")
}
