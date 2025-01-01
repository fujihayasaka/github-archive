package references

import (
	"fmt"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/extensions"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

func NewResolveReferencesRequest(reqCtx *types.RequestContext, repository *types.Repository, refs ...*types.Reference) *ResolveReferencesRequest {
	return &ResolveReferencesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		References:     refs,
	}
}

func (req *ResolveReferencesRequest) Split() []*ResolveReferencesRequest {
	reqs := make([]*ResolveReferencesRequest, len(req.GetReferences()))
	for i, ref := range req.GetReferences() {
		reqs[i] = NewResolveReferencesRequest(
			req.GetRequestContext(),
			req.GetRepository(),
			ref,
		)
	}
	return reqs
}

func (req *ResolveReferencesRequest) Join(reqs ...*ResolveReferencesRequest) *ResolveReferencesRequest {
	if req == nil {
		return nil
	}
	finalReq := NewResolveReferencesRequest(
		req.GetRequestContext(),
		req.GetRepository(),
		req.GetReferences()...,
	)
	for _, req := range reqs {
		finalReq.References = append(finalReq.References, req.GetReferences()...)
	}
	return finalReq
}

func (req *ResolveReferencesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	references := req.GetReferences()
	if len(references) < 1 {
		return twirp.RequiredArgumentError("references")
	}

	desc := req.ProtoReflect().Descriptor().Fields().ByName("references")
	refLimit := int(proto.GetExtension(desc.Options(), extensions.E_Limit).(uint32))
	if refLimit > 0 && len(references) > refLimit {
		return twirp.InvalidArgumentError("references", fmt.Sprintf("may contain up to %d items", refLimit))
	}

	// Note: The references will be validated individually. See the docs for
	// ResolveReferences for details about how these validation errors will
	// be handled.

	return nil
}

func NewResolveReferencesResponse(items ...*ResolveReferencesResponse_ResolvedReference) *ResolveReferencesResponse {
	return &ResolveReferencesResponse{
		Items: items,
	}
}

func (resp *ResolveReferencesResponse) Split() []*ResolveReferencesResponse {
	resps := make([]*ResolveReferencesResponse, len(resp.GetItems()))
	for i, item := range resp.GetItems() {
		resps[i] = NewResolveReferencesResponse(item)
	}
	return resps
}

func (resp *ResolveReferencesResponse) Join(resps ...*ResolveReferencesResponse) *ResolveReferencesResponse {
	if resp == nil {
		return nil
	}
	finalResp := NewResolveReferencesResponse(resp.GetItems()...)
	for _, resp := range resps {
		finalResp.Items = append(finalResp.Items, resp.GetItems()...)
	}
	return finalResp
}

func NewListReferencesRequestWithUniversalSelector(reqCtx *types.RequestContext, repository *types.Repository, cursor *types.Cursor) *ListReferencesRequest {
	return &ListReferencesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListReferencesRequest_UniversalSelector{UniversalSelector: selectors.NewUniversalSelector()},
		Cursor:         cursor,
	}
}

func NewListReferencesRequestWithPrefixSelector(reqCtx *types.RequestContext, repository *types.Repository, prefixes *selectors.PrefixSelector, cursor *types.Cursor) *ListReferencesRequest {
	return &ListReferencesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListReferencesRequest_PrefixSelector{PrefixSelector: prefixes},
		Cursor:         cursor,
	}
}

func (req *ListReferencesRequest) WithPointsAt(pointsAt []*types.ObjectID) *ListReferencesRequest {
	if req.RefListOptions == nil {
		req.RefListOptions = &RefListOptions{}
	}
	req.RefListOptions.PointsAt = pointsAt
	return req
}

func (req *ListReferencesRequest) WithContains(contains []*types.ObjectID) *ListReferencesRequest {
	if req.RefListOptions == nil {
		req.RefListOptions = &RefListOptions{}
	}
	req.RefListOptions.Contains = contains
	return req
}

func (req *ListReferencesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *ListReferencesRequest_UniversalSelector:
		if s.UniversalSelector == nil {
			return twirp.RequiredArgumentError("selector.universal_selector")
		}

		if err := s.UniversalSelector.Validate(); err != nil {
			return err
		}
	case *ListReferencesRequest_PrefixSelector:
		if s.PrefixSelector == nil {
			return twirp.RequiredArgumentError("selector.prefix_selector")
		}

		if err := s.PrefixSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	if req.RefListOptions != nil {
		if err := req.RefListOptions.Validate(); err != nil {
			return twirp.InvalidArgumentError("ref_list_options", fmt.Sprintf("invalid RefListOptions: %v", err))
		}
	}

	return nil
}

func (req *GetDefaultBranchRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *ListReferencesWithDetailsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *ListReferencesWithDetailsRequest_UniversalSelector:
		if s.UniversalSelector == nil {
			return twirp.RequiredArgumentError("selector.universal_selector")
		}

		if err := s.UniversalSelector.Validate(); err != nil {
			return err
		}
	case *ListReferencesWithDetailsRequest_RefGlobSelector:
		if s.RefGlobSelector == nil {
			return twirp.RequiredArgumentError("selector.ref_glob_selector")
		}

		if err := s.RefGlobSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	if req.RefListOptions != nil {
		if err := req.RefListOptions.Validate(); err != nil {
			return twirp.InvalidArgumentError("ref_list_options", fmt.Sprintf("invalid RefListOptions: %v", err))
		}
	}

	return nil
}

func (refListOptions *RefListOptions) Validate() error {
	if pa := refListOptions.GetPointsAt(); pa != nil {
		if len(pa) > 25 {
			return twirp.InvalidArgumentError("points_at", "may contain up to 25 items")
		}
		for _, p := range pa {
			if err := p.Validate(); err != nil {
				return twirp.InvalidArgumentError("points_at", fmt.Sprintf("invalid ObjectID: %v", err))
			}
		}
	}

	if c := refListOptions.GetContains(); c != nil {
		if len(c) > 25 {
			return twirp.InvalidArgumentError("contains", "may contain up to 25 items")
		}
		for _, contains := range c {
			if err := contains.Validate(); err != nil {
				return twirp.InvalidArgumentError("contains", fmt.Sprintf("invalid ObjectID: %v", err))
			}
		}
	}

	return nil
}

func (req *UpdateDefaultBranchRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetNewValue() == nil {
		return twirp.RequiredArgumentError("new_value")
	}

	if err := req.GetNewValue().Validate(); err != nil {
		return err
	}

	if err := req.GetNewValue().ValidateFormat(); err != nil {
		return err
	}

	if req.GetNewValue().IsDefaultBranch() {
		return twirp.InvalidArgumentError("new_value", "cannot be HEAD")
	}

	return nil
}

func (req *ReferencesExistRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}
