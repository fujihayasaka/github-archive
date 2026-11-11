package attributes

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/twitchtv/twirp"
)

func NewReadAttributesRequestWithUniversalSelector(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.TreeishSelector, paths []*types.Path) *ReadAttributesRequest {
	us := selectors.NewUniversalSelector()
	return &ReadAttributesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadAttributesRequest_TreeishSelector{TreeishSelector: ts},
		Paths:          paths,
		KeysSelector:   &ReadAttributesRequest_UniversalSelector{UniversalSelector: us},
	}
}

func NewReadAttributesRequestWithKeySelector(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.TreeishSelector, paths []*types.Path, ks *selectors.KeySelector) *ReadAttributesRequest {
	return &ReadAttributesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadAttributesRequest_TreeishSelector{TreeishSelector: ts},
		Paths:          paths,
		KeysSelector:   &ReadAttributesRequest_KeySelector{KeySelector: ks},
	}
}

func (req *ReadAttributesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *ReadAttributesRequest_TreeishSelector:
		if s.TreeishSelector == nil {
			return twirp.RequiredArgumentError("selector.treeish_selector")
		}

		if err := s.TreeishSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	if len(req.GetPaths()) == 0 {
		return twirp.RequiredArgumentError("paths")
	}

	if len(req.GetPaths()) > 1000 {
		return twirp.InvalidArgumentError("paths", "may contain up to 1000 items")
	}

	for _, path := range req.GetPaths() {
		if path == nil {
			return twirp.RequiredArgumentError("path")
		}

		if err := path.Validate(); err != nil {
			return err
		}
	}

	switch s := req.GetKeysSelector().(type) {
	case *ReadAttributesRequest_UniversalSelector:
		return s.UniversalSelector.Validate()
	case *ReadAttributesRequest_KeySelector:
		if s.KeySelector == nil {
			return twirp.RequiredArgumentError("keys_selector.key_selector")
		}

		return s.KeySelector.Validate()
	default:
		return twirp.RequiredArgumentError("keys_selector")
	}
}

func (req *ReadAttributesRequest) Split() []*ReadAttributesRequest {
	reqs := make([]*ReadAttributesRequest, len(req.GetPaths()))
	for i, path := range req.GetPaths() {
		switch req.GetKeysSelector().(type) {
		case *ReadAttributesRequest_KeySelector:
			reqs[i] = NewReadAttributesRequestWithKeySelector(
				req.GetRequestContext(),
				req.GetRepository(),
				req.GetTreeishSelector(),
				[]*types.Path{path},
				req.GetKeySelector(),
			)
		default: // *ReadAttributesRequest_UniversalSelector
			reqs[i] = NewReadAttributesRequestWithUniversalSelector(
				req.GetRequestContext(),
				req.GetRepository(),
				req.GetTreeishSelector(),
				[]*types.Path{path},
			)
		}
	}
	return reqs
}

func (req *ReadAttributesRequest) Join(reqs ...*ReadAttributesRequest) *ReadAttributesRequest {
	if req == nil {
		return nil
	}

	var finalReq *ReadAttributesRequest

	switch req.GetKeysSelector().(type) {
	case *ReadAttributesRequest_KeySelector:
		finalReq = NewReadAttributesRequestWithKeySelector(
			req.GetRequestContext(),
			req.GetRepository(),
			req.GetTreeishSelector(),
			req.GetPaths(),
			req.GetKeySelector(),
		)
	default: // *ReadAttributesRequest_UniversalSelector
		finalReq = NewReadAttributesRequestWithUniversalSelector(
			req.GetRequestContext(),
			req.GetRepository(),
			req.GetTreeishSelector(),
			req.GetPaths(),
		)
	}

	for _, r := range reqs {
		finalReq.Paths = append(finalReq.Paths, r.GetPaths()...)
	}

	return finalReq
}

func NewReadAttributesResponse(items ...*AttributeItem) *ReadAttributesResponse {
	return &ReadAttributesResponse{
		AttributeItems: items,
	}
}

func (resp *ReadAttributesResponse) Split() []*ReadAttributesResponse {
	resps := make([]*ReadAttributesResponse, len(resp.GetAttributeItems()))
	for i, item := range resp.GetAttributeItems() {
		resps[i] = NewReadAttributesResponse(item)
	}
	return resps
}

func (resp *ReadAttributesResponse) Join(resps ...*ReadAttributesResponse) *ReadAttributesResponse {
	if resp == nil {
		return nil
	}
	finalResp := NewReadAttributesResponse(resp.GetAttributeItems()...)
	for _, r := range resps {
		finalResp.AttributeItems = append(finalResp.AttributeItems, r.GetAttributeItems()...)
	}
	return finalResp
}
