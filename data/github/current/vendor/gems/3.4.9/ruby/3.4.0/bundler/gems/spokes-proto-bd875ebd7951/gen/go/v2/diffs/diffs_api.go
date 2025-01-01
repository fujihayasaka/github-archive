package diffs

import (
	"fmt"

	twirp "github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/extensions"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

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
