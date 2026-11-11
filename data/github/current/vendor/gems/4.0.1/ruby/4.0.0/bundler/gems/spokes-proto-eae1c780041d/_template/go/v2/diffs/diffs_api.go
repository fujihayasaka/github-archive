package diffs

import (
	"fmt"

	twirp "github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/extensions"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	typesv2 "github.com/github/spokes-proto/gen/go/v2/types"
)

const maxDiffPatchSize = 10000

func (req *ReadDiffSummaryRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetOid1().(type) {
	case *ReadDiffSummaryRequest_ObjectId1:
		if s.ObjectId1 == nil {
			return twirp.RequiredArgumentError("oid1.object_id")
		}

		if err := s.ObjectId1.Validate(); err != nil {
			return err
		}
	case *ReadDiffSummaryRequest_RepoObjectId1:
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
	}

	switch s := req.GetOid2().(type) {
	case *ReadDiffSummaryRequest_ObjectId2:
		if s.ObjectId2 == nil {
			return twirp.RequiredArgumentError("oid2.object_id")
		}

		if err := s.ObjectId2.Validate(); err != nil {
			return err
		}
	case *ReadDiffSummaryRequest_RepoObjectId2:
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
	}

	switch s := req.GetBaseOid().(type) {
	case *ReadDiffSummaryRequest_BaseObjectId:
		if s.BaseObjectId == nil {
			return twirp.RequiredArgumentError("base_oid.object_id")
		}

		if err := s.BaseObjectId.Validate(); err != nil {
			return err
		}
	case *ReadDiffSummaryRequest_RepoBaseObjectId:
		if s.RepoBaseObjectId.Oid == nil {
			return twirp.RequiredArgumentError("base_oid.object_id")
		}

		if err := s.RepoBaseObjectId.Oid.Validate(); err != nil {
			return err
		}

		if s.RepoBaseObjectId.BaseRepository == nil {
			return twirp.RequiredArgumentError("base_oid.base_repository")
		}

		if err := s.RepoBaseObjectId.BaseRepository.Validate(); err != nil {
			return err
		}
	}

	if err := req.GetPathspec().Validate(); err != nil {
		return err
	}

	return nil
}

func NewReadDiffSummaryRequest(ctx *types.RequestContext, repo *types.Repository, oid1 *types.ObjectID, oid1base *types.Repository, oid2 *types.ObjectID, oid2base *types.Repository, baseOID *types.ObjectID, baseoidbase *types.Repository, ignoreWhitespace bool, includeStat bool) *ReadDiffSummaryRequest {
	var oid1t isReadDiffSummaryRequest_Oid1
	var oid2t isReadDiffSummaryRequest_Oid2
	var oidbaset isReadDiffSummaryRequest_BaseOid
	if oid1base == nil {
		oid1t = &ReadDiffSummaryRequest_ObjectId1{
			ObjectId1: oid1,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: oid1base,
			Oid:            oid1,
		}
		oid1t = &ReadDiffSummaryRequest_RepoObjectId1{
			RepoObjectId1: sel,
		}
	}
	if oid2base == nil {
		oid2t = &ReadDiffSummaryRequest_ObjectId2{
			ObjectId2: oid2,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: oid2base,
			Oid:            oid2,
		}
		oid2t = &ReadDiffSummaryRequest_RepoObjectId2{
			RepoObjectId2: sel,
		}
	}
	if baseOID == nil {
		oidbaset = &ReadDiffSummaryRequest_NoneBase{
			NoneBase: nil,
		}
	} else if baseoidbase == nil {
		oidbaset = &ReadDiffSummaryRequest_BaseObjectId{
			BaseObjectId: baseOID,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: baseoidbase,
			Oid:            baseOID,
		}
		oidbaset = &ReadDiffSummaryRequest_RepoBaseObjectId{
			RepoBaseObjectId: sel,
		}
	}
	return &ReadDiffSummaryRequest{
		Repository:       repo,
		RequestContext:   ctx,
		Oid1:             oid1t,
		Oid2:             oid2t,
		BaseOid:          oidbaset,
		DiffAlgorithm:    types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
		IgnoreWhitespace: ignoreWhitespace,
		IncludeStat:      includeStat,
	}
}

func NewReadDiffSummaryRequestWithRoot(ctx *types.RequestContext, repo *types.Repository, oid2 *types.ObjectID, oid2base *types.Repository, baseOID *types.ObjectID, baseoidbase *types.Repository, ignoreWhitespace bool, includeStat bool) *ReadDiffSummaryRequest {
	var oid2t isReadDiffSummaryRequest_Oid2
	var oidbaset isReadDiffSummaryRequest_BaseOid
	if oid2base == nil {
		oid2t = &ReadDiffSummaryRequest_ObjectId2{
			ObjectId2: oid2,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: oid2base,
			Oid:            oid2,
		}
		oid2t = &ReadDiffSummaryRequest_RepoObjectId2{
			RepoObjectId2: sel,
		}
	}
	if baseOID == nil {
		oidbaset = &ReadDiffSummaryRequest_NoneBase{
			NoneBase: nil,
		}
	} else if baseoidbase == nil {
		oidbaset = &ReadDiffSummaryRequest_BaseObjectId{
			BaseObjectId: baseOID,
		}
	} else {
		sel := &selectors.RepoObjectIDSelector{
			BaseRepository: baseoidbase,
			Oid:            baseOID,
		}
		oidbaset = &ReadDiffSummaryRequest_RepoBaseObjectId{
			RepoBaseObjectId: sel,
		}
	}
	return &ReadDiffSummaryRequest{
		Repository:       repo,
		RequestContext:   ctx,
		Oid1:             &ReadDiffSummaryRequest_RootSelector1{},
		Oid2:             oid2t,
		BaseOid:          oidbaset,
		DiffAlgorithm:    types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
		IgnoreWhitespace: ignoreWhitespace,
		IncludeStat:      includeStat,
	}
}

