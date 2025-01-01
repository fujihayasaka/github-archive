package merges

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
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

	if req.GetHeadOid() == nil {
		return twirp.RequiredArgumentError("head_oid")
	}

	if err := req.GetHeadOid().Validate(); err != nil {
		return err
	}

	if req.MergeBaseType == 0 {
		return twirp.RequiredArgumentError("merge_base_type")
	}

	return nil
}

func NewFindMergeBasesRequest(ctx *types.RequestContext, repo *types.Repository, oid1 *types.ObjectID, oid2 *types.ObjectID, mergeBaseType MergeBaseType) *FindMergeBasesRequest {
	return &FindMergeBasesRequest{
		Repository:     repo,
		RequestContext: ctx,
		BaseOid:        oid1,
		HeadOid:        oid2,
		MergeBaseType:  mergeBaseType,
	}
}
