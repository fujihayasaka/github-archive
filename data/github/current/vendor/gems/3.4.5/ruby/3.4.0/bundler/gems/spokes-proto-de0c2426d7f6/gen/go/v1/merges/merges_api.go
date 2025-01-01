package merges

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	twirp "github.com/twitchtv/twirp"
)

func (req *FindMergeBasesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetBaseOid() == nil {
		return twirp.RequiredArgumentError("base_oid")
	}

	if err := req.GetBaseOid().Validate(); err != nil {
		return err
	}

	switch s := req.GetHeadOid().(type) {
	case *FindMergeBasesRequest_HeadObjectId:
		if s.HeadObjectId == nil {
			return twirp.RequiredArgumentError("head_oid.head_object_id")
		}
		if err := s.HeadObjectId.Validate(); err != nil {
			return err
		}
	case *FindMergeBasesRequest_RepoHeadObjectId:
		if s.RepoHeadObjectId == nil {
			return twirp.RequiredArgumentError("head_oid.repo_head_object_id")
		}
		if err := s.RepoHeadObjectId.Oid.Validate(); err != nil {
			return err
		}
	}

	if req.MergeBaseType == 0 {
		return twirp.RequiredArgumentError("merge_base_type")
	}

	return nil
}

func NewFindMergeBasesRequestWithHeadObjectId(ctx *types.RequestContext, repo *types.Repository, oid1 *types.ObjectID, oid2 *types.ObjectID, mergeBaseType MergeBaseType) *FindMergeBasesRequest {
	oid2t := &FindMergeBasesRequest_HeadObjectId{
		HeadObjectId: oid2,
	}

	return &FindMergeBasesRequest{
		Repository:     repo,
		RequestContext: ctx,
		BaseOid:        oid1,
		HeadOid:        oid2t,
		MergeBaseType:  mergeBaseType,
	}
}

func NewFindMergeBasesRequestWithRepoHeadObjectId(ctx *types.RequestContext, repo *types.Repository, oid1 *types.ObjectID, oid2 *types.ObjectID, oid2base *types.Repository, mergeBaseType MergeBaseType) *FindMergeBasesRequest {
	oid2t := &FindMergeBasesRequest_RepoHeadObjectId{
		RepoHeadObjectId: &selectors.RepoObjectIDSelector{
			BaseRepository: oid2base,
			Oid:            oid2,
		},
	}

	return &FindMergeBasesRequest{
		Repository:     repo,
		RequestContext: ctx,
		BaseOid:        oid1,
		HeadOid:        oid2t,
		MergeBaseType:  mergeBaseType,
	}
}
