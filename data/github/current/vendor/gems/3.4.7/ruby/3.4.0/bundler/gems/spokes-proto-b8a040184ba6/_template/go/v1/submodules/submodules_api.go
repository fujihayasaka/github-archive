package submodules

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

func NewReadSubmodulesRequest(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.TreeishSelector, paths ...*types.Path) *ReadSubmodulesRequest {
	return &ReadSubmodulesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ReadSubmodulesRequest_TreeishSelector{TreeishSelector: ts},
		Paths:          paths,
	}
}

func (req *ReadSubmodulesRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *ReadSubmodulesRequest_TreeishSelector:
		if s.TreeishSelector == nil {
			return twirp.RequiredArgumentError("selector.treeish_selector")
		}

		if err := s.TreeishSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	paths := req.GetPaths()
	if len(paths) < 1 {
		return twirp.RequiredArgumentError("paths")
	}
	if len(paths) > 1000 {
		return twirp.InvalidArgumentError("paths", "may contain up to 1000 items")
	}

	return nil
}
