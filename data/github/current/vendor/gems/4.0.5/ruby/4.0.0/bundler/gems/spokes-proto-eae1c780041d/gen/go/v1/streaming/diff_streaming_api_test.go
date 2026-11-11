package streaming

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

var (
	oid1     = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	oid2     = types.NewObjectID("bb39a3ee5e6b4b0d3255bfef95601890afd80709")
	baseRepo = types.NewRepository(2)

	rootSelector   = selectors.NewRootSelector()
	parentSelector = selectors.NewParentSelector()
)

func TestReadRawDiffRequest(t *testing.T) {
	t.Run("not valid", func(t *testing.T) {
		var notValid = []struct {
			name string
			req  *ReadRawDiffRequest
			err  string
		}{
			{
				"empty request",
				&ReadRawDiffRequest{},
				"twirp error invalid_argument: repository is required",
			},
			{
				"missing repository",
				&ReadRawDiffRequest{
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
					Mode:           ReadRawDiffRequest_DIFF_MODE_PATCH,
				},
				"twirp error invalid_argument: repository is required",
			},
			{
				"missing oid1",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
					Mode:           ReadRawDiffRequest_DIFF_MODE_PATCH,
				},
				"twirp error invalid_argument: oid1 is required",
			},
			{
				"missing oid1 object_id",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_ObjectId1{ObjectId1: nil},
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
					Mode:           ReadRawDiffRequest_DIFF_MODE_PATCH,
				},
				"twirp error invalid_argument: oid1.object_id is required",
			},
			{
				"missing oid2",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
					Mode:           ReadRawDiffRequest_DIFF_MODE_PATCH,
				},
				"twirp error invalid_argument: oid2 is required",
			},
			{
				"missing oid2 object_id",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: nil},
					Mode:           ReadRawDiffRequest_DIFF_MODE_PATCH,
				},
				"twirp error invalid_argument: oid2.object_id is required",
			},
			{
				"invalid mode",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
					Mode:           ReadRawDiffRequest_DIFF_MODE_INVALID,
				},
				"twirp error invalid_argument: mode is required",
			},
		}

		for _, tt := range notValid {
			t.Run(tt.name, func(t *testing.T) {
				require.EqualError(t, tt.req.Validate(), tt.err)
			})
		}
	})

	t.Run("valid", func(t *testing.T) {
		var valid = []struct {
			name string
			req  *ReadRawDiffRequest
		}{
			{
				"basic diff request",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
					FullIndex:      false,
					Mode:           ReadRawDiffRequest_DIFF_MODE_PATCH,
				},
			},
			{
				"diff with full index",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
					FullIndex:      true,
					Mode:           ReadRawDiffRequest_DIFF_MODE_DIFF,
				},
			},
			{
				"root diff request",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_RootSelector1{RootSelector1: rootSelector},
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
					FullIndex:      true,
					Mode:           ReadRawDiffRequest_DIFF_MODE_PATCH,
				},
			},
			{
				"parent diff request",
				&ReadRawDiffRequest{
					Repository:     repository,
					RequestContext: reqCtx,
					Oid1:           &ReadRawDiffRequest_ParentSelector1{ParentSelector1: parentSelector},
					Oid2:           &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
					FullIndex:      true,
					Mode:           ReadRawDiffRequest_DIFF_MODE_PATCH,
				},
			},
		}

		for _, tt := range valid {
			t.Run(tt.name, func(t *testing.T) {
				require.NoError(t, tt.req.Validate())
			})
		}
	})
}
