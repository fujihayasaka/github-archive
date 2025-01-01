package diffs

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/stretchr/testify/require"
)

var (
	oid1       = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	oid2       = types.NewObjectID("bb39a3ee5e6b4b0d3255bfef95601890afd80709")
	filepath1  = types.NewPath([]byte("my/path1"))
	filepath2  = types.NewPath([]byte("my/path2"))
	item1      = &SourcePathLineNumbers{SourcePath: filepath1, LineNumbers: []int64{1}}
	item2      = &SourcePathLineNumbers{SourcePath: filepath2, LineNumbers: []int64{2, 3}}
	items      = []*SourcePathLineNumbers{item1, item2}
	repository = types.NewRepository(1)
	reqCtx     = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestGetDiffPositionsRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *GetDiffPositionsRequest
		err  string
	}{
		{
			"empty",
			&GetDiffPositionsRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&GetDiffPositionsRequest{RequestContext: reqCtx, SourceOid: &selectors.RepoObjectIDSelector{Oid: oid1}, TargetOid: &selectors.RepoObjectIDSelector{Oid: oid2}, SourceItems: items},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing source_oid selector",
			&GetDiffPositionsRequest{RequestContext: reqCtx, Repository: repository, TargetOid: &selectors.RepoObjectIDSelector{Oid: oid2}, SourceItems: items},
			"twirp error invalid_argument: source_oid is required",
		},
		{
			"missing target_oid selector",
			&GetDiffPositionsRequest{RequestContext: reqCtx, Repository: repository, SourceOid: &selectors.RepoObjectIDSelector{Oid: oid1}, SourceItems: items},
			"twirp error invalid_argument: target_oid is required",
		},
		{
			"missing source_items selector",
			&GetDiffPositionsRequest{RequestContext: reqCtx, Repository: repository, SourceOid: &selectors.RepoObjectIDSelector{Oid: oid1}, TargetOid: &selectors.RepoObjectIDSelector{Oid: oid2}},
			"twirp error invalid_argument: line_numbers is required",
		},
		{
			"target_id matches source_id",
			&GetDiffPositionsRequest{RequestContext: reqCtx, Repository: repository, SourceOid: &selectors.RepoObjectIDSelector{Oid: oid1}, TargetOid: &selectors.RepoObjectIDSelector{Oid: oid1}, SourceItems: items},
			"twirp error invalid_argument: target_oid must be different from source_oid",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestGetDiffPositionsRequestValidate(t *testing.T) {
	req := NewGetDiffPositionsRequest(reqCtx, repository, &selectors.RepoObjectIDSelector{Oid: oid1}, &selectors.RepoObjectIDSelector{Oid: oid2}, item1, item2)
	require.NoError(t, req.Validate())
}
