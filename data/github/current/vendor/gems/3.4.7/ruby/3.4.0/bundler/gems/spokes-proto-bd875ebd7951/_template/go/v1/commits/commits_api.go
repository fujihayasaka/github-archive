package commits

import (
	"fmt"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/extensions"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

func NewCheckCommitReachabilityRequestWithObjectIDSelector(reqCtx *types.RequestContext, r *types.Repository, oids *selectors.ObjectIDSelector, cursor *types.Cursor) *CheckCommitReachabilityRequest {
	return &CheckCommitReachabilityRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &CheckCommitReachabilityRequest_ObjectIdSelector{ObjectIdSelector: oids},
		Cursor:         cursor,
	}
}

func (req *CheckCommitReachabilityRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetSelector() == nil {
		return twirp.RequiredArgumentError("selector")
	}

	switch s := req.GetSelector().(type) {
	case *CheckCommitReachabilityRequest_ObjectIdSelector:
		if s.ObjectIdSelector == nil {
			return twirp.RequiredArgumentError("selector.object_id_selector")
		}

		desc := req.ProtoReflect().Descriptor().Fields().ByName("object_id_selector")
		oidLimit := int(proto.GetExtension(desc.Options(), extensions.E_Limit).(uint32))
		oidCount := len(s.ObjectIdSelector.Oids)
		if oidLimit > 0 && oidCount > oidLimit {
			return twirp.InvalidArgumentError("selector.object_id_selector", fmt.Sprintf("may contain up to %d items", oidLimit))
		}

		if err := s.ObjectIdSelector.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func NewCountCommitsRequestWithObjectIDSelector(reqCtx *types.RequestContext, r *types.Repository, oids *selectors.ObjectIDSelector, filters *RevListFilters, limit uint64) *CountCommitsRequest {
	return &CountCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &CountCommitsRequest_ObjectIdSelector{ObjectIdSelector: oids},
		Filters:        filters,
		Limit:          limit,
	}
}

func NewCountCommitsRequestWithRevisionSelector(reqCtx *types.RequestContext, r *types.Repository, rvs *selectors.RevisionSelector, filters *RevListFilters, limit uint64) *CountCommitsRequest {
	return &CountCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &CountCommitsRequest_RevisionSelector{RevisionSelector: rvs},
		Filters:        filters,
		Limit:          limit,
	}
}

func NewCountCommitsRequestWithDistinctCommitsSelector(reqCtx *types.RequestContext, r *types.Repository, dcs *selectors.DistinctCommitsSelector, filters *RevListFilters, limit uint64) *CountCommitsRequest {
	return &CountCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &CountCommitsRequest_DistinctCommitsSelector{DistinctCommitsSelector: dcs},
		Filters:        filters,
		Limit:          limit,
	}
}

func NewListCommitsRequestWithObjectIDSelector(reqCtx *types.RequestContext, r *types.Repository, oids *selectors.ObjectIDSelector, cursor *types.Cursor) *ListCommitsRequest {
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_ObjectIdSelector{ObjectIdSelector: oids},
		Cursor:         cursor,
	}
}

func NewListCommitsRequestWithPushSelector(reqCtx *types.RequestContext, r *types.Repository, ps *selectors.PushSelector, cursor *types.Cursor) *ListCommitsRequest {
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_PushSelector{PushSelector: ps},
		Cursor:         cursor,
	}
}

func NewListCommitsRequestWithHistoricalPushSelector(reqCtx *types.RequestContext, r *types.Repository, hps *selectors.HistoricalPushSelector, cursor *types.Cursor) *ListCommitsRequest {
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_HistoricalPushSelector{HistoricalPushSelector: hps},
		Cursor:         cursor,
	}
}

func NewListCommitsRequestWithForkPushSelector(reqCtx *types.RequestContext, r *types.Repository, ps *selectors.ForkPushSelector, cursor *types.Cursor) *ListCommitsRequest {
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_ForkPushSelector{ForkPushSelector: ps},
		Cursor:         cursor,
	}
}

func NewListCommitsRequestWithUniversalSelector(reqCtx *types.RequestContext, r *types.Repository, cursor *types.Cursor) *ListCommitsRequest {
	us := selectors.NewUniversalSelector()
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_UniversalSelector{UniversalSelector: us},
		Cursor:         cursor,
	}
}

func NewListCommitsRequestWithRevisionSelector(reqCtx *types.RequestContext, r *types.Repository, rvs *selectors.RevisionSelector, cursor *types.Cursor) *ListCommitsRequest {
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_RevisionSelector{RevisionSelector: rvs},
		Cursor:         cursor,
	}
}

func NewListCommitsRequestWithRevisionAndPathSelector(reqCtx *types.RequestContext, r *types.Repository, rvaps *selectors.RevisionAndPathSelector, cursor *types.Cursor) *ListCommitsRequest {
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_RevisionAndPathSelector{RevisionAndPathSelector: rvaps},
		Cursor:         cursor,
	}
}

