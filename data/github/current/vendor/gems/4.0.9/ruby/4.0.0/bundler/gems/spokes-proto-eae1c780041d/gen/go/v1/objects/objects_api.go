package objects

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/twitchtv/twirp"
)

func NewResolveObjectRequest(reqCtx *types.RequestContext, repository *types.Repository, name *types.Revision) *ResolveObjectRequest {
	return &ResolveObjectRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		ObjectName:     name,
	}
}

func (req *ResolveObjectRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	name := req.GetObjectName()
	if name == nil {
		return twirp.RequiredArgumentError("object_name")
	}

	if err := name.Validate(); err != nil {
		return err
	}

	return nil
}

func NewResolveObjectsRequest(reqCtx *types.RequestContext, repository *types.Repository, objects ...*selectors.ObjectSelector) *ResolveObjectsRequest {
	return &ResolveObjectsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selectors:      objects,
	}
}

func (req *ResolveObjectsRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	selectors := req.GetSelectors()
	if len(selectors) < 1 {
		return twirp.RequiredArgumentError("selectors")
	}
	if len(selectors) > 1000 {
		return twirp.InvalidArgumentError("selectors", "may contain up to 1000 items")
	}

	// Note: The selectors will be validated individually. See the docs for
	// ResolveObjects for details about how these validation errors will be
	// reported.

	return nil
}

func (req *ResolveObjectsRequest) Split() []*ResolveObjectsRequest {
	reqs := make([]*ResolveObjectsRequest, len(req.GetSelectors()))
	for i, sel := range req.GetSelectors() {
		reqs[i] = NewResolveObjectsRequest(
			req.GetRequestContext(),
			req.GetRepository(),
			sel,
		)
	}
	return reqs
}

func (req *ResolveObjectsRequest) Join(reqs ...*ResolveObjectsRequest) *ResolveObjectsRequest {
	if req == nil {
		return nil
	}
	finalReq := NewResolveObjectsRequest(
		req.GetRequestContext(),
		req.GetRepository(),
		req.GetSelectors()...,
	)
	for _, req := range reqs {
		finalReq.Selectors = append(finalReq.Selectors, req.GetSelectors()...)
	}
	return finalReq
}

func NewResolveObjectsResolvedObject(object *types.Object) *ResolveObjectsResponse_ResolvedItem {
	return &ResolveObjectsResponse_ResolvedItem{
		Item: &ResolveObjectsResponse_ResolvedItem_Object{
			Object: object,
		},
	}
}

func NewResolveObjectsResolvedError(message string) *ResolveObjectsResponse_ResolvedItem {
	return &ResolveObjectsResponse_ResolvedItem{
		Item: &ResolveObjectsResponse_ResolvedItem_Error{
			Error: message,
		},
	}
}

func NewResolveObjectsResponse(items ...*ResolveObjectsResponse_ResolvedItem) *ResolveObjectsResponse {
	return &ResolveObjectsResponse{
		Items: items,
	}
}

func (resp *ResolveObjectsResponse) Split() []*ResolveObjectsResponse {
	resps := make([]*ResolveObjectsResponse, len(resp.GetItems()))
	for i, item := range resp.GetItems() {
		resps[i] = NewResolveObjectsResponse(item)
	}
	return resps
}

func (resp *ResolveObjectsResponse) Join(resps ...*ResolveObjectsResponse) *ResolveObjectsResponse {
	if resp == nil {
		return nil
	}
	finalResp := NewResolveObjectsResponse(resp.GetItems()...)
	for _, resp := range resps {
		finalResp.Items = append(finalResp.Items, resp.GetItems()...)
	}
	return finalResp
}

func NewReadObjectsRequest(reqCtx *types.RequestContext, repository *types.Repository, objects ...*selectors.ObjectSelector) *ReadObjectsRequest {
	return &ReadObjectsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selectors:      objects,
	}
}

func (req *ReadObjectsRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	selectors := req.GetSelectors()
	if len(selectors) < 1 {
		return twirp.RequiredArgumentError("selectors")
	}

	if len(selectors) > 1000 {
		return twirp.InvalidArgumentError("selectors", "may contain up to 1000 items")
	}

	for _, selector := range selectors {
		if selector == nil {
			return twirp.RequiredArgumentError("selector")
		} else if err := selector.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func NewExpandOidsRequest(reqCtx *types.RequestContext, repository *types.Repository, selectors []*selectors.ObjectSelector) *ExpandOidsRequest {
	return &ExpandOidsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selectors:      selectors,
	}
}

func (req *ExpandOidsRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	selectors := req.GetSelectors()
	if len(selectors) < 1 {
		return twirp.RequiredArgumentError("selectors")
	}

	if len(selectors) > 1000 {
		return twirp.InvalidArgumentError("selectors", "may contain up to 1000 items")
	}

	for _, selector := range selectors {
		if selector == nil {
			return twirp.RequiredArgumentError("selector")
		}

		if err := selector.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func NewCreateObjectsRequest(reqCtx *types.RequestContext, repository *types.Repository, objects ...*CreatableObject) *CreateObjectsRequest {
	return &CreateObjectsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Objects:        objects,
	}
}

func (req *CreateObjectsRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	if req.GetRequestContext() == nil {
		return twirp.RequiredArgumentError("request_context")
	}
	
	
	if req.GetRequestContext().GetTransactionState() == nil {
		return twirp.RequiredArgumentError("request_context.transaction_state")
	}

	objects := req.GetObjects()
	if len(objects) < 1 {
		return twirp.RequiredArgumentError("objects")
	}
	if len(objects) > 1000 {
		return twirp.InvalidArgumentError("objects", "may not contain more than 1000 items")
	}

	for _, obj := range objects {
		if obj == nil {
			return twirp.RequiredArgumentError("objects")
		}

		objType := obj.GetType()
		if objType == nil {
			return twirp.RequiredArgumentError("type")
		}

		// Note: content can be empty (e.g., an empty tree is always created when initializing a repo),
		// so we don't validate that here.

		if err := objType.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func (resp *CreateObjectsResponse) SetTransactionContext(transactionContext *types.TransactionContext) {
	if resp != nil {
		resp.TransactionContext = transactionContext
	}
}
