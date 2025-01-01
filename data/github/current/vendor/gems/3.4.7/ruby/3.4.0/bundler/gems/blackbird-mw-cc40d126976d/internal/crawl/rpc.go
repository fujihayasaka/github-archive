package crawl

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/cenkalti/backoff/v4"
	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	blackbirdpb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/messages"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search/blackbird"
)

// ErrMessageSizeTooLarge is returned when a cache publish fails due to the
// message being too large for Kafka. It is the equivalent of
// sarama.ErrMessageSizeTooLarge in the Kafka-based ingest.
var ErrMessageSizeTooLarge = errors.New("cache: kafka message was too large")

func isMessageSizeTooLarge(err error) bool {
	return err != nil && strings.Contains(err.Error(), "kafka message was too large")
}

func newCacheRequest(doc *blackbirdpb.GitDocument, msg *messages.Ingest) routing.CacheRequest {
	switch {
	case len(doc.Content) > 0:
		return &cachepb.PublishDocumentRequest{
			TopicName:   msg.DocumentTopic.Name(),
			GitDocument: doc,
			NumShards:   uint32(msg.DocumentTopic.Partitions),
			EpochMode:   blackbird.ConvertEpochMode(msg.EpochMode),
			IngestMode:  convertIngestMode(msg.IngestMode),
		}
	case doc.AllLocationsDeleted:
		return &cachepb.PublishDeleteDocumentRequest{
			TopicName:   msg.DocumentTopic.Name(),
			GitDocument: doc,
			NumShards:   uint32(msg.DocumentTopic.Partitions),
			EpochMode:   blackbird.ConvertEpochMode(msg.EpochMode),
			IngestMode:  convertIngestMode(msg.IngestMode),
		}
	default:
		return &cachepb.PublishCacheDocumentRequest{
			TopicName:   msg.DocumentTopic.Name(),
			GitDocument: doc,
			NumShards:   uint32(msg.DocumentTopic.Partitions),
			EpochMode:   blackbird.ConvertEpochMode(msg.EpochMode),
			IngestMode:  convertIngestMode(msg.IngestMode),
		}
	}
}

func publishGitDocumentWithRetries(
	ctx context.Context,
	indexerCluster *routing.IndexerCluster,
	cacheClusters *routing.CacheClusters,
	req routing.CacheRequest,
	topic routing.DocumentTopic,
	backOff backoff.BackOff,
) (routing.CacheResponse, error) {
	const (
		logAttempt  = 5
		logDuration = 5 * time.Minute
	)

	start := time.Now()
	attempts := 0
	var res routing.CacheResponse
	op := func() error {
		attempts++
		var err error

		cluster := indexerCluster.CacheCluster()
		res, err = cacheClusters.Publish(ctx, cluster, req, topic)
		if isMessageSizeTooLarge(err) {
			return backoff.Permanent(ErrMessageSizeTooLarge)
		}

		if attempts == logAttempt {
			logging.Error(
				ctx,
				"unusual cache publish",
				kvp.String("blob_oid", gitaccess.NewObjectIDFromBytes(req.GetGitDocument().ContentSha).String()),
				kvp.String("path", req.GetGitDocument().Locations[0].Path),
				kvp.Int("num_locations", len(req.GetGitDocument().Locations)),
				kvp.Int64("lease_expires_at_ms", req.GetGitDocument().LeaseExpiresAt),
				kvp.Any("lease_expires_at", time.UnixMilli(req.GetGitDocument().LeaseExpiresAt)),
				kvp.Duration("duration_ms", time.Since(start)),
				kvp.Any("duration", time.Since(start)),
				kvp.String("cache_cluster", cluster),
				kvp.Err(err),
			)
		}

		return err
	}

	tags := stats.Tags{"status": "success"}
	err := backoff.Retry(op, backOff)
	if err != nil {
		// NOTE: Don't spam the logs on cancellation
		if !errors.Is(err, context.Canceled) {
			logging.Error(
				ctx,
				"failed to publish document to cache server",
				kvp.String("blob_oid", gitaccess.NewObjectIDFromBytes(req.GetGitDocument().ContentSha).String()),
				kvp.Int("cache_publish_attempts", attempts),
				kvp.Err(err),
			)
		}
		tags = stats.Tags{"status": "error"}
	}

	statting.Counter(ctx, "crawl.cache.publish_git_document.attempts", int64(attempts), tags)
	statting.Distribution(ctx, "crawl.cache.publish_git_document.attempt_dist", float64(attempts), tags)
	statting.DistributionMs(ctx, "crawl.cache.publish_git_document.duration", time.Since(start), tags)

	if attempts >= logAttempt || time.Since(start) >= logDuration {
		logging.Error(
			ctx,
			"final result of unusual cache publish",
			kvp.Int("cache_publish_attempts", attempts),
			kvp.String("blob_oid", gitaccess.NewObjectIDFromBytes(req.GetGitDocument().ContentSha).String()),
			kvp.String("path", req.GetGitDocument().Locations[0].Path),
			kvp.Int("num_locations", len(req.GetGitDocument().Locations)),
			kvp.Int64("lease_expires_at_ms", req.GetGitDocument().LeaseExpiresAt),
			kvp.Any("lease_expires_at", time.UnixMilli(req.GetGitDocument().LeaseExpiresAt)),
			kvp.Duration("duration_ms", time.Since(start)),
			kvp.Any("duration", time.Since(start)),
			kvp.Err(err),
		)
	}

	return res, err
}

func convertIngestMode(ingestMode db.IngestMode) entities.IngestMode {
	switch ingestMode {
	case db.IngestModeLegacy:
		return entities.IngestMode_INGEST_MODE_UNKNOWN
	case db.IngestModeBackfill:
		return entities.IngestMode_INGEST_MODE_BACKFILL
	case db.IngestModeBackfillCatchup:
		return entities.IngestMode_INGEST_MODE_BACKFILL_CATCHUP
	case db.IngestModeIncrementalTransition:
		return entities.IngestMode_INGEST_MODE_INCREMENTAL_TRANSITION
	case db.IngestModeIncremental:
		return entities.IngestMode_INGEST_MODE_INCREMENTAL
	default:
		panic(fmt.Sprintf("unknown ingest mode %v", ingestMode))
	}
}