func NewListCommitsRequestWithQuarantineCommitsSelector(reqCtx *types.RequestContext, r *types.Repository, qs *selectors.QuarantineCommitsSelector, cursor *types.Cursor) *ListCommitsRequest {
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_QuarantineCommitsSelector{QuarantineCommitsSelector: qs},
		Cursor:         cursor,
	}
}

func NewListCommitsRequestWithDistinctCommitsSelector(reqCtx *types.RequestContext, r *types.Repository, dcs *selectors.DistinctCommitsSelector, cursor *types.Cursor) *ListCommitsRequest {
	return &ListCommitsRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Selector:       &ListCommitsRequest_DistinctCommitsSelector{DistinctCommitsSelector: dcs},
		Cursor:         cursor,
	}
}

func (req *ListCommitsRequest) WithFilters(filters *RevListFilters) *ListCommitsRequest {
	if req == nil {
		return nil
	}
	req.Filters = filters
	return req
}

func (req *CountCommitsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetSelector() == nil {
		return twirp.RequiredArgumentError("selector")
	}

	switch s := req.GetSelector().(type) {
	case *CountCommitsRequest_ObjectIdSelector:
		if s.ObjectIdSelector == nil {
			return twirp.RequiredArgumentError("selector.object_id_selector")
		}

		if err := s.ObjectIdSelector.Validate(); err != nil {
			return err
		}

	case *CountCommitsRequest_RevisionSelector:
		if s.RevisionSelector == nil {
			return twirp.RequiredArgumentError("selector.revision_selector")
		}

		if err := s.RevisionSelector.Validate(); err != nil {
			return err
		}

	case *CountCommitsRequest_DistinctCommitsSelector:
		if s.DistinctCommitsSelector == nil {
			return twirp.RequiredArgumentError("selector.distinct_commits_selector")
		}

		if err := s.DistinctCommitsSelector.Validate(); err != nil {
			return err
		}

		if req.GetFilters() != nil {
			return twirp.InvalidArgumentError("filters", "cannot be used with distinct_commits_selector")
		}
	}

	if err := req.GetFilters().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *ListCommitsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetSelector() == nil {
		return twirp.RequiredArgumentError("selector")
	}

	switch s := req.GetSelector().(type) {
	case *ListCommitsRequest_ObjectIdSelector:
		if s.ObjectIdSelector == nil {
			return twirp.RequiredArgumentError("selector.object_id_selector")
		}

		if err := s.ObjectIdSelector.Validate(); err != nil {
			return err
		}

	case *ListCommitsRequest_PushSelector:
		if s.PushSelector == nil {
			return twirp.RequiredArgumentError("selector.push_selector")
		}

		if err := s.PushSelector.Validate(); err != nil {
			return err
		}

	case *ListCommitsRequest_HistoricalPushSelector:
		if s.HistoricalPushSelector == nil {
			return twirp.RequiredArgumentError("selector.historical_push_selector")
		}

		if err := s.HistoricalPushSelector.Validate(); err != nil {
			return err
		}

	case *ListCommitsRequest_ForkPushSelector:
		if s.ForkPushSelector == nil {
			return twirp.RequiredArgumentError("selector.fork_push_selector")
		}

		if err := s.ForkPushSelector.Validate(); err != nil {
			return err
		}

	case *ListCommitsRequest_UniversalSelector:
		if err := s.UniversalSelector.Validate(); err != nil {
			return err
		}

	case *ListCommitsRequest_RevisionSelector:
		if s.RevisionSelector == nil {
			return twirp.RequiredArgumentError("selector.revision_selector")
		}

		if err := s.RevisionSelector.Validate(); err != nil {
			return err
		}

	case *ListCommitsRequest_RevisionAndPathSelector:
		if s.RevisionAndPathSelector == nil {
			return twirp.RequiredArgumentError("selector.revision_and_path_selector")
		}

		if req.GetFilters().GetPathspec() != nil && len(req.GetFilters().GetPathspec().GetItems()) > 0 {
			return twirp.InvalidArgumentError("pathspec", "cannot be used with revision_and_path_selector")
		}

		if err := s.RevisionAndPathSelector.Validate(); err != nil {
			return err
		}

	case *ListCommitsRequest_QuarantineCommitsSelector:
		if s.QuarantineCommitsSelector == nil {
			return twirp.RequiredArgumentError("selector.quarantine_commits_selector")
		}

		if req.GetRequestContext().GetTransactionState() == nil {
			return twirp.RequiredArgumentError("request_context.transaction_state")
		}

		if err := s.QuarantineCommitsSelector.Validate(); err != nil {
			return err
		}

	case *ListCommitsRequest_DistinctCommitsSelector:
		if s.DistinctCommitsSelector == nil {
			return twirp.RequiredArgumentError("selector.distinct_commits_selector")
		}

		if err := s.DistinctCommitsSelector.Validate(); err != nil {
			return err
		}

		if req.GetFilters() != nil {
			return twirp.InvalidArgumentError("filters", "cannot be used with distinct_commits_selector")
		}
	}

	if err := req.GetFilters().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *ListContributorsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetSelector() == nil {
		return twirp.RequiredArgumentError("selector")
	}

	switch s := req.GetSelector().(type) {
	case *ListContributorsRequest_PushSelector:
		if s.PushSelector == nil {
			return twirp.RequiredArgumentError("selector.push_selector")
		}

		if err := s.PushSelector.Validate(); err != nil {
			return err
		}
	case *ListContributorsRequest_HistoricalPushSelector:
		if s.HistoricalPushSelector == nil {
			return twirp.RequiredArgumentError("selector.historical_push_selector")
		}

		if err := s.HistoricalPushSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	return nil
}

func NewAheadBehindRequest(reqCtx *types.RequestContext, repository *types.Repository, base *types.Revision, tips []*types.Revision) *AheadBehindRequest {
	return &AheadBehindRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector: &AheadBehindRequest_BaseAndTipsSelector{
			BaseAndTipsSelector: &BaseAndTipsSelector{
				Base: base,
				Tips: tips,
			},
		},
	}
}

