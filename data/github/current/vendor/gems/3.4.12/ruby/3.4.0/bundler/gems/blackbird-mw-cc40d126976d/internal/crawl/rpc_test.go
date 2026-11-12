package crawl

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/blackbird/crates/client/pkg/blackbird"
	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	blackbirdpb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_publishGitDocumentWithRetries(t *testing.T) {
	const (
		retries = 1
		hosts   = 1
	)
	ctx := context.Background()
	req := &cachepb.PublishCacheDocumentRequest{
		GitDocument: &blackbirdpb.GitDocument{
			ContentSha: helpers.UniqueOID(t).Bytes(),
			Locations: []*entities.Location{{
				Path:   "readme.txt",
				Change: entities.Location_CHANGE_ADDED,
			}},
		},
		NumShards: uint32(hosts),
	}

	t.Run("too large is does not retry", func(t *testing.T) {
		topic := routing.DocumentTopic{Partitions: hosts}

		indexerCluster := helpers.IndexerCluster(t)
		cacheClusters := helpers.CacheClusters(t)
		client, err := cacheClusters.ClientForCluster(routing.CacheClusterNames[0])
		require.NoError(t, err)
		cacheAPI := helpers.FakeCacheAPI(t, client, 0)
		cacheAPI.PublishCacheDocumentReturns(nil, errors.New("kafka message was too large"))

		res, err := publishGitDocumentWithRetries(ctx, indexerCluster, cacheClusters, req, topic, retry.DefaultBackOff(ctx, retries))
		require.Error(t, err)
		require.ErrorIs(t, err, ErrMessageSizeTooLarge)
		require.Nil(t, res)
		require.Equal(t, 1, cacheAPI.PublishCacheDocumentCallCount(), "should only be called once and then fail")
	})

	t.Run("no hosts retries", func(t *testing.T) {
		indexerCluster := helpers.IndexerCluster(t)
		cacheClusters := helpers.CacheClusters(t)
		client, err := cacheClusters.ClientForCluster(routing.CacheClusterNames[0])
		require.NoError(t, err)
		fakeClient := helpers.FakeClient(t, client)
		fakeClient.RoutesReturns(blackbird.Routes{}) // no hosts

		res, err := publishGitDocumentWithRetries(ctx, indexerCluster, cacheClusters, req, routing.DocumentTopic{}, retry.DefaultBackOff(ctx, retries))
		require.Error(t, err)
		require.ErrorContains(t, err, "no cache hosts found")
		require.Nil(t, res)
		require.Equal(t, retries+1, fakeClient.RoutesCallCount())
	})

	t.Run("NumShards greater than cache's shards publishes", func(t *testing.T) {
		indexerCluster := helpers.IndexerCluster(t)
		cacheClusters := helpers.CacheClusters(t)
		client, err := cacheClusters.ClientForCluster(routing.CacheClusterNames[0])
		require.NoError(t, err)
		cacheAPI := helpers.FakeCacheAPI(t, client, 0)
		cacheAPI.PublishCacheDocumentReturns(
			&cachepb.PublishCacheDocumentResponse{
				Published: &cachepb.Published{
					Partition:  0,
					Offset:     1,
					AppendTime: time.Now().UnixMilli(),
				},
				ServingStatus: &servingpb.ServingStatus{},
			},
			nil,
		)

		req := &cachepb.PublishCacheDocumentRequest{
			GitDocument: &blackbirdpb.GitDocument{
				ContentSha: helpers.UniqueOID(t).Bytes(),
				Locations: []*entities.Location{{
					Path:   "readme.txt",
					Change: entities.Location_CHANGE_ADDED,
				}},
			},
			NumShards: uint32(hosts + 1),
		}

		topic := routing.DocumentTopic{Partitions: hosts + 1}

		res, err := publishGitDocumentWithRetries(ctx, indexerCluster, cacheClusters, req, topic, retry.DefaultBackOff(ctx, retries))
		require.NoError(t, err)
		require.NotNil(t, res)
		require.Equal(t, 1, cacheAPI.PublishCacheDocumentCallCount())
	})

	t.Run("RPC error retries", func(t *testing.T) {
		topic := routing.DocumentTopic{Partitions: hosts}

		indexerCluster := helpers.IndexerCluster(t)
		cacheClusters := helpers.CacheClusters(t)
		client, err := cacheClusters.ClientForCluster(routing.CacheClusterNames[0])
		require.NoError(t, err)
		cacheAPI := helpers.FakeCacheAPI(t, client, 0)
		cacheAPI.PublishCacheDocumentReturns(nil, errors.New("some twirp error"))

		res, err := publishGitDocumentWithRetries(ctx, indexerCluster, cacheClusters, req, topic, retry.DefaultBackOff(ctx, retries))
		require.Error(t, err)
		require.Nil(t, res)
		require.Equal(t, retries+1, cacheAPI.PublishCacheDocumentCallCount())
	})
}
