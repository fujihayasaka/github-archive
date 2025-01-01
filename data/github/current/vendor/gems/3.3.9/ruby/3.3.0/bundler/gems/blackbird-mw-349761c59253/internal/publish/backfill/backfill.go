package backfill

import (
	"context"
	"fmt"
	"time"

	"github.com/IBM/sarama"
	"github.com/cenkalti/backoff/v4"
	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	blackbird_pb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/pkg/errors"
	"golang.org/x/text/language"
	"golang.org/x/text/message"

	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/deltaingest"
	pb "github.com/github/blackbird-mw/internal/proto/admin/v1"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

// An async sarama producer that allows publishing repos for backfill and
// collecting the last offset on each partition.
type Publisher struct {
	store              db.Store
	snapshotProducer   sarama.SyncProducer
	searchClusters     *routing.SearchClusters
	cacheClusters      *routing.CacheClusters
	chatClient         chat.Client
	documentPartitions uint32
	backfillPartitions uint32
}

func NewPublisher(
	store db.Store,
	snapshotProducer sarama.SyncProducer,
	searchClusters *routing.SearchClusters,
	cacheClusters *routing.CacheClusters,
	chatClient chat.Client,
	documentPartitions uint32,
	backfillPartitions uint32,
) *Publisher {
	return &Publisher{
		store,
		snapshotProducer,
		searchClusters,
		cacheClusters,
		chatClient,
		documentPartitions,
		backfillPartitions,
	}
}

// Returns the number of backfill messages published and the latest offsets on
// all partitions or an error.
func (b *Publisher) Publish(ctx context.Context, req *pb.BackfillCorpusRequest, epoch *db.Epoch) (*ComputeMSTResult, error) {
	topic := epoch.Corpus.EpochBackfillTopic(epoch.EpochID)

	ctx = logging.With(ctx, kvp.String("corpus", req.Corpus), kvp.String("topic", topic), kvp.String("epoch_mode", req.EpochMode.String()), kvp.Uint("epoch_id", uint(epoch.EpochID)))
	// Trigger epoch change
	err := b.ChangeEpoch(ctx, epoch, req.EpochMode)
	if err != nil {
		return nil, err
	}

	if req.Bootstrap {
		err = b.bootstrap(ctx, epoch)
		if err != nil {
			return nil, err
		}

		return &ComputeMSTResult{
			MaxPublishedOffsets: db.EpochOffsets{},
		}, nil
	}

	result, err := b.computeMST(ctx, topic, req, epoch)
	if err != nil {
		logging.Error(ctx, "error loading repositories", kvp.Err(err))
		return nil, err
	}

	if len(result.SourceKafkaOffsets) > 0 {
		msg, err := deltaingest.EncodeSnapshotMessage(
			routing.SnapshotTopic{
				Corpus:  epoch.Corpus,
				EpochID: epoch.EpochID,
			},
			&blackbird_pb.SnapshotTreeUpdate{
				EpochId:            uint32(epoch.EpochID),
				SourceKafkaOffsets: result.SourceKafkaOffsets,
			},
		)
		if err != nil {
			return nil, fmt.Errorf("encoding snapshot message failed: %w", err)
		}
		if _, _, err := b.snapshotProducer.SendMessage(msg); err != nil {
			return nil, fmt.Errorf("publishing snapshot message failed: %w", err)
		}
	}

	return result, err
}

func (b *Publisher) bootstrap(ctx context.Context, epoch *db.Epoch) error {
	// When bootstrapping we go immediately through all the modes...
	if _, err := b.store.SetCorpusIngestMode(ctx, epoch.Corpus, db.IngestModeBackfill, db.IngestModeBackfillCatchup); err != nil {
		return err
	}
	if _, err := b.store.SetCorpusIngestMode(ctx, epoch.Corpus, db.IngestModeBackfillCatchup, db.IngestModeIncrementalTransition); err != nil {
		return err
	}
	// Send a message on the snapshot topic to let the shards know we're going incremental.
	msg, err := deltaingest.EncodeSnapshotMessage(
		routing.SnapshotTopic{
			Corpus:  epoch.Corpus,
			EpochID: epoch.EpochID,
		},
		&blackbird_pb.SnapshotTreeUpdate{
			EpochId: uint32(epoch.EpochID),
			Mode:    blackbird_pb.SnapshotTreeUpdate_INCREMENTAL,
		},
	)
	if err != nil {
		return err
	}
	if _, _, err := b.snapshotProducer.SendMessage(msg); err != nil {
		return err
	}
	if _, err := b.store.SetCorpusIngestMode(ctx, epoch.Corpus, db.IngestModeIncrementalTransition, db.IngestModeIncremental); err != nil {
		return err
	}

	return nil
}

var encoder = hydro.NewDefaultEncoder()

func (b *Publisher) ChangeEpoch(ctx context.Context, epoch *db.Epoch, mode blackbird_entities.EpochMode) error {
	logging.Info(
		ctx,
		"creating epoch for dynamic shard assignment",
		kvp.Uint("num_shards", uint(b.documentPartitions)),
		kvp.String("shard_assignment_topic", epoch.Corpus.ShardAssignmentTopic()),
	)

	assignment := &blackbird_pb.ShardAssignment{
		Epoch: &blackbird_entities.ChangeEpoch{
			EpochId:   uint32(epoch.EpochID),
			EpochMode: mode,
			NumShards: b.documentPartitions,
		},
	}

	payload, err := encoder.Encode(assignment, time.Now())
	if err != nil {
		return fmt.Errorf("failed to encode hydro message: %w", err)
	}

	_, _, err = b.snapshotProducer.SendMessage(
		&sarama.ProducerMessage{
			Topic: epoch.Corpus.ShardAssignmentTopic(),
			Value: sarama.ByteEncoder(payload),
		},
	)

	return err
}

type ComputeMSTResult struct {
	NumReposPublished   uint32
	MaxPublishedOffsets db.EpochOffsets
	SourceKafkaOffsets  []*blackbird_entities.SourceKafkaOffsets
}

// computeMST triggers MST computation on blackbird cache server.
func (b *Publisher) computeMST(
	ctx context.Context,
	topic string,
	req *pb.BackfillCorpusRequest,
	epoch *db.Epoch,
) (*ComputeMSTResult, error) {
	res, err := b.computeMSTWithRetries(ctx, req, topic, epoch)
	if err != nil {
		return nil, fmt.Errorf("MST RPC failed: %w", err)
	}
	if len(res.Offsets) == 0 {
		return nil, fmt.Errorf("MST RPC succeeded without returning offsets")
	}

	maxPublishedOffsets := make(db.EpochOffsets)
	for _, published := range res.Offsets {
		maxPublishedOffsets.Set(published.Partition, published.Offset)
	}

	// We don't want to carry forward source kafka offsets of previous backfills otherwise
	// we'd keep accumulating those for all the backfills ever run.
	sourceKafkaOffsets := []*blackbird_entities.SourceKafkaOffsets{}
	for _, sko := range res.SourceKafkaOffsets {
		if !routing.IsBackfillTopic(sko.Topic) {
			sourceKafkaOffsets = append(sourceKafkaOffsets, sko)
		}

	}

	return &ComputeMSTResult{
		NumReposPublished:   res.GetStats().GetNumRepositories(),
		MaxPublishedOffsets: maxPublishedOffsets,
		SourceKafkaOffsets:  sourceKafkaOffsets,
	}, nil
}

func (b *Publisher) computeMSTWithRetries(ctx context.Context, req *pb.BackfillCorpusRequest, topic string, targetEpoch *db.Epoch) (*cachepb.MstResponse, error) {
	destCorpus, err := routing.CorpusFromString(req.Corpus)
	if err != nil {
		return nil, err
	}

	if req.EpochId == 0 {
		return nil, errors.New("epoch ID is required when requesting MST")
	}

	epochID := types.EpochID(req.EpochId)

	attempt := 0
	var mstRes *cachepb.MstResponse
	operation := func() error {
		attempt++

		cacheCluster := b.searchClusters.CacheClusterName(destCorpus)
		if cacheCluster == "" {
			return backoff.Permanent(errors.New("no cache cluster configured"))
		}

		servingEpoch, err := b.cacheClusters.ServingEpochForCluster(ctx, cacheCluster)
		if err != nil {
			return err
		}

		// TODO: add check for epoch mode as well
		if servingEpoch != epochID {
			return errors.Errorf("cache cluster %q is not serving the requested epoch: %d. Currently serving: %d", cacheCluster, req.EpochId, servingEpoch)
		}

		cacheHost, err := b.cacheClusters.RandomHost(cacheCluster)
		if err != nil {
			return fmt.Errorf("no cache host found for cache cluster %q: %w", cacheCluster, err)
		}

		msg := fmt.Sprintf("Calling MST RPC on cache host %q backfill %s using source epoch %d with epoch mode %s", cacheHost.Hostname, destCorpus, epochID, req.EpochMode.String())

		if req.Limit > 0 {
			msg += fmt.Sprintf(" with limit %d", req.Limit)
		}

		if attempt > 1 {
			msg += fmt.Sprintf(" (attempt %d)", attempt)
		}

		logging.Info(ctx, "fetching MST",
			kvp.String("shard", cacheHost.Hostname),
			kvp.Int("source_epoch", int(epochID)),
			kvp.Uint("limit", uint(req.Limit)),
			kvp.Int("mst_attempt", attempt),
		)

		b.say(ctx, msg)

		start := time.Now()
		mstReq := &cachepb.MstRequest{
			EpochId:         uint32(epochID),
			Num:             req.Limit,
			NumPartitions:   b.backfillPartitions,
			ShardId:         cacheHost.ShardID,
			TargetEpoch:     uint32(targetEpoch.EpochID),
			TargetEpochMode: req.EpochMode,
			TargetTopic:     topic,
			NumMasks:        req.NumMasks,
			Query:           req.Query,
		}
		mstRes, err = cacheHost.ComputeMst(ctx, mstReq)
		if err != nil {
			logging.Error(ctx, "failed to trigger MST computation",
				kvp.Err(err),
				kvp.String("cache_host", cacheHost.Hostname),
				kvp.Uint("source_epoch", uint(epochID)),
				kvp.Int("mst_attempt", attempt))
			return err
		}
		stats := mstRes.GetStats()
		printer := message.NewPrinter(language.English)
		b.say(
			ctx,
			fmt.Sprintf("MST RPC returned %s repositories in %s. MstCost: %s vs. FlatCost: %s",
				printer.Sprintf("%d", stats.GetNumRepositories()),
				time.Since(start).Round(time.Second),
				printer.Sprintf("%d", stats.GetMstCost()),
				printer.Sprintf("%d", stats.GetFlatCost()),
			),
		)
		return nil
	}

	err = backoff.Retry(operation, retry.DefaultBackOff(ctx, 3))
	if err != nil {
		return nil, err
	}

	return mstRes, nil
}

// Publish a message to the blackbird-ops channel. It is infallible and will log
// if the message can't be published.
func (b *Publisher) say(ctx context.Context, msg string) {
	chat.Say(ctx, b.chatClient, chat.BlackbirdOpsChannel, msg)
}