func (req *ReadDiffSummaryRequest) WithPathspec(pathspec *types.Pathspec) *ReadDiffSummaryRequest {
	req.Pathspec = pathspec
	return req
}

func NewGetDiffPositionsRequest(reqCtx *types.RequestContext, r *types.Repository, sourceOid *selectors.RepoObjectIDSelector, targetOid *selectors.RepoObjectIDSelector, items ...*SourcePathLineNumbers) *GetDiffPositionsRequest {
	return &GetDiffPositionsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		SourceOid:      sourceOid,
		TargetOid:      targetOid,
		SourceItems:    items,
	}
}

func (obj *SourcePathLineNumbers) Validate() error {
	if obj.GetSourcePath() == nil {
		return twirp.RequiredArgumentError("source_path")
	}

	if err := obj.GetSourcePath().Validate(); err != nil {
		return err
	}

	lineNumItems := obj.GetLineNumbers()

	if len(lineNumItems) < 1 {
		return twirp.RequiredArgumentError("line_number")
	}

	for _, item := range lineNumItems {
		if item < 0 {
			return twirp.InvalidArgumentError("line_number", "must be greater than or equal to 0")
		}
	}

	return nil
}

func (req *GetDiffPositionsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetSourceOid() == nil {
		return twirp.RequiredArgumentError("source_oid")
	}

	if req.GetTargetOid() == nil {
		return twirp.RequiredArgumentError("target_oid")
	}

	if err := req.GetSourceOid().Validate(); err != nil {
		return err
	}

	if err := req.GetTargetOid().Validate(); err != nil {
		return err
	}

	if req.GetSourceOid().GetOid().GetId() == req.GetTargetOid().GetOid().GetId() {
		return twirp.InvalidArgumentError("target_oid", "must be different from source_oid")
	}

	items := req.GetSourceItems()
	totalLineNumItems := 0

	for _, item := range items {
		if item == nil {
			return twirp.RequiredArgumentError("source_item")
		} else if err := item.Validate(); err != nil {
			return err
		}
		totalLineNumItems += len(item.GetLineNumbers())
	}

	desc := req.ProtoReflect().Descriptor().Fields().ByName("source_items")
	limit := int(proto.GetExtension(desc.Options(), extensions.E_Limit).(uint32))

	if totalLineNumItems < 1 {
		return twirp.RequiredArgumentError("line_numbers")
	} else if totalLineNumItems > limit {
		return twirp.InvalidArgumentError("line_numbers", fmt.Sprintf("may contain up to %d line number requests across all requested paths", limit))
	}

	return nil
}

// Convenience function for creating a TargetPathLineNumbers result.
func NewTargetPathLineNumbers(source_path string, target_path string, lineNumbers ...*LineNumberMapping) *TargetPathLineNumbers {
	return &TargetPathLineNumbers{
		SourcePath:  types.NewPath([]byte(source_path)),
		TargetPath:  types.NewPath([]byte(target_path)),
		LineNumbers: lineNumbers,
	}
}

// Convenience function for creating a TargetPathLineNumbers result with a deleted file.
func NewTargetPathLineNumbersDeleted(source_path string) *TargetPathLineNumbers {
	return &TargetPathLineNumbers{
		SourcePath:  types.NewPath([]byte(source_path)),
		TargetPath:  types.NewPath([]byte("")),
		LineNumbers: []*LineNumberMapping{},
	}
}

// Validate the ReadDiffPairsRequest.
func (req *ReadDiffPairsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}
	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	// Validate the oneof pairs field
	switch p := req.GetPairs().(type) {
	case *ReadDiffPairsRequest_DiffDeltas:
		if p.DiffDeltas == nil {
			return twirp.RequiredArgumentError("pairs.diff_deltas")
		}

		// First validate the DiffDeltaSelector structure (length, nil checks)
		if len(p.DiffDeltas.DiffDeltaList) == 0 {
			return twirp.RequiredArgumentError("pairs.diff_deltas.diff_delta_list")
		} else if len(p.DiffDeltas.DiffDeltaList) > 10000 {
			return twirp.InvalidArgumentError("pairs.diff_deltas.diff_delta_list", fmt.Sprintf("maximum of %d diff deltas allowed, got %d", 10000, len(p.DiffDeltas.DiffDeltaList)))
		}

	case nil:
		return twirp.RequiredArgumentError("pairs")
	default:
		return twirp.InvalidArgumentError("pairs", "unknown pairs type")
	}

	// Validate optional resolved base selector if provided
	if req.GetResolvedBaseSelector() != nil {
		if err := req.GetResolvedBaseSelector().Validate(); err != nil {
			return err
		}
	}

	return nil
}

