package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewTreeishSelector(treeish *types.Treeish) *TreeishSelector {
	return &TreeishSelector{Treeish: treeish}
}

func (t *TreeishSelector) Validate() error {
	if t == nil {
		return nil
	}

	if t.GetTreeish() == nil {
		return twirp.RequiredArgumentError("treeish")
	}

	if err := t.GetTreeish().Validate(); err != nil {
		return err
	}

	return nil
}
