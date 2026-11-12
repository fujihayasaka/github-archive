package merges

import (
	"google.golang.org/protobuf/types/known/emptypb"

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

func NewMergeTreesRequest(
	reqCtx *types.RequestContext,
	repository *types.Repository,
	base *selectors.MergeObjectSelector,
	head *selectors.MergeObjectSelector) *MergeTreesRequest {
	req := &MergeTreesRequest{
		Repository:     repository,
		RequestContext: reqCtx,
		BaseSelector:   base,
		HeadSelector:   head,
		MergeBase: &MergeTreesRequest_MergeBaseNone{
			MergeBaseNone: &selectors.NoneSelector{},
		},
		Options: &MergeTreesRequest_MergeTreesOptions{},
	}

	return req
}

func (req *MergeTreesRequest) WithMergeBase(mergeBase *selectors.MergeObjectSelector) *MergeTreesRequest {
	req.MergeBase = &MergeTreesRequest_MergeBaseSelector{
		MergeBaseSelector: mergeBase,
	}
	return req
}

func (req *MergeTreesRequest) WithMergeabilityOnly() *MergeTreesRequest {
	if req.Options == nil {
		req.Options = &MergeTreesRequest_MergeTreesOptions{}
	}
	req.Options.MergeabilityOnly = true
	return req
}

func (req *MergeTreesRequest) WithConflictDetails() *MergeTreesRequest {
	if req.Options == nil {
		req.Options = &MergeTreesRequest_MergeTreesOptions{}
	}
	req.Options.IncludeConflictDetails = true
	return req
}

func (req *MergeTreesRequest) WithResolutions(resolutions ...*MergeConflict_TreeEntry) *MergeTreesRequest {
	req.Resolutions = resolutions
	return req
}

func (req *MergeTreesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	// Require a transaction only if we're writing objects.
	if !req.GetOptions().GetMergeabilityOnly() &&
		req.GetRequestContext().GetTransactionState() == nil {
		return twirp.RequiredArgumentError("request_context.transaction_state")
	}

	// base_selector
	if req.GetBaseSelector() == nil {
		return twirp.RequiredArgumentError("base_selector")
	}

	if err := req.BaseSelector.Validate(); err != nil {
		return err
	}

	// head_selector
	if req.GetHeadSelector() == nil {
		return twirp.RequiredArgumentError("head_selector")
	}

	if err := req.HeadSelector.Validate(); err != nil {
		return err
	}

	// merge_base
	if req.GetMergeBase() == nil {
		return twirp.RequiredArgumentError("merge_base")
	}

	switch s := req.GetMergeBase().(type) {
	case *MergeTreesRequest_MergeBaseSelector:
		if s.MergeBaseSelector == nil {
			return twirp.RequiredArgumentError("merge_base.merge_base_selector")
		}
		if err := s.MergeBaseSelector.Validate(); err != nil {
			return err
		}
	}

	// resolutions
	for _, resolution := range req.GetResolutions() {
		if resolution == nil {
			return twirp.RequiredArgumentError("resolution")
		}

		if err := resolution.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func (req *MergeConflict_TreeEntry) Validate() error {
	if req.GetPath() == nil {
		return twirp.RequiredArgumentError("tree_entry.path")
	}

	if err := req.GetPath().Validate(); err != nil {
		return err
	}

	if req.GetOid() == nil {
		return twirp.RequiredArgumentError("tree_entry.oid")
	}

	if err := req.GetOid().Validate(); err != nil {
		return err
	}

	return nil
}

func NewMergeTreesResponseOidResult(status MergeTreesResponse_Status, oid *types.ObjectID) *MergeTreesResponse {
	return &MergeTreesResponse{
		MergeStatus: status,
		Result: &MergeTreesResponse_Oid{
			Oid: oid,
		},
	}
}

func NewMergeTreesResponseConflictResult(status MergeTreesResponse_Status, conflicts []*MergeConflict) *MergeTreesResponse {
	return &MergeTreesResponse{
		MergeStatus: status,
		Result: &MergeTreesResponse_Conflicts{
			Conflicts: &MergeTreesResponse_MergeConflictResult{
				Entries: conflicts,
			},
		},
	}
}

func NewMergeTreesResponseNoneResult(status MergeTreesResponse_Status) *MergeTreesResponse {
	return &MergeTreesResponse{
		MergeStatus: status,
		Result: &MergeTreesResponse_None{
			None: &emptypb.Empty{},
		},
	}
}

func (resp *MergeTreesResponse) SetTransactionContext(transactionContext *types.TransactionContext) {
	if resp != nil {
		resp.TransactionContext = transactionContext
	}
}