func (req *ReadDiffPairsRequest) WithCursor(cursor *types.Cursor) *ReadDiffPairsRequest {
	req.Cursor = cursor
	return req
}

// NewReadDiffPairsRequest creates a request to read diff pairs from diff deltas.
func NewReadDiffPairsRequest(
	repository *types.Repository,
	requestContext *types.RequestContext,
	diffDeltas *DiffDeltaSelector,
	resolvedBaseSelector *selectors.ResolvedBaseSelector,
	options *ReadDiffPairsOptions) (*ReadDiffPairsRequest, error) {

	req := &ReadDiffPairsRequest{
		Repository:           repository,
		RequestContext:       requestContext,
		Pairs:                &ReadDiffPairsRequest_DiffDeltas{DiffDeltas: diffDeltas},
		ResolvedBaseSelector: resolvedBaseSelector,
		Options:              options,
	}

	if err := req.Validate(); err != nil {
		return nil, err
	}

	return req, nil
}

// NewReadDiffPairsRequestWithResolvedBaseSelector creates a ReadDiffPairsRequest with a ResolvedBase selector.
func NewReadDiffPairsRequestWithResolvedBaseSelector(
	repository *types.Repository,
	requestContext *types.RequestContext,
	diffDeltas *DiffDeltaSelector,
	resolvedBaseSelector *selectors.ResolvedBaseSelector,
	options *ReadDiffPairsOptions) (*ReadDiffPairsRequest, error) {

	return NewReadDiffPairsRequest(repository, requestContext, diffDeltas, resolvedBaseSelector, options)
}

// NewReadDiffPairsRequestWithoutBase creates a ReadDiffPairsRequest without a base selector.
func NewReadDiffPairsRequestWithoutBase(
	repository *types.Repository,
	requestContext *types.RequestContext,
	diffDeltas *DiffDeltaSelector,
	options *ReadDiffPairsOptions) (*ReadDiffPairsRequest, error) {

	return NewReadDiffPairsRequest(repository, requestContext, diffDeltas, nil, options)
}

func (req *GetDiffAppliableRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetCommitOid() == nil {
		return twirp.RequiredArgumentError("commit_oid")
	}

	if err := req.GetCommitOid().Validate(); err != nil {
		return err
	}

	if len(req.GetDiffPatch()) == 0 {
		return twirp.RequiredArgumentError("diff_patch")
	}

	if len(req.GetDiffPatch()) > maxDiffPatchSize {
		return twirp.InvalidArgumentError("diff_patch", fmt.Sprintf("cannot exceed %d bytes", maxDiffPatchSize))
	}

	return nil
}

func NewGetDiffAppliableRequest(ctx *types.RequestContext, repo *types.Repository, commitOID *types.ObjectID, diffPatch []byte) *GetDiffAppliableRequest {
	return &GetDiffAppliableRequest{
		Repository:     repo,
		RequestContext: ctx,
		CommitOid:      commitOID,
		DiffPatch:      diffPatch,
	}
}

func NewCreateCommitFromDiffRequest(
	ctx *types.RequestContext,
	repo *types.Repository,
	diffPatch []byte,
	baseOID *types.ObjectID,
	author *typesv2.Attribution,
	committer *typesv2.Attribution,
	message []byte,
) *CreateCommitFromDiffRequest {
	return &CreateCommitFromDiffRequest{
		Repository:     repo,
		RequestContext: ctx,
		DiffPatch:      diffPatch,
		BaseOid:        baseOID,
		Author:         author,
		Committer:      committer,
		Message:        message,
	}
}

func (req *CreateCommitFromDiffRequest) Validate() error {
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

	if req.GetRequestContext() == nil {
		return twirp.RequiredArgumentError("request_context")
	}

	if req.GetRequestContext().GetTransactionState() == nil {
		return twirp.RequiredArgumentError("request_context.transaction_state")
	}

	if len(req.GetDiffPatch()) == 0 {
		return twirp.RequiredArgumentError("diff_patch")
	}

	if len(req.GetDiffPatch()) > maxDiffPatchSize {
		return twirp.InvalidArgumentError("diff_patch", fmt.Sprintf("cannot exceed %d bytes", maxDiffPatchSize))
	}

	if req.GetAuthor() == nil {
		return twirp.RequiredArgumentError("author")
	}

	if err := req.GetAuthor().Validate(); err != nil {
		return err
	}

	if req.GetCommitter() == nil {
		return twirp.RequiredArgumentError("committer")
	}

	if err := req.GetCommitter().Validate(); err != nil {
		return err
	}

	return nil
}

func (resp *CreateCommitFromDiffResponse) SetTransactionContext(transactionContext *types.TransactionContext) {
	if resp != nil {
		resp.TransactionContext = transactionContext
	}
}
