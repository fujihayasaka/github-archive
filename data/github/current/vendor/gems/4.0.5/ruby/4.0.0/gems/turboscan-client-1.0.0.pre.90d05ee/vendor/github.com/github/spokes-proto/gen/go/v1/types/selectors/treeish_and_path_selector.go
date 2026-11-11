package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewTreeishAndPathSelector(treeish *types.Treeish, path *types.Path) *TreeishAndPathSelector {
	return &TreeishAndPathSelector{Treeish: treeish, Path: path}
}

func (t *TreeishAndPathSelector) Validate() error {
	if t == nil {
		return nil
	}

	if t.GetTreeish() == nil {
		return twirp.RequiredArgumentError("treeish")
	}

	if t.GetPath() == nil {
		return twirp.RequiredArgumentError("path")
	}

	if err := t.GetTreeish().Validate(); err != nil {
		return err
	}

	if err := t.GetPath().Validate(); err != nil {
		return err
	}

	return nil
}
