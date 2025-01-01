package deltaingest

import (
	"fmt"
	"time"

	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/kafka"
)

// Returns both committed and consumed offsets (consumed offsets include timestamp as well) for a
// given Kafka topic and partition. Committed offsets are used for epoch branching. The consumed
// offsets and timestamps are used by the probers for monitoring lag and tracking cluster health.
func getSourceOffsets(ot *kafka.OffsetTracker, topic string, partition int32) []*blackbird_entities.SourceKafkaOffsets {
	offsets := []*blackbird_entities.SourceKafkaOffsets{}

	lastConsumedOffset, lastConsumedTs := ot.GetLastConsumed(topic, partition)
	if lastConsumedOffset >= 0 {
		offsets = append(offsets, consumedSourceKafkaOffsets(topic, partition, lastConsumedOffset, lastConsumedTs))
	}

	lastCommittedOffset := ot.GetLastCommittedOffset(topic, partition)
	if lastCommittedOffset >= 0 {
		offsets = append(offsets, committedSourceKafkaOffsets(topic, partition, lastCommittedOffset))
	}

	return offsets
}

// Returns both committed and consumed offsets (consumed offsets include timestamp as well) for a
// all Kafka topics and partitions. Committed offsets are used for epoch branching. The consumed
// offsets and timestamps are used by the probers for monitoring lag and tracking cluster health.
func getAllSourceOffsets(ot *kafka.OffsetTracker) []*blackbird_entities.SourceKafkaOffsets {
	offsets := []*blackbird_entities.SourceKafkaOffsets{}

	consumed := ot.GetAllLastConsumed()
	for pk, consumed := range consumed {
		if consumed.Offset >= 0 {
			offsets = append(offsets, consumedSourceKafkaOffsets(pk.Topic, pk.Partition, consumed.Offset, consumed.Ts))
		}
	}

	committed := ot.GetAllLastCommitted()
	for pk, lastCommited := range committed {
		if lastCommited >= 0 {
			offsets = append(offsets, committedSourceKafkaOffsets(pk.Topic, pk.Partition, lastCommited))
		}
	}

	return offsets
}

func consumedSourceKafkaOffsets(topic string, partition int32, lastConsumedOffset int64, lastConsumedTs time.Time) *blackbird_entities.SourceKafkaOffsets {
	return &blackbird_entities.SourceKafkaOffsets{
		// NB: We use a fake topic name (^ is an invalid character for topics in Kafka) to track
		// consumed offsets.
		Topic: fmt.Sprintf("%s^consumed", topic),
		PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
			{
				Partition: partition,
				Offset:    lastConsumedOffset,
				Timestamp: lastConsumedTs.UnixMilli(),
			},
		},
	}
}

func committedSourceKafkaOffsets(topic string, partition int32, lastCommittedOffset int64) *blackbird_entities.SourceKafkaOffsets {
	return &blackbird_entities.SourceKafkaOffsets{
		Topic: topic,
		PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
			{
				Partition: partition,
				Offset:    lastCommittedOffset,
				// TODO: Should we track these too? have to do this in the PQ and it's tricky b/c we skip ahead...
				// Timestamp: ,
			},
		},
	}
}
