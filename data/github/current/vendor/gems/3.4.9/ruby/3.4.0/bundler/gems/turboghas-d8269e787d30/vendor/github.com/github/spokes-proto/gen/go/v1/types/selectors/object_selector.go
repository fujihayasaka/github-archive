package selectors

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewObjectSelectorByTreeishAndPath(treeish *types.Treeish, path *types.Path) *ObjectSelector {
	treeishAndPath := &ObjectSelector_TreeishAndPath{
		Treeish: treeish,
		Path:    path,
	}
	return &ObjectSelector{
		Object: &ObjectSelector_ByTreeishAndPath{ByTreeishAndPath: treeishAndPath},
	}
}

func NewObjectSelectorByObjectID(oid *types.ObjectID) *ObjectSelector {
	return &ObjectSelector{
		Object: &ObjectSelector_ById{ById: oid},
	}
}

func NewObjectSelectorByRevision(revision *types.Revision) *ObjectSelector {
	return &ObjectSelector{
		Object: &ObjectSelector_ByName{ByName: revision},
	}
}

func (o *ObjectSelector) Validate() error {
	switch {
	case o.GetByTreeishAndPath() != nil:
		if err := o.GetByTreeishAndPath().Validate(); err != nil {
			return err
		}
	case o.GetById() != nil:
		if err := o.GetById().Validate(); err != nil {
			return err
		}
	case o.GetByName() != nil:
		if err := o.GetByName().Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("object_selector.object")
	}

	return nil
}

func (tp *ObjectSelector_TreeishAndPath) Validate() error {
	treeish := tp.GetTreeish()
	if treeish == nil {
		return twirp.RequiredArgumentError("object_selector.treeish")
	}
	if err := treeish.Validate(); err != nil {
		return err
	}

	path := tp.GetPath()
	if path == nil {
		return twirp.RequiredArgumentError("object_selector.path")
	}
	if err := path.Validate(); err != nil {
		return err
	}

	return nil
}
