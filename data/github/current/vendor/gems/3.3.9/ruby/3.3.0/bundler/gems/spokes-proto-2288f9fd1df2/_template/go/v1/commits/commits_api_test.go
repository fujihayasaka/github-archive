package commits

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/stretchr/testify/require"
)

var (
	ref                            = types.NewReference([]byte("refs/heads/main"))
	oid                            = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refUpdate                      = types.NewReferenceUpdate(ref, oid, oid)
	objectIDSelector               = selectors.NewObjectIDSelector(oid)
	pushSelector                   = selectors.NewPushSelector([]*types.ReferenceUpdate{refUpdate})
	historicalPushSelector         = selectors.NewHistoricalPushSelector([]*types.ReferenceUpdate{refUpdate})
	forkPushSelector               = selectors.NewForkPushSelector(repository, []*types.ReferenceUpdate{refUpdate})
	invalidObjectIDSelector        = selectors.NewObjectIDSelector()
	invalidRevisionSelector        = selectors.NewRevisionSelector()
	invalidRevisionAndPathSelector = selectors.NewRevisionAndPathSelector(nil, nil)
	invalidPushSelector            = selectors.NewPushSelector([]*types.ReferenceUpdate{})
	invalidHistoricalPushSelector  = selectors.NewHistoricalPushSelector([]*types.ReferenceUpdate{})
	invalidForkPushSelector        = selectors.NewForkPushSelector(nil, []*types.ReferenceUpdate{})
	repository                     = types.NewRepository(1)
	base                           = types.NewRevision([]byte("main@{1.day.ago}"))
	tip1                           = types.NewRevision([]byte("main"))
	tip2                           = types.NewRevision([]byte("main@{2.days.ago}"))
	tips                           = []*types.Revision{tip1, tip2}
	reqCtx                         = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
	blamePath                      = types.NewPath([]byte("my/path"))
	revisionAndPathSelector        = selectors.NewRevisionAndPathSelector(tip1, blamePath)
	quarantineCommitsSelector      = selectors.NewQuarantineCommitsSelector()
	reqCtxWithPushState            = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE, types.WithPushState([]byte("push state")))
)

func TestCheckCommitReachabilityRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *CheckCommitReachabilityRequest
		err  string
	}{
		{
			"empty",
			&CheckCommitReachabilityRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&CheckCommitReachabilityRequest{RequestContext: reqCtx, Selector: &CheckCommitReachabilityRequest_ObjectIdSelector{ObjectIdSelector: objectIDSelector}},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing selector",
			&CheckCommitReachabilityRequest{RequestContext: reqCtx, Repository: repository},
			"twirp error invalid_argument: selector is required",
		},
		{
			"empty object id selector",
			&CheckCommitReachabilityRequest{RequestContext: reqCtx, Repository: repository, Selector: &CheckCommitReachabilityRequest_ObjectIdSelector{}},
			"twirp error invalid_argument: selector.object_id_selector is required",
		},
		{
			"invalid object id selector",
			NewCheckCommitReachabilityRequestWithObjectIDSelector(reqCtx, repository, invalidObjectIDSelector, nil),
			"twirp error invalid_argument: oids is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestCheckCommitReachabilityRequestValidate(t *testing.T) {
	req := NewCheckCommitReachabilityRequestWithObjectIDSelector(reqCtx, repository, objectIDSelector, nil)
	require.NoError(t, req.Validate())
}

func TestListCommitsRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *ListCommitsRequest
		err  string
	}{
		{
			"empty",
			&ListCommitsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&ListCommitsRequest{RequestContext: reqCtx, Selector: &ListCommitsRequest_PushSelector{PushSelector: pushSelector}},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing selector",
			&ListCommitsRequest{RequestContext: reqCtx, Repository: repository},
			"twirp error invalid_argument: selector is required",
		},
		{
			"empty object id selector",
			&ListCommitsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListCommitsRequest_ObjectIdSelector{}},
			"twirp error invalid_argument: selector.object_id_selector is required",
		},
		{
			"invalid object id selector",
			NewListCommitsRequestWithObjectIDSelector(reqCtx, repository, invalidObjectIDSelector, nil),
			"twirp error invalid_argument: oids is required",
		},
		{
			"empty push selector",
			&ListCommitsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListCommitsRequest_PushSelector{}},
			"twirp error invalid_argument: selector.push_selector is required",
		},
		{
			"invalid push selector",
			NewListCommitsRequestWithPushSelector(reqCtx, repository, invalidPushSelector, nil),
			"twirp error invalid_argument: reference_updates is required",
		},
		{
			"empty revision selector",
			&ListCommitsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListCommitsRequest_RevisionSelector{}},
			"twirp error invalid_argument: selector.revision_selector is required",
		},
		{
			"invalid revision selector",
			NewListCommitsRequestWithRevisionSelector(reqCtx, repository, invalidRevisionSelector, nil),
			"twirp error invalid_argument: revisions is required",
		},
		{
			"empty revision and path selector",
			&ListCommitsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListCommitsRequest_RevisionAndPathSelector{}},
			"twirp error invalid_argument: selector.revision_and_path_selector is required",
		},
		{
			"invalid revision and path selector",
			NewListCommitsRequestWithRevisionAndPathSelector(reqCtx, repository, invalidRevisionAndPathSelector, nil),
			"twirp error invalid_argument: revision is required",
		},
		{
			"empty fork push selector",
			&ListCommitsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListCommitsRequest_ForkPushSelector{}},
			"twirp error invalid_argument: selector.fork_push_selector is required",
		},
		{
			"invalid fork push selector",
			NewListCommitsRequestWithForkPushSelector(reqCtx, repository, invalidForkPushSelector, nil),
			"twirp error invalid_argument: base_repository is required",
		},
		{
			"empty historical push selector",
			&ListCommitsRequest{RequestContext: reqCtx, Repository: repository, Selector: &ListCommitsRequest_HistoricalPushSelector{}},
			"twirp error invalid_argument: selector.historical_push_selector is required",
		},
		{
			"invalid historical push selector",
			NewListCommitsRequestWithHistoricalPushSelector(reqCtx, repository, invalidHistoricalPushSelector, nil),
			"twirp error invalid_argument: reference_updates is required",
		},
		{
			"invalid quarantine commits selector",
			NewListCommitsRequestWithQuarantineCommitsSelector(reqCtx, repository, nil, nil),
			"twirp error invalid_argument: selector.quarantine_commits_selector is required",
		},
		{
			"missing push state with quarantine commits selector",
			NewListCommitsRequestWithQuarantineCommitsSelector(reqCtx, repository, quarantineCommitsSelector, nil),
			"twirp error invalid_argument: request_context.push_state is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestListCommitsRequestValidate(t *testing.T) {
	req := NewListCommitsRequestWithObjectIDSelector(reqCtx, repository, objectIDSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListCommitsRequestWithPushSelector(reqCtx, repository, pushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListCommitsRequestWithHistoricalPushSelector(reqCtx, repository, historicalPushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListCommitsRequestWithForkPushSelector(reqCtx, repository, forkPushSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListCommitsRequestWithUniversalSelector(reqCtx, repository, nil)
	require.NoError(t, req.Validate())

	req = NewListCommitsRequestWithRevisionAndPathSelector(reqCtx, repository, revisionAndPathSelector, nil)
	require.NoError(t, req.Validate())

	req = NewListCommitsRequestWithQuarantineCommitsSelector(reqCtxWithPushState, repository, quarantineCommitsSelector, nil)
	require.NoError(t, req.Validate())
}

func TestNewAheadBehindRequest(t *testing.T) {
	req := NewAheadBehindRequest(reqCtx, repository, base, tips)
	require.Equal(t, req, &AheadBehindRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector: &AheadBehindRequest_BaseAndTipsSelector{
			BaseAndTipsSelector: &BaseAndTipsSelector{
				Base: base,
				Tips: tips,
			},
		},
	})
}

func TestAheadBehindRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *AheadBehindRequest
		err  string
	}{
		{
			"empty",
			&AheadBehindRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewAheadBehindRequest(reqCtx, nil, base, tips),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewAheadBehindRequest(reqCtx, &types.Repository{}, base, tips),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing base",
			NewAheadBehindRequest(reqCtx, repository, nil, tips),
			"twirp error invalid_argument: base is required",
		},
		{
			"invalid base",
			NewAheadBehindRequest(reqCtx, repository, types.NewRevision(nil), tips),
			"twirp error invalid_argument: revision.name is required",
		},
		{
			"missing tips",
			NewAheadBehindRequest(reqCtx, repository, base, nil),
			"twirp error invalid_argument: tips is required",
		},
		{
			"nil tip",
			NewAheadBehindRequest(reqCtx, repository, base, []*types.Revision{nil}),
			"twirp error invalid_argument: tip is required",
		},
		{
			"invalid tip",
			NewAheadBehindRequest(reqCtx, repository, base, []*types.Revision{types.NewRevision(nil)}),
			"twirp error invalid_argument: revision.name is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestNewAheadBehindContainsRequest(t *testing.T) {
	req := NewAheadBehindContainsRequest(reqCtx, repository, base, tips)
	require.Equal(t, req, &AheadBehindContainsRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector: &AheadBehindContainsRequest_BaseAndTipsSelector{
			BaseAndTipsSelector: &BaseAndTipsSelector{
				Base: base,
				Tips: tips,
			},
		},
	})
}

func TestAheadBehindContainsRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *AheadBehindContainsRequest
		err  string
	}{
		{
			"empty",
			&AheadBehindContainsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewAheadBehindContainsRequest(reqCtx, nil, base, tips),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewAheadBehindContainsRequest(reqCtx, &types.Repository{}, base, tips),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing base",
			NewAheadBehindContainsRequest(reqCtx, repository, nil, tips),
			"twirp error invalid_argument: base is required",
		},
		{
			"invalid base",
			NewAheadBehindContainsRequest(reqCtx, repository, types.NewRevision(nil), tips),
			"twirp error invalid_argument: revision.name is required",
		},
		{
			"missing tips",
			NewAheadBehindContainsRequest(reqCtx, repository, base, nil),
			"twirp error invalid_argument: tips is required",
		},
		{
			"nil tip",
			NewAheadBehindContainsRequest(reqCtx, repository, base, []*types.Revision{nil}),
			"twirp error invalid_argument: tip is required",
		},
		{
			"invalid tip",
			NewAheadBehindContainsRequest(reqCtx, repository, base, []*types.Revision{types.NewRevision(nil)}),
			"twirp error invalid_argument: revision.name is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestNewBlameTreeRequest(t *testing.T) {
	req := NewBlameTreeRequest(reqCtx, repository, base, blamePath, false)
	require.Equal(t, req, &BlameTreeRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector: &BlameTreeRequest_BlameTreeSelector{
			BlameTreeSelector: &BlameTreeSelector{
				Commit:    base,
				Path:      blamePath,
				Recursive: false,
			},
		},
	})
	req = NewBlameTreeRequest(reqCtx, repository, base, blamePath, true)
	require.Equal(t, req, &BlameTreeRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector: &BlameTreeRequest_BlameTreeSelector{
			BlameTreeSelector: &BlameTreeSelector{
				Commit:    base,
				Path:      blamePath,
				Recursive: true,
			},
		},
	})
}

func TestBlameTreeRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *BlameTreeRequest
		err  string
	}{
		{
			"empty",
			&BlameTreeRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewBlameTreeRequest(reqCtx, nil, base, blamePath, false),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewBlameTreeRequest(reqCtx, &types.Repository{}, base, blamePath, false),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing base",
			NewBlameTreeRequest(reqCtx, repository, nil, blamePath, false),
			"twirp error invalid_argument: commit is required",
		},
		{
			"invalid base",
			NewBlameTreeRequest(reqCtx, repository, types.NewRevision(nil), blamePath, false),
			"twirp error invalid_argument: revision.name is required",
		},
		{
			"nil path",
			NewBlameTreeRequest(reqCtx, repository, base, types.NewPath(nil), false),
			"twirp error invalid_argument: path.name is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}
