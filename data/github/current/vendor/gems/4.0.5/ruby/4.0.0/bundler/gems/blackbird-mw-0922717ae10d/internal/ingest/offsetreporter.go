package ingest

import (
	"context"
	"fmt"
	"time"

	"github.com/cenkalti/backoff/v4"
	indexpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/index/v1"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

func newOffsetReporter(
	corpus routing.Corpus,
	indexerCluster *routing.IndexerCluster,
	offsetTracker *kafka.OffsetTracker,
	sharedAdminClient *kafka.AdminClient,
	blackbirdAdminClient *kafka.AdminClient,
) offsetReporter {
	return offsetReporter{
		indexerCluster:       indexerCluster,
		offsetTracker:        offsetTracker,
		sharedAdminClient:    sharedAdminClient,
		blackbirdAdminClient: blackbirdAdminClient,
		corpus:               corpus,
		epochID:              types.EpochID(indexerCluster.EpochInfo().EpochID), // Initial epoch ID, if it changes sendConsumedOffsets returns an error
	}
}

type offsetReporter struct {
	indexerCluster       *routing.IndexerCluster
	offsetTracker        *kafka.OffsetTracker
	sharedAdminClient    *kafka.AdminClient
	blackbirdAdminClient *kafka.AdminClient
	corpus               routing.Corpus
	epochID              types.EpochID
}

// Send SourceKafkaOffsets for consumed and committed topics tracked by the
// OffsetTracker to the index cluster.
//
// To ensure empty partitions are reported, also sends committed offsets for
// incremental and onboarding partitions that are below the lag threshold.
func (o offsetReporter) sendSourceKafkaOffsets(ctx context.Context) error {
	attempt := 0
	op := func() error {
		attempt++
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()

		if o.indexerCluster.IsIndexingPaused() {
			return nil
		}

		host, err := o.indexerCluster.GetHost()
		if err != nil {
			logging.Error(ctx, "failed to get host for index cluster, retrying", kvp.Err(err))
			return err
		}

		skos, err := o.getAllSourceOffsets(ctx)
		if err != nil {
			logging.Error(ctx, "failed to get all source kafka offsets, retrying", kvp.Err(err))
			return err
		}

		req := &indexpb.SkipRequest{
			ShardId:            host.ShardID,
			EpochId:            uint32(o.epochID),
			SourceKafkaOffsets: skos,
		}

		_, err = host.Skip(ctx, req)
		if err != nil {
			logging.Error(ctx, "Skip RPC failed", kvp.Err(err), kvp.Int("skip_rpc_attempt", attempt), kvp.String("index_host", host.Hostname))
			if epochMovedErr := GetNewEpochError(ctx, o.epochID, err); epochMovedErr != nil {
				return backoff.Permanent(epochMovedErr)
			}
			return err
		}

		return nil
	}

	return backoff.Retry(op, retry.Forever(ctx))
}

const lagThreshold = 100

// Returns both committed and consumed offsets (consumed offsets include
// timestamp as well) for all Kafka topics and partitions seen by this ingest
// process, plus an entry with a mark is included if the consumer group lag is
// low enough for the onboarding and incremental partitions.
//
// Committed offsets are used for epoch branching. The consumed offsets and
// timestamps are used by the probers for monitoring lag and tracking cluster
// health.
//
// Reports per-partition lag for all topics as a metric.
func (o offsetReporter) getAllSourceOffsets(ctx context.Context) ([]*blackbird_entities.SourceKafkaOffsets, error) {
	committed := o.offsetTracker.GetAllCommitted()
	consumed := o.offsetTracker.GetAllLastConsumed()

	// Augment consumed with finished partitions, and mark the finished partition.
	// We do this because in low-traffic environments, not every partition is guaranteed to have a message.
	//
	// NOTE: This reads from the consumer group, so it includes offsets for all partitions.
	cg := o.corpus.ConsumerGroup(o.epochID)
	incrLag, err := o.sharedAdminClient.GetLag(ctx, cg, routing.IncrementalSourceTopic)
	if err != nil {
		return nil, err
	}
	onboardingLag, err := o.sharedAdminClient.GetLag(ctx, cg, routing.OnboardSourceTopic)
	if err != nil {
		return nil, err
	}
	// NOTE: Use only for for reporting lag. Not used for marking offsets because this topic has sentinel messages.
	// Must use the blackbirdAdminClient because the backfill topic exists on the blackbird Kafka cluster.
	backfillLag, err := o.blackbirdAdminClient.GetLag(ctx, cg, o.corpus.EpochBackfillTopic(o.epochID))
	if err != nil {
		return nil, err
	}

	o.reportLag(ctx, cg, incrLag)
	o.reportLag(ctx, cg, onboardingLag)
	o.reportLag(ctx, cg, backfillLag)

	for pk, lag := range incrLag {
		offset, ok := committed[pk]
		if lag < lagThreshold {
			if ok {
				// we caught up and processed this partition. Mark this offset.
				offset.Mark()
			} else {
				// we are caught up but haven't seen this partition. Create a marked offset
				mko := kafka.NewMarkedKafkaOffset(0)
				mko.Mark()
				committed[pk] = mko
			}
		}
	}

	for pk, lag := range onboardingLag {
		offset, ok := committed[pk]
		if lag < lagThreshold {
			if ok {
				// we caught up and processed this partition. Mark this offset.
				offset.Mark()
			} else {
				// we are caught up but haven't seen this partition. Create a marked offset
				mko := kafka.NewMarkedKafkaOffset(0)
				mko.Mark()
				committed[pk] = mko
			}
		}
	}

	offsets := []*blackbird_entities.SourceKafkaOffsets{}
	for pk, offset := range committed {
		offsets = append(offsets, committedSourceKafkaOffsets(pk.Topic, pk.Partition, offset))
	}
	for pk, consumed := range consumed {
		offsets = append(offsets, consumedSourceKafkaOffsets(pk.Topic, pk.Partition, consumed.Offset, consumed.Ts))
	}

	return offsets, nil
}

func (o offsetReporter) reportLag(ctx context.Context, consumerGroup string, lag map[kafka.PartitionKey]int64) {
	for pk, partitionLag := range lag {
		tags := stats.Tags{
			"corpus":    o.corpus.String(),
			"topic":     pk.Topic,
			"cg":        consumerGroup,
			"partition": fmt.Sprintf("%d", pk.Partition),
		}

		statting.Gauge(ctx, "consumer_lag", partitionLag, tags)
	}
}
