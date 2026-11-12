package deltaingest

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	blackbird "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/utils"
)

type IngestModeDetector interface {
	IsBackfillFinished(ctx context.Context, state *db.CorpusState) (bool, error)
}

type KafkaIngestModeDetector struct {
	store                 db.Store
	sharedKafkaAdmin      *kafka.AdminClient
	blackbirdKafkaAdmin   *kafka.AdminClient
	snapshotProducer      sarama.SyncProducer
	numBackfillPartitions int
	stamp                 routing.Stamp
}

func NewIngestModeDetector(
	store db.Store,
	sharedKafkaAdmin *kafka.AdminClient,
	blackbirdKafkaAdmin *kafka.AdminClient,
	snapshotProducer sarama.SyncProducer,
	numBackfillPartitions int,
	stamp routing.Stamp,
) *KafkaIngestModeDetector {
	return &KafkaIngestModeDetector{store, sharedKafkaAdmin, blackbirdKafkaAdmin, snapshotProducer, numBackfillPartitions, stamp}
}

func (b *KafkaIngestModeDetector) Run(ctx context.Context) {
	go func() {
		defer utils.PanicLogger(ctx)

		// Add some jitter to the interval (should take 2-10s)
		ticker := time.NewTicker(2*time.Second + time.Duration(8000*rand.Float64())*time.Millisecond)
		defer ticker.Stop()

		for {
			if err := b.check(ctx); err != nil && !errors.Is(err, context.Canceled) {
				logging.Error(ctx, "failed to check backfill state", kvp.Err(err))
			}

			select {
			case <-ticker.C:
				continue
			case <-ctx.Done():
				logging.Info(ctx, "context canceled, exiting backfill checker loop")
				return
			}
		}
	}()
}

func (b *KafkaIngestModeDetector) check(ctx context.Context) error {
	for _, corpus := range b.stamp.EnabledCorpora() {
		state, err := b.store.GetCorpusState(ctx, corpus)
		if err != nil {
			return err
		}

		// We always check to get stats in DD
		if err := b.reportMaxLag(ctx, state); err != nil {
			return err
		}

		backfillFinished, err := b.IsBackfillFinished(ctx, state)
		if err != nil {
			return err
		}

		switch state.IngestMode {
		case db.IngestModeBackfill:
			if backfillFinished {
				if _, err := b.store.SetCorpusIngestMode(ctx, corpus, db.IngestModeBackfill, db.IngestModeBackfillCatchup); err != nil {
					return err
				}
			}
		case db.IngestModeBackfillCatchup:
			if err := b.checkForTransitionToIncremental(ctx, state); err != nil {
				return err
			}
			continue
		default:
			// NOOP in all other states (Legacy, Incremental, Aborted)
			continue
		}
	}
	return nil
}

// IsBackfillFinished looks for committed offsets on each partition of the
// backfill topic to move past what's saved in the db (end offsets of the
// backfill).
func (b *KafkaIngestModeDetector) IsBackfillFinished(ctx context.Context, state *db.CorpusState) (bool, error) {
	corpus := state.Corpus
	backfillTopic := corpus.EpochBackfillTopic(state.EpochID)

	ctx = logging.With(ctx, kvp.String("corpus", corpus.String()), kvp.Int("epoch_id", int(state.EpochID)), kvp.String("topic", backfillTopic))

	offsets, err := b.store.GetEpochEndOffsets(ctx, state.EpochID)
	if err != nil {
		return false, err
	}
	if len(offsets) == 0 {
		// Might have caught the system right in the middle of a `.blackbird
		// backfill`, just check again later...
		return false, nil
	}

	if len(offsets) != b.numBackfillPartitions {
		panic(fmt.Sprintf("Found %d offsets in database, expected %d offsets from topic %q", len(offsets), b.numBackfillPartitions, backfillTopic))
	}

	partitions := make([]int32, 0, len(offsets))
	for partition := range offsets {
		partitions = append(partitions, partition)
	}

	cg := corpus.ConsumerGroup(state.EpochID)
	res, err := b.blackbirdKafkaAdmin.ListConsumerGroupOffsets(cg, map[string][]int32{backfillTopic: partitions})
	if err != nil {
		return false, fmt.Errorf("error listing consumer group offsets: %w", err)
	}

	allFinished := true
	for partition, lastOffset := range offsets {
		block := res.GetBlock(backfillTopic, partition)
		if block == nil {
			logging.Info(ctx, "no offsets recorded", kvp.String("topic", backfillTopic), kvp.Int("partition", int(partition)), kvp.String("consumer_group", cg))
			return false, nil
		}

		var delta int64
		// If the consumer group offset is negative (either newest offset (-1) or earliest offset (-2)), this means the
		// consumer group has no recorded offsets for the topic and partition. This can happen when the consumer group's
		// consumer offsets are deleted by the broker (see https://kafka.apache.org/documentation/#brokerconfigs_offsets.retention.minutes),
		// or when the consumer group is new and has not yet consumed any messages.
		// NB: Because we configure Kafka consumers initial offsets to be -1 (newest offset), we should never see -2 (earliest offset) here.
		offset := block.Offset
		switch {
		case offset >= 0:
			consumedOffset := offset - 1 // NB: Kafka stores the *next* offset to read, the db has the inclusive end.
			if consumedOffset < lastOffset {
				allFinished = false
			}
			delta = lastOffset - consumedOffset
		case offset == -1:
			allFinished = false
			logging.Info(ctx, "no offsets recorded (newest)", kvp.String("topic", backfillTopic), kvp.Int("partition", int(partition)), kvp.String("consumer_group", cg))
		case offset == -2:
			allFinished = false
			logging.Info(ctx, "no offsets recorded (oldest)", kvp.String("topic", backfillTopic), kvp.Int("partition", int(partition)), kvp.String("consumer_group", cg))
		default:
			panic(fmt.Sprintf("unexpected block offset: %d", offset))
		}

		statting.Gauge(ctx, "backfill_lag", delta, stats.Tags{"corpus": corpus.String(), "topic": backfillTopic, "cg": cg, "partition": fmt.Sprintf("%d", partition)})
	}

	return allFinished, nil
}

