package trees

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

func NewListTreesRequestWithTreeishSelector(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.TreeishSelector, recursive bool, cursor *types.Cursor) *ListTreesRequest {
	return &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishSelector{TreeishSelector: ts},
		Recursive:      recursive,
		Cursor:         cursor,
	}
}

func NewListTreesRequestWithTreeishAndPathSelector(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.TreeishAndPathSelector, recursive bool, cursor *types.Cursor) *ListTreesRequest {
	return &ListTreesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListTreesRequest_TreeishAndPathSelector{TreeishAndPathSelector: ts},
		Recursive:      recursive,
		Cursor:         cursor,
	}
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
	default:
		return twirp.RequiredArgumentError("selector")
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
