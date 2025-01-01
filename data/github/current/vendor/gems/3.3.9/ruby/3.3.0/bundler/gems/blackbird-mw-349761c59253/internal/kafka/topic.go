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

type EpochType string

const (
	EpochTypeBackfill = "backfill"
	EpochTypeBranch   = "branch"
)

// UpdateTopics creates a new per-epoch backfill, document, and snapshot topics.
// It truncates the prior document and snapshot topics and deletes unnecessary
// older topics when EpochTypeBackfill is specified.
func UpdateTopics(
	ctx context.Context,
	adminProvider func() sarama.ClusterAdmin,
	epoch *db.Epoch,
	tc routing.TopicConfig,
	epochType EpochType,
) error {
	clusterAdmin := adminProvider()
	defer clusterAdmin.Close()

	topics, err := clusterAdmin.ListTopics()
	if err != nil {
		return errors.Wrap(err, "could not list topics")
	}

	documentTopic := routing.DocumentTopic{
		Corpus:     epoch.Corpus,
		EpochID:    epoch.EpochID,
		Partitions: tc.Document.Partitions,
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

		if epochType == EpochTypeBackfill {
			logging.Info(
				ctx,
				"reducing retention of document topic for older epoch",
				kvp.Int64("epoch_id", int64(largestEpochTopic.EpochID)),
				kvp.Int("corpus_id", int(largestEpochTopic.Corpus)),
				kvp.String("corpus", largestEpochTopic.Corpus.String()),
				kvp.String("topic", largestEpochTopic.Name()),
			)

			err := clusterAdmin.AlterConfig(
				sarama.TopicResource,
				largestEpochTopic.Name(),
				tc.TruncateDocumentTopicConfig(),
				false, // validateOnly, don't alter (https://javadoc.io/doc/org.apache.kafka/kafka-clients/latest/org/apache/kafka/clients/admin/AlterConfigsOptions.html)
			)
			if err != nil {
				return errors.Wrap(err, "could not reduce topic retention")
			}

			for _, ot := range priorDocumentTopics[1:] {
				logging.Info(
					ctx,
					"deleting document topic for older epoch",
					kvp.Int64("epoch_id", int64(ot.EpochID)),
					kvp.Int("corpus_id", int(ot.Corpus)),
					kvp.String("corpus", ot.Corpus.String()),
					kvp.String("topic", ot.Name()),
				)
				err := clusterAdmin.DeleteTopic(ot.Name())
				if err != nil {
					return errors.Wrap(err, "could not delete older topic")
				}
			}
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

		if epochType == EpochTypeBackfill {
			for _, st := range priorSnapshotTopics[1:] {
				logging.Info(
					ctx,
					"deleting snapshot topic for older epoch",
					kvp.Int64("epoch_id", int64(st.EpochID)),
					kvp.Int("corpus_id", int(st.Corpus)),
					kvp.String("corpus", st.Corpus.String()),
					kvp.String("topic", st.Name()),
				)
				err := clusterAdmin.DeleteTopic(st.Name())
				if err != nil {
					return errors.Wrap(err, "could not delete older snapshot topic")
				}
			}
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
	err = clusterAdmin.CreateTopic(documentTopic.Name(), tc.DocumentTopicDetail(), false)
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

func IsSnapshotTopicPresent(adminProvider func() sarama.ClusterAdmin, snapshotTopic *routing.SnapshotTopic) (bool, error) {
	clusterAdmin := adminProvider()
	topics, err := clusterAdmin.ListTopics()
	if err != nil {
		return false, err
	}

	_, present := topics[snapshotTopic.Name()]
	return present, nil
}
