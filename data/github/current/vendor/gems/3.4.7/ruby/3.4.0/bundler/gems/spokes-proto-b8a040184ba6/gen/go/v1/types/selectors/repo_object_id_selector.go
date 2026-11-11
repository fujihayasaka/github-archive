package selectors

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewRepoObjectIDSelector(repo *types.Repository, oid *types.ObjectID) *RepoObjectIDSelector {
	return &RepoObjectIDSelector{BaseRepository: repo, Oid: oid}
}

func (o *RepoObjectIDSelector) Validate() error {
	if o == nil {
		return nil
	}

	if o.GetOid() == nil {
		return twirp.RequiredArgumentError("oid")
	}

	if err := o.GetOid().Validate(); err != nil {
		return err
	}

	if o.BaseRepository != nil {
		if err := o.BaseRepository.Validate(); err != nil {
			return err
		}
	}

	return nil
}
