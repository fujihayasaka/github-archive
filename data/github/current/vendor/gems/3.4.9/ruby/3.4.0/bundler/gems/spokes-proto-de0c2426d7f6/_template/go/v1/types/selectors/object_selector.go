package selectors

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewObjectSelectorByTreeishAndPath(treeish *types.Treeish, path *types.Path, symlinkResolution *ObjectSelector_TreeishAndPath_SymlinkResolution) *ObjectSelector {
	treeishAndPath := &ObjectSelector_TreeishAndPath{
		Treeish:           treeish,
		Path:              path,
		SymlinkResolution: symlinkResolution,
	}
	return &ObjectSelector{
		Object: &ObjectSelector_ByTreeishAndPath{ByTreeishAndPath: treeishAndPath},
	}
}

func NewObjectSelectorByTreeishAndPathAndType(treeish *types.Treeish, path *types.Path, objectType *types.ObjectType, symlinkResolution *ObjectSelector_TreeishAndPath_SymlinkResolution) *ObjectSelector {
	treeishAndPath := &ObjectSelector_TreeishAndPath{
		Treeish:           treeish,
		Path:              path,
		SymlinkResolution: symlinkResolution,
	}
	return &ObjectSelector{
		Object:     &ObjectSelector_ByTreeishAndPath{ByTreeishAndPath: treeishAndPath},
		ObjectType: objectType,
	}
}

func NewObjectSelectorByObjectID(oid *types.ObjectID) *ObjectSelector {
	return &ObjectSelector{
		Object: &ObjectSelector_ById{ById: oid},
	}
}

func NewObjectSelectorByObjectIDAndType(oid *types.ObjectID, objectType *types.ObjectType) *ObjectSelector {
	return &ObjectSelector{
		Object:     &ObjectSelector_ById{ById: oid},
		ObjectType: objectType,
	}
}
func NewObjectSelectorByRevision(revision *types.Revision) *ObjectSelector {
	return &ObjectSelector{
		Object: &ObjectSelector_ByName{ByName: revision},
	}
}

func NewObjectSelectorByRevisionAndType(revision *types.Revision, objectType *types.ObjectType) *ObjectSelector {
	return &ObjectSelector{
		Object:     &ObjectSelector_ByName{ByName: revision},
		ObjectType: objectType,
	}
}

func (o *ObjectSelector) Validate() error {
	if o.ObjectType != nil {
		if err := o.ObjectType.Validate(); err != nil {
			return err
		}
	}

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

	if symlinkResolution := tp.GetSymlinkResolution(); symlinkResolution != nil {
		maxDepth := symlinkResolution.GetMaxDepth()
		if maxDepth > 40 { // maxDepth is unsigned, so we only check the upper bound.
			return twirp.InvalidArgumentError("object_selector.symlink_resolution.max_depth", "must be between 0 and 40")
		}
	}

	return nil
}
