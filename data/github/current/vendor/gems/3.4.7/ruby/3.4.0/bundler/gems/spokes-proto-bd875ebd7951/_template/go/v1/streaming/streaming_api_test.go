package streaming

import (
	"fmt"
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
)

var (
	oid        = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	repository = types.NewRepository(1)
	reqCtx     = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestBatchBlobsRequest(t *testing.T) {
	manyObjectIds := func(n int) []*types.ObjectID {
		res := make([]*types.ObjectID, 0, n)
		for i := 0; i < n; i++ {
			res = append(res, types.NewObjectID(fmt.Sprintf("%040d", i)))
		}
		return res
	}

	t.Run("not valid", func(t *testing.T) {
		var notValid = []struct {
			name string
			req  *BatchBlobsRequest
			err  string
		}{
			{
				"empty",
				&BatchBlobsRequest{},
				"twirp error invalid_argument: repository is required",
			},
			{
				"missing repository",
				NewBatchBlobsRequest(reqCtx, nil, []*types.ObjectID{oid}),
				"twirp error invalid_argument: repository is required",
			},
			{
				"missing oids",
				NewBatchBlobsRequest(reqCtx, repository, nil),
				"twirp error invalid_argument: oids is required",
			},
			{
				"too many oids",
				NewBatchBlobsRequest(reqCtx, repository, manyObjectIds(1001)),
				"twirp error invalid_argument: oids may contain up to 1000 items",
			},
			{
				"max_size must be set if using content filters",
				NewBatchBlobsRequest(reqCtx, repository, manyObjectIds(10), WithUTF8Only()),
				"twirp error invalid_argument: filters.max_size must be set if using content filters",
			},
			{
				"max_size must be less than 1MiB if using content filters",
				NewBatchBlobsRequest(reqCtx, repository, manyObjectIds(10), WithMaxSize(1024*1024+1), WithUTF8Only()),
				"twirp error invalid_argument: filters.max_size cannot exceed 1MiB",
			},
			{
				"max_size must be less than 1MiB if using content filters",
				NewBatchBlobsRequest(reqCtx, repository, manyObjectIds(10), WithTruncation(1024), WithMaxSize(1024*1024), WithUTF8Only()),
				"twirp error invalid_argument: filters.truncate_at cannot be used with content filters",
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
			req  *BatchBlobsRequest
		}{
			{
				"one oid",
				NewBatchBlobsRequest(reqCtx, repository, []*types.ObjectID{oid}),
			},
			{
				"max oids",
				NewBatchBlobsRequest(reqCtx, repository, manyObjectIds(1000)),
			},
			{
				"one oid, filtered",
				NewBatchBlobsRequest(reqCtx, repository, []*types.ObjectID{oid}, WithTruncation(1024*1024)),
			},
			{
				"max oids, filtered",
				NewBatchBlobsRequest(reqCtx, repository, manyObjectIds(1000), WithTruncation(1024*1024)),
			},
			{
				"content filters ok with max_size",
				NewBatchBlobsRequest(reqCtx, repository, manyObjectIds(10), WithMaxSize(1024*1024), WithUTF8Only()),
			},
		}

		for _, tt := range valid {
			t.Run(tt.name, func(t *testing.T) {
				require.NoError(t, tt.req.Validate())
			})
		}
	})
}
