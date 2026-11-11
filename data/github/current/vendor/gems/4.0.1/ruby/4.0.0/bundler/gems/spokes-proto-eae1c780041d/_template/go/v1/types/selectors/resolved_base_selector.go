package selectors

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewResolvedBaseSelector() *ResolvedBaseSelector {
	return &ResolvedBaseSelector{}
}

func NewResolvedBaseSelectorWithObjectIDs(oid1, oid2 *types.ObjectID) *ResolvedBaseSelector {
	return &ResolvedBaseSelector{
		Oid1: &ResolvedBaseSelector_ObjectId1{ObjectId1: oid1},
		Oid2: &ResolvedBaseSelector_ObjectId2{ObjectId2: oid2},
	}
}

func NewResolvedBaseSelectorWithRepoObjectIDs(repoOid1, repoOid2 *RepoObjectIDSelector) *ResolvedBaseSelector {
	return &ResolvedBaseSelector{
		Oid1: &ResolvedBaseSelector_RepoObjectId1{RepoObjectId1: repoOid1},
		Oid2: &ResolvedBaseSelector_RepoObjectId2{RepoObjectId2: repoOid2},
	}
}

func (r *ResolvedBaseSelector) Validate() error {
	if r == nil {
		return nil
	}

	// Validate oid1 (required)
	switch {
	case r.GetObjectId1() != nil:
		if err := r.GetObjectId1().Validate(); err != nil {
			return err
		}
	case r.GetRepoObjectId1() != nil:
		if err := r.GetRepoObjectId1().Validate(); err != nil {
			return err
		}
	case r.GetRootSelector1() != nil:
		if err := r.GetRootSelector1().Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("oid1")
	}

	// Validate oid2 (required)
	switch {
	case r.GetObjectId2() != nil:
		if err := r.GetObjectId2().Validate(); err != nil {
			return err
		}
	case r.GetRepoObjectId2() != nil:
		if err := r.GetRepoObjectId2().Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("oid2")
	}

	// Validate base_oid (optional)
	switch {
	case r.GetBaseObjectId() != nil:
		if err := r.GetBaseObjectId().Validate(); err != nil {
			return err
		}
	case r.GetRepoBaseObjectId() != nil:
		if err := r.GetRepoBaseObjectId().Validate(); err != nil {
			return err
		}
	default: 
		// base_oid is optional, so it's okay if none is set
	}

	return nil
}
