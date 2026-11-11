package trees

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

func NewListTreesRequestWithTreeishSelector(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.TreeishSelector) *ListTreesRequest {
	req := &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishSelector{TreeishSelector: ts},
	}

	return req
}

func NewListTreesRequestWithTreeishAndPathSelector(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.TreeishAndPathSelector) *ListTreesRequest {
	req := &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishAndPathSelector{TreeishAndPathSelector: ts},
	}

	return req
}

func (req *ListTreesRequest) WithRecursive() *ListTreesRequest {
	req.Recursive = true
	return req
}

func (req *ListTreesRequest) WithFlattenPaths() *ListTreesRequest {
	req.FlattenPaths = true
	return req
}

func (req *ListTreesRequest) WithCursor(cursor *types.Cursor) *ListTreesRequest {
	req.Cursor = cursor
	return req
}

func (req *ListTreesRequest) WithPathspec(pathspec *types.Pathspec) *ListTreesRequest {
	req.Pathspec = pathspec
	return req
}

func (req *ListTreesRequest) WithIncludeEol() *ListTreesRequest {
	req.IncludeEol = true
	return req
}

func (req *ListTreesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *ListTreesRequest_TreeishSelector:
		if s.TreeishSelector == nil {
			return twirp.RequiredArgumentError("selector.treeish_selector")
		}

		if err := s.TreeishSelector.Validate(); err != nil {
			return err
		}
	case *ListTreesRequest_TreeishAndPathSelector:
		if s.TreeishAndPathSelector == nil {
			return twirp.RequiredArgumentError("selector.treeish_and_path_selector")
		}

		if err := s.TreeishAndPathSelector.Validate(); err != nil {
			return err
		}

		if req.GetPathspec() != nil {
			return twirp.InvalidArgumentError("pathspec", "cannot be used with treeish_and_path selector")
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	if err := req.GetPathspec().Validate(); err != nil {
		return err
	}

	return nil
}

func NewCompareTreesRequestWithRangeSelector(reqCtx *types.RequestContext, repository *types.Repository, rs *selectors.RangeSelector, recursive, includeRenames bool, cursor *types.Cursor) *CompareTreesRequest {
	return &CompareTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &CompareTreesRequest_RangeSelector{RangeSelector: rs},
		Recursive:      recursive,
		IncludeRenames: includeRenames,
		Cursor:         cursor,
	}
}

func (req *CompareTreesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *CompareTreesRequest_RangeSelector:
		if s.RangeSelector == nil {
			return twirp.RequiredArgumentError("selector.range_selector")
		}

		if err := s.RangeSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	return nil
}

func NewReadTreeEntryOidRequest(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.TreeishSelector, path *types.Path, objectType *types.ObjectType) *ReadTreeEntryOidRequest {
	return &ReadTreeEntryOidRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadTreeEntryOidRequest_TreeishSelector{ts},
		Path:           path,
		Type:           objectType,
	}
}

func (req *ReadTreeEntryOidRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *ReadTreeEntryOidRequest_TreeishSelector:
		if s.TreeishSelector == nil {
			return twirp.RequiredArgumentError("selector.treeish_selector")
		}

		if err := s.TreeishSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	// Path is allowed to be nil, but if not nil, then
	// it must be valid (it has a non-nil name).
	path := req.GetPath()
	if path != nil {
		if err := path.Validate(); err != nil {
			return err
		}
	}

	// ObjectType is allowed to be nil, but if not nil, then
	// it must be a valid git object type.
	objectType := req.GetType()
	if objectType != nil {
		if err := objectType.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func NewCreateTreeRequest(reqCtx *types.RequestContext, repository *types.Repository, baseTree *types.ObjectID, entries ...*CreateTreeRequest_TreeEntry) *CreateTreeRequest {
	return &CreateTreeRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		BaseTree:       baseTree,
		Entries:        entries,
	}
}

func (req *CreateTreeRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetRequestContext() == nil {
		return twirp.RequiredArgumentError("request_context")
	}

	if req.GetRequestContext().GetTransactionState() == nil {
		return twirp.RequiredArgumentError("request_context.transaction_state")
	}

	// BaseTree is optional, but if provided must be valid
	baseTree := req.GetBaseTree()
	if baseTree != nil {
		if err := baseTree.Validate(); err != nil {
			return err
		}
	}

	for _, entry := range req.GetEntries() {
		if entry == nil {
			return twirp.RequiredArgumentError("entries")
		}

		if err := entry.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func NewCreateTreeRequestEntry(mode *types.Mode, oid *types.ObjectID, path *types.Path) *CreateTreeRequest_TreeEntry {
	return &CreateTreeRequest_TreeEntry{
		Mode: mode,
		Oid:  oid,
		Path: path,
	}
}

func (te *CreateTreeRequest_TreeEntry) Validate() error {
	if te == nil {
		return nil
	}

	if te.GetMode() == nil {
		return twirp.RequiredArgumentError("mode")
	}

	if err := te.GetMode().Validate(); err != nil {
		return err
	}

	if te.GetOid() == nil {
		return twirp.RequiredArgumentError("oid")
	}

	if err := te.GetOid().Validate(); err != nil {
		return err
	}

	if te.GetPath() == nil {
		return twirp.RequiredArgumentError("path")
	}

	if err := te.GetPath().Validate(); err != nil {
		return err
	}

	return nil
}

func (resp *CreateTreeResponse) SetTransactionContext(transactionContext *types.TransactionContext) {
	if resp != nil {
		resp.TransactionContext = transactionContext
	}
}
