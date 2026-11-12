package crawl

import (
	"context"
	"testing"
	"time"

	"github.com/cenkalti/backoff/v4"
	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/messages"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_LeaseExpiration(t *testing.T) {
	ctx := context.Background()

	servingTs := time.Now().UTC()

	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	cache.PublishCacheDocumentReturns(
		&cachepb.PublishCacheDocumentResponse{
			Published:     &cachepb.Published{Partition: 0, Offset: 0, AppendTime: servingTs.UnixMilli()},
			ServingStatus: &servingpb.ServingStatus{},
		},
		nil,
	)

	const workers = 1
	pool := NewWorkPool(ctx, indexerCluster, cacheClusters, workers, helpers.Corpus(t))
	defer pool.Close()

	msg := &messages.Ingest{
		Corpus:          corpus,
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLeaseFromUnixMilli(servingTs.Add(-1 * time.Minute).UnixMilli()),
	}
	oid := &gitaccess.BlobOIDChange{
		ObjectID:      helpers.UniqueOID(t),
		BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: "test/readme.txt"}},
	}

	renewLease := func() error {
		require.Fail(t, "this should not be called")
		return nil
	}

	tg := pool.NewTaskGroupWithBackOff(ctx, nil, &backoff.ZeroBackOff{}, renewLease)
	tg.EnqueueCachePublishTask(msg, oid)
	_, err = tg.Wait()
	require.Error(t, err)
	require.ErrorIs(t, err, ErrLeaseExpired)
}
