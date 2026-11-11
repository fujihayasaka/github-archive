package backfill

import (
	"context"
	"fmt"
	"time"

	"github.com/IBM/sarama"
	"github.com/cenkalti/backoff/v4"
	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	blackbird_pb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/blackbird-mw/internal/search/blackbird"

	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/db"
	pb "github.com/github/blackbird-mw/internal/proto/admin/v1"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

// An async sarama producer that allows publishing repos for backfill and
// collecting the last offset on each partition.
type Publisher struct {
	store                db.Store
	kafkaClusterResolver routing.ClusterResolver
	blackbirdProducers   map[routing.Region]sarama.SyncProducer
	cacheClusters        *routing.CacheClusters
	chatClient           chat.Client
	topicConfig          routing.TopicConfig
}

func NewPublisher(
	store db.Store,
	kafkaClusterResolver routing.ClusterResolver,
	blackbirdProducers map[routing.Region]sarama.SyncProducer,
	cacheClusters *routing.CacheClusters,
	chatClient chat.Client,
	topicConfig routing.TopicConfig,
) *Publisher {
	return &Publisher{
		store,
		kafkaClusterResolver,
		blackbirdProducers,
		cacheClusters,
		chatClient,
		topicConfig,
	}
}

// Triggers a backfill operation for the given corpus and epoch.
// Returns an error if the operation fails.
func (b *Publisher) Publish(ctx context.Context, req *pb.BackfillCorpusRequest, epoch *db.Epoch) error {
	ctx = logging.With(
		ctx,
		kvp.String("corpus", req.Corpus),
		kvp.String("topic", epoch.Corpus.EpochBackfillTopic(epoch.EpochID)),
		kvp.String("epoch_mode", req.EpochMode.String()),
		kvp.Uint("epoch_id", uint(epoch.EpochID)),
		kvp.Uint("num_shards", uint(req.NumShards)),
		kvp.Bool("bootstrap", req.Bootstrap),
	)
	// Trigger epoch change
	err := b.changeEpoch(ctx, epoch, req.EpochMode, req.NumShards)
	if err != nil {
		return err
	}

	return b.backfillRPC(ctx, req, epoch)
}

// Prepare the indexer to handle epoch branching: change the epoch and transition it out of backfill mode.
func (b *Publisher) BootstrapEpochBranch(ctx context.Context, req *pb.BranchEpochRequest, dbEpoch *db.Epoch) error {
	sourceCorpus, err := routing.CorpusFromString(req.SourceCorpus)
	if err != nil {
		return err
	}

	epochMode := blackbird.UnconvertEpochMode(req.EpochMode)
	if epoch.EpochFeaturesExternalContent.SupportedBy(epochMode) {
		logging.Info(ctx, "skipping epoch change for external epoch")
	} else {
		err = b.changeEpoch(ctx, dbEpoch, req.EpochMode, req.NumShards)
		if err != nil {
			return err
		}
	}

	err = b.publishEndBackfillSentinels(ctx, dbEpoch.Corpus, dbEpoch.EpochID)
	if err != nil {
		return err
	}

	targetTopic := &routing.SnapshotTopic{
		Corpus:  dbEpoch.Corpus,
		EpochID: dbEpoch.EpochID,
	}

	msg, err := hydro.NewDefaultEncoder().Encode(
		&blackbird_pb.SnapshotTreeUpdate{
			EpochBranch: &blackbird_pb.SnapshotTreeUpdate_EpochBranch{
				SourceEpochId:   req.SourceEpoch,
				BranchTimestamp: &wrapperspb.Int64Value{Value: req.BranchTs},
				SourceCluster:   sourceCorpus.ClusterName(),
			},
		},
		time.Now(),
	)
	if err != nil {
		return err
	}

	region := b.kafkaClusterResolver.GetRegion(targetTopic.Corpus.ClusterName())
	partition, offset, err := b.blackbirdProducers[region].SendMessage(
		&sarama.ProducerMessage{
			Topic: targetTopic.Name(),
			Value: sarama.ByteEncoder(msg),
		},
	)
	if err != nil {
		return fmt.Errorf("failed to send EpochBranch message: %w", err)
	}
	if offset != 0 {
		return fmt.Errorf(
			"seed message must be the first snapshot tree update when creating an epoch branch, partition:%d, offset:%d",
			partition,
			offset,
		)
	}

	return nil
}

// Publishes sentinel messages to the backfill topic.
func (b *Publisher) publishEndBackfillSentinels(ctx context.Context, corpus routing.Corpus, epochID types.EpochID) error {
	rc := &searchpb.RepositoryChanged{
		Change:           searchpb.RepositoryChanged_ADMIN_PUSHED,
		Repository:       nil, // sentinel value: missing repo
		BlackbirdEpochId: int64(epochID),
	}
	encoded, err := encoder.Encode(rc, time.Now())
	if err != nil {
		return err
	}
	value := sarama.ByteEncoder(encoded)

	for i := range b.topicConfig.Backfill.Partitions {
		msg := &sarama.ProducerMessage{
			Topic:     corpus.EpochBackfillTopic(epochID),
			Partition: i,
			Value:     value,
		}
		region := b.kafkaClusterResolver.GetRegion(corpus.ClusterName())
		_, _, err = b.blackbirdProducers[region].SendMessage(msg)
		if err != nil {
			return err
		}
	}

	logging.Info(ctx, "sent backfill sentinel messages so indexer transitions to incremental mode", kvp.Int("num_partitions", int(b.topicConfig.Backfill.Partitions)))
	return nil
}

var encoder = hydro.NewDefaultEncoder()

func (b *Publisher) changeEpoch(ctx context.Context, epoch *db.Epoch, mode blackbird_entities.EpochMode, numShards uint32) error {
	logging.Info(
		ctx,
		"creating epoch for dynamic shard assignment",
		kvp.Uint("num_shards", uint(numShards)),
		kvp.String("shard_assignment_topic", epoch.Corpus.ShardAssignmentTopic()),
	)

	assignment := &blackbird_pb.ShardAssignment{
		Epoch: &blackbird_entities.ChangeEpoch{
			EpochId:   uint32(epoch.EpochID),
			EpochMode: mode,
			NumShards: numShards,
		},
	}

	payload, err := encoder.Encode(assignment, time.Now())
	if err != nil {
		return fmt.Errorf("failed to encode hydro message: %w", err)
	}

	region := b.kafkaClusterResolver.GetRegion(epoch.Corpus.ClusterName())
	_, _, err = b.blackbirdProducers[region].SendMessage(
		&sarama.ProducerMessage{
			Topic: epoch.Corpus.ShardAssignmentTopic(),
			Value: sarama.ByteEncoder(payload),
		},
	)

	return err
}

// backfill RPC triggers MST-based backfill publishing on a random blackbird cache host.
func (b *Publisher) backfillRPC(ctx context.Context, req *pb.BackfillCorpusRequest, epoch *db.Epoch) error {
	destCorpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return err
	}

	attempt := 0
	operation := func() error {
		attempt++

		cacheHost, err := b.cacheClusters.RandomHost(req.MstCacheCluster)
		if err != nil {
			return err
		}

		msg := fmt.Sprintf("Calling Backfill RPC on cache host %q backfill %s using source epoch %d with epoch mode %s", cacheHost.Hostname, destCorpus, cacheHost.EpochID, req.EpochMode.String())

		if req.Limit > 0 {
			msg += fmt.Sprintf(" with limit %d", req.Limit)
		}

		if req.Bootstrap {
			msg += " in bootstrap mode"
		}

		if attempt > 1 {
			msg += fmt.Sprintf(" (attempt %d)", attempt)
		}

		logging.Info(ctx, "calling Backfill RPC",
			kvp.String("shard", cacheHost.Hostname),
			kvp.Int("source_epoch", int(cacheHost.EpochID)),
			kvp.Uint("limit", uint(req.Limit)),
			kvp.Int("backfill_attempt", attempt),
		)

		b.say(ctx, msg)
		backfillReq := &cachepb.BackfillRequest{
			EpochId:         uint32(cacheHost.EpochID),
			Num:             req.Limit,
			NumPartitions:   uint32(b.topicConfig.Backfill.Partitions),
			TargetNumShards: req.NumShards,
			ShardId:         cacheHost.ShardID,
			TargetEpoch:     uint32(epoch.EpochID),
			TargetEpochMode: req.EpochMode,
			TargetCorpus:    req.Corpus,
			NumMasks:        req.NumMasks,
			Query:           req.Query,
			Bootstrap:       req.Bootstrap,
		}
		_, err = cacheHost.Backfill(ctx, backfillReq)
		if err != nil {
			logging.Error(ctx, "failed to trigger backfill",
				kvp.Err(err),
				kvp.String("cache_host", cacheHost.Hostname),
				kvp.Uint("source_epoch", uint(cacheHost.EpochID)),
				kvp.Int("backfill_attempt", attempt))
			return err
		}

		return nil
	}

	return backoff.Retry(operation, retry.DefaultBackOff(ctx, 3))
}

// Publish a message to the blackbird-ops channel. It is infallible and will log
// if the message can't be published.
func (b *Publisher) say(ctx context.Context, msg string) {
	chat.Say(ctx, b.chatClient, chat.BlackbirdOpsChannel, msg)
}
