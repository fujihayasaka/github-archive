package merges

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/types"
	typesv2 "github.com/github/spokes-proto/gen/go/v2/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	repository = types.NewRepository(1)

	readmePath = types.NewPath([]byte("README.md"))
	mode       = types.NewMode(0o100_644)
	oid        = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	oid2       = types.NewObjectID("bb39a3ee5e6b4b0d3255bfef95601890afd80709")
	oid3       = types.NewObjectID("2fbf3466625ed033492d740cce89c9fd3dd2204e")
	resolution = &MergeConflict_TreeEntry{ Path: readmePath, Mode: mode, Oid: oid }
	committer  = typesv2.NewAttribution([]byte("A U Thor"), []byte("author@example.com"), time.Now())

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
					AbortQuietly:           false,
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
					AbortQuietly:           false,
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
					AbortQuietly:           false,
				},
			},
		},
		{
			"with include conflict details",
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
					AbortQuietly:           false,
				},
			},
		},
		{
			"with abort quietly",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithAbortQuietly(),
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
					AbortQuietly:           true,
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
					AbortQuietly:           false,
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
					AbortQuietly:           false,
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
			"with abort quietly",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithAbortQuietly(),
		},
		{
			"with abort quietly, no transaction_state",
			NewMergeTreesRequest(reqCtxWithoutTransaction, repository, mergeObjectSelector, mergeObjectSelector).WithAbortQuietly(),
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
		{
			"abort quietly with mergeability only",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithAbortQuietly().WithMergeabilityOnly(),
			"twirp error invalid_argument: options.abort_quietly cannot be used with mergeability_only or include_conflict_details",
		},
		{
			"abort quietly with include conflict details",
			NewMergeTreesRequest(reqCtx, repository, mergeObjectSelector, mergeObjectSelector).WithAbortQuietly().WithConflictDetails(),
			"twirp error invalid_argument: options.abort_quietly cannot be used with mergeability_only or include_conflict_details",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestRebaseRequest(t *testing.T) {
	var tests = []struct {
		name string
		actual *RebaseRequest
		expected *RebaseRequest
	}{
		{
			"base request",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer),
			&RebaseRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				HeadOid:        oid,
				BaseOid:        oid2,
				OntoOid:        oid2,
				Committer:      committer,
				DiffAlgorithm:  types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
				Options:        &RebaseRequest_RebaseOptions{
					MergeabilityOnly: false,
					CommitterOnly:    false,
				},
			},
		},
		{
			"with mergeability only",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithMergeabilityOnly(),
			&RebaseRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				HeadOid:        oid,
				BaseOid:        oid2,
				OntoOid:        oid2,
				Committer:      committer,
				DiffAlgorithm:  types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
				Options:        &RebaseRequest_RebaseOptions{
					MergeabilityOnly: true,
					CommitterOnly:    false,
				},
			},
		},
		{
			"with committer only",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithCommitterOnly(),
			&RebaseRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				HeadOid:        oid,
				BaseOid:        oid2,
				OntoOid:        oid2,
				Committer:      committer,
				DiffAlgorithm:  types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
				Options:        &RebaseRequest_RebaseOptions{
					MergeabilityOnly: false,
					CommitterOnly:    true,
				},
			},
		},
		{
			"with multiple options",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithMergeabilityOnly().WithCommitterOnly(),
			&RebaseRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				HeadOid:        oid,
				BaseOid:        oid2,
				OntoOid:        oid2,
				Committer:      committer,
				DiffAlgorithm:  types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
				Options:        &RebaseRequest_RebaseOptions{
					MergeabilityOnly: true,
					CommitterOnly:    true,
				},
			},
		},
		{
			"with diff algorithm",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithDiffAlgorithm(types.DiffAlgorithm_DIFF_ALGORITHM_INVALID), // Using invalid for testing only
			&RebaseRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				HeadOid:        oid,
				BaseOid:        oid2,
				OntoOid:        oid2,
				Committer:      committer,
				DiffAlgorithm:  types.DiffAlgorithm_DIFF_ALGORITHM_INVALID,
				Options:        &RebaseRequest_RebaseOptions{
					MergeabilityOnly: false,
					CommitterOnly:    false,
				},
			},
		},
		{
			"with onto oid",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithOntoOid(oid3),
			&RebaseRequest{
				RequestContext: reqCtx,
				Repository:     repository,
				HeadOid:        oid,
				BaseOid:        oid2,
				OntoOid:        oid3,
				Committer:      committer,
				DiffAlgorithm:  types.DiffAlgorithm_DIFF_ALGORITHM_DEFAULT,
				Options:        &RebaseRequest_RebaseOptions{
					MergeabilityOnly: false,
					CommitterOnly:    false,
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

func TestRebaseRequestValidate(t *testing.T) {
	var tests = []struct {
		name string
		req  *RebaseRequest
	}{
		{
			"base request",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer),
		},
		{
			"with mergeability only",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithMergeabilityOnly(),
		},
		{
			"with mergeability only, no transaction_state",
			NewRebaseRequest(reqCtxWithoutTransaction, repository, oid, oid2, committer).WithMergeabilityOnly(),
		},
		{
			"with committer only",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithCommitterOnly(),
		},
		{
			"with onto oid",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithOntoOid(oid3),
		},
		{
			"with multiple options",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithMergeabilityOnly().WithCommitterOnly(),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.req.Validate())
		})
	}
}

func TestRebaseRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *RebaseRequest
		err  string
	}{
		{
			"empty request",
			&RebaseRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewRebaseRequest(reqCtx, nil, oid, oid2, committer),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewRebaseRequest(reqCtx, types.NewRepository(0), oid, oid2, committer),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing transaction_state",
			NewRebaseRequest(reqCtxWithoutTransaction, repository, oid, oid2, committer),
			"twirp error invalid_argument: request_context.transaction_state is required",
		},
		{
			"missing head_oid",
			NewRebaseRequest(reqCtx, repository, nil, oid2, committer),
			"twirp error invalid_argument: head_oid is required",
		},
		{
			"invalid head_oid",
			NewRebaseRequest(reqCtx, repository, types.NewObjectID(""), oid2, committer),
			"twirp error invalid_argument: object_id.id is required",
		},
		{
			"missing base_oid",
			NewRebaseRequest(reqCtx, repository, oid, nil, committer),
			"twirp error invalid_argument: base_oid is required",
		},
		{
			"invalid base_oid",
			NewRebaseRequest(reqCtx, repository, oid, types.NewObjectID(""), committer),
			"twirp error invalid_argument: object_id.id is required",
		},
		{
			"invalid onto_oid",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithOntoOid(types.NewObjectID("")),
			"twirp error invalid_argument: object_id.id is required",
		},
		{
			"missing committer",
			NewRebaseRequest(reqCtx, repository, oid, oid2, nil),
			"twirp error invalid_argument: committer is required",
		},
		{
			"invalid committer",
			NewRebaseRequest(reqCtx, repository, oid, oid2, typesv2.NewAttribution(nil, nil, time.Time{})),
			"twirp error invalid_argument: attribution.name is required",
		},
		{
			"invalid diff_algorithm",
			NewRebaseRequest(reqCtx, repository, oid, oid2, committer).WithDiffAlgorithm(types.DiffAlgorithm_DIFF_ALGORITHM_INVALID),
			"twirp error invalid_argument: diff_algorithm is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}
