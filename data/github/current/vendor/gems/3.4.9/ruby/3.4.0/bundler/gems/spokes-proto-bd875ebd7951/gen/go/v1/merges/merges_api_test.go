package merges

import (
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	repository = types.NewRepository(1)

	readmePath = types.NewPath([]byte("README.md"))
	mode       = types.NewMode(0o100_644)
	oid        = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	resolution = &MergeConflict_TreeEntry{ Path: readmePath, Mode: mode, Oid: oid }

	mergeObjectSelector = selectors.NewMergeObjectSelectorByOid(oid, nil)

	reqCtx                   = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE, types.WithTransactionState([]byte("transaction")))
	reqCtxWithoutTransaction = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestNewMergeTreesRequest(t *testing.T) {
	var tests = []struct {
		name     string
		actual   *MergeTreesRequest
		expected *MergeTreesRequest
	}{
		{
			"base request",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector),
			&MergeTreesRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				BaseSelector:   mergeObjectSelector,
				HeadSelector:   mergeObjectSelector,
				MergeBase: &MergeTreesRequest_MergeBaseNone{
					MergeBaseNone: &selectors.NoneSelector{},
				},
				Options: &MergeTreesRequest_MergeTreesOptions{
					MergeabilityOnly:       false,
					IncludeConflictDetails: false,
				},
			},
		},
		{
			"with merge base",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithMergeBase(mergeObjectSelector),
			&MergeTreesRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				BaseSelector:   mergeObjectSelector,
				HeadSelector:   mergeObjectSelector,
				MergeBase: &MergeTreesRequest_MergeBaseSelector{
					MergeBaseSelector: mergeObjectSelector,
				},
				Options: &MergeTreesRequest_MergeTreesOptions{
					MergeabilityOnly:       false,
					IncludeConflictDetails: false,
				},
			},
		},
		{
			"with mergeability only",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithMergeabilityOnly(),
			&MergeTreesRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				BaseSelector:   mergeObjectSelector,
				HeadSelector:   mergeObjectSelector,
				MergeBase: &MergeTreesRequest_MergeBaseNone{
					MergeBaseNone: &selectors.NoneSelector{},
				},
				Options: &MergeTreesRequest_MergeTreesOptions{
					MergeabilityOnly:       true,
					IncludeConflictDetails: false,
				},
			},
		},
		{
			"with skip conflict details",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithConflictDetails(),
			&MergeTreesRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				BaseSelector:   mergeObjectSelector,
				HeadSelector:   mergeObjectSelector,
				MergeBase: &MergeTreesRequest_MergeBaseNone{
					MergeBaseNone: &selectors.NoneSelector{},
				},
				Options: &MergeTreesRequest_MergeTreesOptions{
					MergeabilityOnly:       false,
					IncludeConflictDetails: true,
				},
			},
		},
		{
			"with resolutions",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithResolutions(resolution),
			&MergeTreesRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				BaseSelector:   mergeObjectSelector,
				HeadSelector:   mergeObjectSelector,
				MergeBase: &MergeTreesRequest_MergeBaseNone{
					MergeBaseNone: &selectors.NoneSelector{},
				},
				Options: &MergeTreesRequest_MergeTreesOptions{
					MergeabilityOnly:       false,
					IncludeConflictDetails: false,
				},
				Resolutions: []*MergeConflict_TreeEntry{
					resolution,
				},
			},
		},
		{
			"with multiple options",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithMergeBase(mergeObjectSelector).WithMergeabilityOnly(),
			&MergeTreesRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				BaseSelector:   mergeObjectSelector,
				HeadSelector:   mergeObjectSelector,
				MergeBase: &MergeTreesRequest_MergeBaseSelector{
					MergeBaseSelector: mergeObjectSelector,
				},
				Options: &MergeTreesRequest_MergeTreesOptions{
					MergeabilityOnly:       true,
					IncludeConflictDetails: false,
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Compare by string to get a useful diff
			require.Equal(t, prototext.Format(tt.expected), prototext.Format(tt.actual))
			require.True(t, proto.Equal(tt.expected, tt.actual), "formatted protobufs are equal, but objects are not")
		})
	}
}

func TestMergeTreesRequestValidate(t *testing.T) {
	var tests = []struct {
		name string
		req  *MergeTreesRequest
	}{
		{
			"base request",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector),
		},
		{
			"with merge base",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithMergeBase(mergeObjectSelector),
		},
		{
			"mergeability only",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithMergeabilityOnly(),
		},
		{
			"mergeability only, no transaction_state",
			NewMergeTreesRequest(reqCtxWithoutTransaction, repository, mergeObjectSelector, mergeObjectSelector).WithMergeabilityOnly(),
		},
		{
			"with conflict details",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithConflictDetails(),
		},
		{
			"with resolutions",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithResolutions(resolution),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.req.Validate())
		})
	}
}

func TestMergeTreesRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *MergeTreesRequest
		err  string
	}{
		{
			"empty",
			&MergeTreesRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewMergeTreesRequest(reqCtx, nil, mergeObjectSelector, mergeObjectSelector),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewMergeTreesRequest(reqCtx, &types.Repository{}, nil, nil),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing transaction_state",
			NewMergeTreesRequest(reqCtxWithoutTransaction, repository, mergeObjectSelector, mergeObjectSelector),
			"twirp error invalid_argument: request_context.transaction_state is required",
		},
		{
			"missing base_selector",
			NewMergeTreesRequest(reqCtx, repository, nil, mergeObjectSelector),
			"twirp error invalid_argument: base_selector is required",
		},
		{
			"invalid base_selector",
			NewMergeTreesRequest(reqCtx, repository, &selectors.MergeObjectSelector{}, mergeObjectSelector),
			"twirp error invalid_argument: merge_object_selector.object is required",
		},
		{
			"missing head_selector",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, nil),
			"twirp error invalid_argument: head_selector is required",
		},
		{
			"invalid head_selector",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, &selectors.MergeObjectSelector{}),
			"twirp error invalid_argument: merge_object_selector.object is required",
		},
		{
			"missing merge_base",
			&MergeTreesRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				BaseSelector:   mergeObjectSelector,
				HeadSelector:   mergeObjectSelector,
				MergeBase:      nil,
			},
			"twirp error invalid_argument: merge_base is required",
		},
		{
			"missing merge_base_selector",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithMergeBase(nil),
			"twirp error invalid_argument: merge_base.merge_base_selector is required",
		},
		{
			"invalid merge_base_selector",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithMergeBase(&selectors.MergeObjectSelector{}),
			"twirp error invalid_argument: merge_object_selector.object is required",
		},
		{
			"missing resolution entry",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithResolutions(nil),
			"twirp error invalid_argument: resolution is required",
		},
		{
			"invalid resolution entry",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithResolutions(&MergeConflict_TreeEntry{}),
			"twirp error invalid_argument: tree_entry.path is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}
