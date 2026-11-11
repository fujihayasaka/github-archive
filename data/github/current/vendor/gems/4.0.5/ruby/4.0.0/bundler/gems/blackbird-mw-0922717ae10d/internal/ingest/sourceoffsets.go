package ingest

import (
	"time"

	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/routing"
)

// Returns both committed and consumed offsets (consumed offsets include timestamp as well) for a
// given Kafka topic and partition. Committed offsets are used for epoch branching. The consumed
// offsets and timestamps are used by the probers for monitoring lag and tracking cluster health.
func getSourceOffsets(ot *kafka.OffsetTracker, topic string, partition int32) []*blackbird_entities.SourceKafkaOffsets {
	offsets := []*blackbird_entities.SourceKafkaOffsets{}

	lastConsumedOffset, lastConsumedTs := ot.GetLastConsumed(topic, partition)
	offsets = append(offsets, consumedSourceKafkaOffsets(topic, partition, lastConsumedOffset, lastConsumedTs))

	committedOffset := ot.GetCommittedOffset(topic, partition)
	offsets = append(offsets, committedSourceKafkaOffsets(topic, partition, committedOffset))

	return offsets
}

func consumedSourceKafkaOffsets(topic string, partition int32, lastConsumedOffset kafka.MarkedKafkaOffset, lastConsumedTs time.Time) *blackbird_entities.SourceKafkaOffsets {
	return &blackbird_entities.SourceKafkaOffsets{
		Topic: routing.ConsumedTopic(topic),
		PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
			{
				Partition: partition,
				Offset:    lastConsumedOffset.Raw(),
				Timestamp: lastConsumedTs.UnixMilli(),
			},
		},
	}
}

func committedSourceKafkaOffsets(topic string, partition int32, lastCommittedOffset kafka.MarkedKafkaOffset) *blackbird_entities.SourceKafkaOffsets {
	return &blackbird_entities.SourceKafkaOffsets{
		Topic: topic,
		PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
			{
				Partition: partition,
				Offset:    lastCommittedOffset.Raw(),
				// TODO: Should we track these too? have to do this in the PQ and it's tricky b/c we skip ahead...
				// Timestamp: ,
			},
		},
	}
}
