package experimental

import (
	types "github.com/github/spokes-proto/gen/go/v1/types"
	selectors "github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/twitchtv/twirp"
)

func NewResolveObjectsRequest(reqCtx *types.RequestContext, selectors ...*ObjectSelectorsByRepo) *ResolveObjectsRequest {
	return &ResolveObjectsRequest{
		RequestContext:        reqCtx,
		ObjectSelectorsByRepo: selectors,
	}
}

func NewObjectSelectorsByRepo(repository *types.Repository, selectors ...*selectors.ObjectSelector) *ObjectSelectorsByRepo {
	return &ObjectSelectorsByRepo{
		Repository: repository,
		Selectors:  selectors,
	}
}

func (req *ResolveObjectsRequest) Validate() error {
	if len(req.GetObjectSelectorsByRepo()) < 1 {
		return twirp.RequiredArgumentError("ObjectSelectorsByRepo")
	}

	for i, batch := range req.ObjectSelectorsByRepo {
		if err := batch.Validate(i); err != nil {
			return err
		}
	}

	return nil
}

func (s *ObjectSelectorsByRepo) Validate(index int) error {
	if s.Repository == nil {
		return twirp.InvalidArgument.Errorf("repository cannot be empty @ ObjectSelectorsByRepo[%d]", index)
	}

	if err := s.Repository.Validate(); err != nil {
		if twerr, ok := err.(twirp.Error); ok {
			return twirp.InvalidArgument.Errorf("invalid repository @ ObjectSelectorsByRepo[%d] %s", index, twerr.Msg())
		} else {
			return twirp.InvalidArgument.Errorf("invalid repository @ ObjectSelectorsByRepo[%d] %s", index, err.Error())
		}
	}

	if len(s.Selectors) < 1 {
		return twirp.InvalidArgument.Errorf("selectors cannot be empty @ ObjectSelectorsByRepo[%d]", index)
	}

	if len(s.Selectors) > 1000 {
		return twirp.InvalidArgument.Errorf("selectors contain more than 1000 items @ ObjectSelectorsByRepo[%d]", index)
	}

	return nil
}
