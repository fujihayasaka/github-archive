package kafka

import (
	"context"
	"fmt"
	"sort"

	"github.com/IBM/sarama"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/routing"
)

// UpdateTopics creates a new per-epoch backfill, document, and snapshot topics.
func UpdateTopics(
	ctx context.Context,
	adminProvider func(corpus routing.Corpus) sarama.ClusterAdmin,
	corpus routing.Corpus,
	epoch *db.Epoch,
	tc routing.TopicConfig,
	numShards int32,
) error {
	clusterAdmin := adminProvider(corpus)
	defer clusterAdmin.Close()

	topics, err := clusterAdmin.ListTopics()
	if err != nil {
		return errors.Wrap(err, "could not list topics")
	}

	documentTopic := routing.DocumentTopic{
		Corpus:     epoch.Corpus,
		EpochID:    epoch.EpochID,
		Partitions: numShards,
	}

	if _, ok := topics[documentTopic.Name()]; ok {
		return errors.New("document topic already exists for this epoch")
	}

	snapshotTopic := routing.SnapshotTopic{
		Corpus:  epoch.Corpus,
		EpochID: epoch.EpochID,
	}

	if _, ok := topics[snapshotTopic.Name()]; ok {
		return errors.New("snapshot topic already exists for this epoch")
	}

	priorDocumentTopics := []*routing.DocumentTopic{}
	for topic, detail := range topics {
		dt, err := routing.NewDocumentTopicFromTopicDetail(topic, detail)
		if err != nil {
			continue
		}

		if dt.Corpus != epoch.Corpus {
			continue
		}

		priorDocumentTopics = append(priorDocumentTopics, dt)
	}

	// Deal with older topics
	if len(priorDocumentTopics) > 0 {
		// Sort in reverse order so the biggest epoch is first
		sort.Slice(priorDocumentTopics, func(i, j int) bool {
			return priorDocumentTopics[i].EpochID > priorDocumentTopics[j].EpochID
		})

		largestEpochTopic := priorDocumentTopics[0]

		if largestEpochTopic.EpochID > epoch.EpochID {
			return errors.New("a document topic for a larger epoch already exists")
		}
	}

	priorSnapshotTopics := []*routing.SnapshotTopic{}
	for topic, detail := range topics {
		snapshotTopic, err := routing.NewSnapshotTopicFromTopicDetail(topic, detail)
		if err != nil {
			continue
		}

		if snapshotTopic.Corpus != epoch.Corpus {
			continue
		}

		priorSnapshotTopics = append(priorSnapshotTopics, snapshotTopic)
	}

	if len(priorSnapshotTopics) > 0 {
		// Sort in reverse order so the biggest epoch is first
		sort.Slice(priorSnapshotTopics, func(i, j int) bool {
			return priorSnapshotTopics[i].EpochID > priorSnapshotTopics[j].EpochID
		})

		largestSnapshotTopic := priorSnapshotTopics[0]

		if largestSnapshotTopic.EpochID > epoch.EpochID {
			return errors.New("a snapshot topic for a larger epoch already exists")
		}
	}

	logging.Info(
		ctx,
		"creating new document topic",
		kvp.Int64("epoch_id", int64(epoch.EpochID)),
		kvp.Int("corpus_id", int(epoch.Corpus)),
		kvp.String("corpus", epoch.Corpus.String()),
		kvp.String("topic", documentTopic.Name()),
	)
	err = clusterAdmin.CreateTopic(documentTopic.Name(), tc.DocumentTopicDetail(documentTopic.Partitions), false)
	if err != nil {
		return errors.Wrap(err, "could not create document topic")
	}

	logging.Info(
		ctx,
		"creating new snapshot topic",
		kvp.Int64("epoch_id", int64(epoch.EpochID)),
		kvp.Int("corpus_id", int(epoch.Corpus)),
		kvp.String("corpus", epoch.Corpus.String()),
		kvp.String("topic", documentTopic.Name()),
	)
	err = clusterAdmin.CreateTopic(snapshotTopic.Name(), tc.SnapshotTopicDetail(), false)
	if err != nil {
		return fmt.Errorf("error creating snapshot topic: %w", err)
	}

	backfillTopic := epoch.Corpus.EpochBackfillTopic(epoch.EpochID)

	logging.Info(
		ctx,
		"creating backfill topic",
		kvp.Int64("epoch_id", int64(epoch.EpochID)),
		kvp.Int("corpus_id", int(epoch.Corpus)),
		kvp.String("corpus", epoch.Corpus.String()),
		kvp.String("topic", backfillTopic),
	)

	err = clusterAdmin.CreateTopic(backfillTopic, tc.BackfillTopicDetail(), false)
	if err != nil {
		return fmt.Errorf("error creating backfill topic: %w", err)
	}

	return nil
}

func IsSnapshotTopicPresent(adminProvider func(routing.Corpus) sarama.ClusterAdmin, corpus routing.Corpus, snapshotTopic *routing.SnapshotTopic) (bool, error) {
	clusterAdmin := adminProvider(corpus)
	topics, err := clusterAdmin.ListTopics()
	if err != nil {
		return false, err
	}

	_, present := topics[snapshotTopic.Name()]
	return present, nil
}
