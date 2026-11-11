package diffs

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	twirp "github.com/twitchtv/twirp"
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
	}

	if req.GetOid2() == nil {
		return twirp.RequiredArgumentError("oid2")
	}

	return nil
}

func NewReadDiffSummaryRequest(ctx *types.RequestContext, repo *types.Repository, oid1 *types.ObjectID, oid2 *types.ObjectID, baseOID *types.ObjectID, ignoreWhitespace bool, includeStat bool) *ReadDiffSummaryRequest {
	return &ReadDiffSummaryRequest{
		Repository:     repo,
		RequestContext: ctx,
		Oid1: &ReadDiffSummaryRequest_ObjectId1{
			ObjectId1: oid1,
		},
		Oid2:             oid2,
		BaseOid:          baseOID,
		DiffAlgorithm:    types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
		IgnoreWhitespace: ignoreWhitespace,
		IncludeStat:      includeStat,
	}
}

func NewReadDiffSummaryRequestWithRoot(ctx *types.RequestContext, repo *types.Repository, oid2 *types.ObjectID, baseOID *types.ObjectID, ignoreWhitespace bool, includeStat bool) *ReadDiffSummaryRequest {
	return &ReadDiffSummaryRequest{
		Repository:       repo,
		RequestContext:   ctx,
		Oid1:             &ReadDiffSummaryRequest_RootSelector1{},
		Oid2:             oid2,
		BaseOid:          baseOID,
		DiffAlgorithm:    types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
		IgnoreWhitespace: ignoreWhitespace,
		IncludeStat:      includeStat,
	}
}
