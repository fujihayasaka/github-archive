package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewMergeObjectSelectorByOid(oid *types.ObjectID, repo *types.Repository) *MergeObjectSelector {
	return &MergeObjectSelector{
		Object: &MergeObjectSelector_ByOid{
			ByOid: oid,
		},
		SourceRepository: repo,
	}
}

func (sel *MergeObjectSelector) Validate() error {
	if sel == nil {
		return nil
	}

	if sel.GetObject() == nil {
		return twirp.RequiredArgumentError("merge_object_selector.object")
	}

	switch s := sel.GetObject().(type) {
	case *MergeObjectSelector_ByOid:
		if s.ByOid == nil {
			return twirp.RequiredArgumentError("merge_object_selector.by_oid")
		}
		if err := s.ByOid.Validate(); err != nil {
			return err
		}
	}

	if sel.GetSourceRepository() != nil {
		if err := sel.SourceRepository.Validate(); err != nil {
			return err
		}
	}

	return nil
}