func (req *BaseAndTipsSelector) Validate() error {
	base := req.GetBase()
	if base == nil {
		return twirp.RequiredArgumentError("base")
	}

	if err := base.Validate(); err != nil {
		return err
	}

	tips := req.GetTips()
	if tips == nil {
		return twirp.RequiredArgumentError("tips")
	}

	for _, tip := range tips {
		if tip == nil {
			return twirp.RequiredArgumentError("tip")
		}
		if err := tip.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func (req *AheadBehindRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *AheadBehindRequest_BaseAndTipsSelector:
		if s.BaseAndTipsSelector == nil {
			return twirp.RequiredArgumentError("selector.base_and_tips_selector")
		}

		if err := s.BaseAndTipsSelector.Validate(); err != nil {
			return err
		}

	default:
		return twirp.RequiredArgumentError("selector")
	}

	return nil
}

func NewAheadBehindContainsRequest(reqCtx *types.RequestContext, repository *types.Repository, base *types.Revision, tips []*types.Revision) *AheadBehindContainsRequest {
	return &AheadBehindContainsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector: &AheadBehindContainsRequest_BaseAndTipsSelector{
			BaseAndTipsSelector: &BaseAndTipsSelector{
				Base: base,
				Tips: tips,
			},
		},
	}
}

func (req *AheadBehindContainsRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *AheadBehindContainsRequest_BaseAndTipsSelector:
		if s.BaseAndTipsSelector == nil {
			return twirp.RequiredArgumentError("selector.base_and_tips_selector")
		}

		if err := s.BaseAndTipsSelector.Validate(); err != nil {
			return err
		}

	default:
		return twirp.RequiredArgumentError("selector")
	}

	return nil
}

func NewBlameTreeRequest(reqCtx *types.RequestContext, repository *types.Repository, commit *types.Revision, path *types.Path, recursive bool) *BlameTreeRequest {
	return &BlameTreeRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector: &BlameTreeRequest_BlameTreeSelector{
			BlameTreeSelector: &BlameTreeSelector{
				Commit:    commit,
				Path:      path,
				Recursive: recursive,
			},
		},
	}
}

func (req *BlameTreeSelector) Validate() error {
	commit := req.GetCommit()
	if commit == nil {
		return twirp.RequiredArgumentError("commit")
	}

	if err := commit.Validate(); err != nil {
		return err
	}

	// Path is allowed to be nil, but if not nil, then
	// it must be valid (it has a non-nil name).
	path := req.GetPath()
	if path != nil {
		if err := path.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func (req *BlameTreeRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError(("repository"))
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *BlameTreeRequest_BlameTreeSelector:
		if s.BlameTreeSelector == nil {
			return twirp.RequiredArgumentError(("selector.blame_tree_selector"))
		}
		if err := s.BlameTreeSelector.Validate(); err != nil {
			return err
		}

	default:
		return twirp.RequiredArgumentError("selector")
	}

	return nil
}

func (filters *RevListFilters) Validate() error {
	if filters == nil {
		return nil
	}

	if err := filters.GetPathspec().Validate(); err != nil {
		return err
	}

	return nil
}

func NewDescribeRequestWithCommitishSelector(reqCtx *types.RequestContext, repository *types.Repository, ts *selectors.CommitishSelector) *DescribeRequest {
	return &DescribeRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &DescribeRequest_CommitishSelector{CommitishSelector: ts},
	}
}

func (dr *DescribeRequest) Validate() error {
	if dr == nil {
		return twirp.RequiredArgumentError("DescribeRequest")
	}

	if dr.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := dr.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := dr.GetSelector().(type) {
	case *DescribeRequest_CommitishSelector:
		if s.CommitishSelector == nil {
			return twirp.RequiredArgumentError("selector.commitish_selector")
		}

		if err := s.CommitishSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	return nil
}
