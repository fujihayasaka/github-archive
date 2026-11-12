
package streaming

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/twitchtv/twirp"
)

func NewReadRawDiffRequest(ctx *types.RequestContext, repo *types.Repository, oid1 *types.ObjectID, oid1base *types.Repository, oid2 *types.ObjectID, oid2base *types.Repository, fullIndex bool, mode ReadRawDiffRequest_DiffMode) *ReadRawDiffRequest {
	var oid1t isReadRawDiffRequest_Oid1
	var oid2t isReadRawDiffRequest_Oid2
	
	if oid1base == nil {
		oid1t = &ReadRawDiffRequest_ObjectId1{
			ObjectId1: oid1,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: oid1base,
			Oid:            oid1,
		}
		oid1t = &ReadRawDiffRequest_RepoObjectId1{
			RepoObjectId1: sel,
		}
	}
	
	if oid2base == nil {
		oid2t = &ReadRawDiffRequest_ObjectId2{
			ObjectId2: oid2,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: oid2base,
			Oid:            oid2,
		}
		oid2t = &ReadRawDiffRequest_RepoObjectId2{
			RepoObjectId2: sel,
		}
	}
	
	return &ReadRawDiffRequest{
		Repository:     repo,
		RequestContext: ctx,
		Oid1:           oid1t,
		Oid2:           oid2t,
		FullIndex:      fullIndex,
		Mode:           mode,
	}
}

func NewReadRawDiffRequestWithRoot(ctx *types.RequestContext, repo *types.Repository, oid2 *types.ObjectID, oid2base *types.Repository, fullIndex bool, mode ReadRawDiffRequest_DiffMode) *ReadRawDiffRequest {
	var oid2t isReadRawDiffRequest_Oid2
	
	if oid2base == nil {
		oid2t = &ReadRawDiffRequest_ObjectId2{
			ObjectId2: oid2,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: oid2base,
			Oid:            oid2,
		}
		oid2t = &ReadRawDiffRequest_RepoObjectId2{
			RepoObjectId2: sel,
		}
	}
	
	rs := selectors.NewRootSelector()

	return &ReadRawDiffRequest{
		Repository:     repo,
		RequestContext: ctx,
		Oid1:           &ReadRawDiffRequest_RootSelector1{RootSelector1: rs},
		Oid2:           oid2t,
		FullIndex:      fullIndex,
		Mode:           mode,
	}
}

func NewReadRawDiffRequestWithParent(ctx *types.RequestContext, repo *types.Repository, oid2 *types.ObjectID, oid2base *types.Repository, fullIndex bool, mode ReadRawDiffRequest_DiffMode) *ReadRawDiffRequest {
	var oid2t isReadRawDiffRequest_Oid2
	
	if oid2base == nil {
		oid2t = &ReadRawDiffRequest_ObjectId2{
			ObjectId2: oid2,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: oid2base,
			Oid:            oid2,
		}
		oid2t = &ReadRawDiffRequest_RepoObjectId2{
			RepoObjectId2: sel,
		}
	}

	ps := selectors.NewParentSelector()

	return &ReadRawDiffRequest{
		Repository:     repo,
		RequestContext: ctx,
		Oid1:           &ReadRawDiffRequest_ParentSelector1{ParentSelector1: ps},
		Oid2:           oid2t,
		FullIndex:      fullIndex,
		Mode:           mode,
	}
}

func (req *ReadRawDiffRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetOid1().(type) {
	case *ReadRawDiffRequest_ObjectId1:
		if s.ObjectId1 == nil {
			return twirp.RequiredArgumentError("oid1.object_id")
		}

		if err := s.ObjectId1.Validate(); err != nil {
			return err
		}
	case *ReadRawDiffRequest_RepoObjectId1:
		if s.RepoObjectId1.Oid == nil {
			return twirp.RequiredArgumentError("oid1.object_id")
		}

		if err := s.RepoObjectId1.Oid.Validate(); err != nil {
			return err
		}

		if s.RepoObjectId1.BaseRepository == nil {
			return twirp.RequiredArgumentError("oid1.base_repository")
		}

		if err := s.RepoObjectId1.BaseRepository.Validate(); err != nil {
			return err
		}
	case *ReadRawDiffRequest_RootSelector1:
		if err := s.RootSelector1.Validate(); err != nil {
			return err
		}
	case *ReadRawDiffRequest_ParentSelector1:
		if err := s.ParentSelector1.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("oid1")
	}

	switch s := req.GetOid2().(type) {
	case *ReadRawDiffRequest_ObjectId2:
		if s.ObjectId2 == nil {
			return twirp.RequiredArgumentError("oid2.object_id")
		}

		if err := s.ObjectId2.Validate(); err != nil {
			return err
		}
	case *ReadRawDiffRequest_RepoObjectId2:
		if s.RepoObjectId2.Oid == nil {
			return twirp.RequiredArgumentError("oid2.object_id")
		}

		if err := s.RepoObjectId2.Oid.Validate(); err != nil {
			return err
		}

		if s.RepoObjectId2.BaseRepository == nil {
			return twirp.RequiredArgumentError("oid2.base_repository")
		}

		if err := s.RepoObjectId2.BaseRepository.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("oid2")
	}

	if req.GetMode() == ReadRawDiffRequest_DIFF_MODE_INVALID {
		return twirp.RequiredArgumentError("mode")
	}

	return nil
}