// checkForTransitionToIncremental looks for lag on the incremental and
// onboarding topics to be within some threshold and then transitions ingest
// mode to => IngestModeIncrementalTransition, sends a message to switch modes
// to the shards, and finally transitions to => IngestModeIncremental.
//
// This calculates the consumer lag by comparing the committed offsets for the
// ingest worker consumer group with the newest offsets on each partition.
func (b *KafkaIngestModeDetector) checkForTransitionToIncremental(ctx context.Context, state *db.CorpusState) error {
	corpus := state.Corpus
	ctx = logging.With(ctx, kvp.String("corpus", corpus.String()), kvp.Int("epoch_id", int(state.EpochID)))

	incrLag, err := b.getMaxIncrementalLag(ctx, state)
	if err != nil {
		return fmt.Errorf("failed to get incremental lag: %w", err)
	}

	onboardingLag, err := b.getMaxOnboardingLag(ctx, state)
	if err != nil {
		return fmt.Errorf("failed to get onboarding lag: %w", err)
	}

	// NB: Incremental/onboarding lag hovers around 50 when we're caught up due to the
	// debounce window, set the threshold a little above to detect when we enter
	// this state. If the lag is too high, return early and don't transition.
	const lagTransitionThreshold = 100
	if incrLag > lagTransitionThreshold || onboardingLag > lagTransitionThreshold {
		return nil
	}

	// Update state to incremental transition mode.
	ok, err := b.store.SetCorpusIngestMode(ctx, corpus, db.IngestModeBackfillCatchup, db.IngestModeIncrementalTransition)
	if err != nil {
		return fmt.Errorf("failed to set ingest mode: cannot switch to incremental transition mode: %w", err)
	}
	if !ok {
		return nil // Somebody beat us to switching modes or db state otherwise changed
	}

	// Send a message on the snapshot topic to let the shards know we're going incremental.
	msg, err := EncodeSnapshotMessage(
		routing.SnapshotTopic{
			Corpus:  state.Corpus,
			EpochID: state.EpochID,
		},
		&blackbird.SnapshotTreeUpdate{
			EpochId: uint32(state.EpochID),
			Mode:    blackbird.SnapshotTreeUpdate_INCREMENTAL,
		},
	)
	if err != nil {
		return fmt.Errorf("failed to encode snapshot message: cannot move to incremental mode: %w", err)
	}

	if _, _, err := b.snapshotProducer.SendMessage(msg); err != nil {
		return fmt.Errorf("failed to send snapshot message: cannot switch to incremental mode: %w", err)
	}

	// Update state in the db now that we're officially in incremental mode.
	ok, err = b.store.SetCorpusIngestMode(ctx, corpus, db.IngestModeIncrementalTransition, db.IngestModeIncremental)
	if err != nil {
		return fmt.Errorf("failed to set ingest mode: cannot switch to incremental mode: %w", err)
	}

	if !ok {
		return errors.New("failed to switch to incremental mode: db in unknown state")
	}
	return nil
}

// reportMaxLag publishes metrics for the Kafka lag on the incremental and onboarding topics.
func (b *KafkaIngestModeDetector) reportMaxLag(ctx context.Context, state *db.CorpusState) error {
	if _, err := b.getMaxIncrementalLag(ctx, state); err != nil {
		return err
	}

	if _, err := b.getMaxOnboardingLag(ctx, state); err != nil {
		return err
	}

	return nil
}

// getMaxIncrementalLag returns the maximum number of messages behind the head
// of the incremental topic. As a side effect it publishes a lag metric for each
// partition.
func (b *KafkaIngestModeDetector) getMaxIncrementalLag(ctx context.Context, state *db.CorpusState) (int64, error) {
	return b.sharedKafkaAdmin.GetMaxLag(ctx, state.Corpus, state.EpochID, routing.IncrementalSourceTopic, stats.Tags{"ingest_mode": state.IngestMode.String()})
}

// getMaxOnboardingLag returns the maximum number of messages behind the head of
// the onboarding topic. As a side effect it publishes a lag metric for each
// partition.
func (b *KafkaIngestModeDetector) getMaxOnboardingLag(ctx context.Context, state *db.CorpusState) (int64, error) {
	return b.sharedKafkaAdmin.GetMaxLag(ctx, state.Corpus, state.EpochID, routing.OnboardSourceTopic, stats.Tags{"ingest_mode": state.IngestMode.String()})
}
