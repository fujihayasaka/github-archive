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
