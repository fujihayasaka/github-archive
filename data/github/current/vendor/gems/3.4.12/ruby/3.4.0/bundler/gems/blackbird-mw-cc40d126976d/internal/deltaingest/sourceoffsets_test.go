package deltaingest

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
	"github.com/github/blackbird-mw/internal/routing"
)

func Test_sourceKafkaOffsets(t *testing.T) {
	ctx := context.Background()
	partition := int32(1)
	now := time.Now()
	ot := kafka.NewOffsetTracker(&kafkafakes.FakeIngestConsumer{})

	// Track offset: 0 on partition: 1
	// We should get that offset zero is consumed (and a valid timestamp)
	ot.TrackMsg(ctx, routing.IncrementalSourceTopic, partition, 0, now)
	result := getSourceOffsets(ot, routing.IncrementalSourceTopic, partition)
	require.ElementsMatch(t, result, []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.IncrementalSourceConsumed,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    0,
					Timestamp: now.UnixMilli(),
				},
			},
		},
	})

	// Now mark that offset as committed
	// We should get back both the consumed and committed offsets
	ot.MarkOffset(ctx, routing.IncrementalSourceTopic, partition, 0)
	result = getSourceOffsets(ot, routing.IncrementalSourceTopic, partition)
	require.ElementsMatch(t, result, []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.IncrementalSourceConsumed,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    0,
					Timestamp: now.UnixMilli(),
				},
			},
		},
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    0,
				},
			},
		},
	})

	// Now, consume ahead bit and the consumed source offsets should move forward, but the committed
	// offset is still 0.
	for i := 1; i < 10; i++ {
		ot.TrackMsg(ctx, routing.IncrementalSourceTopic, partition, int64(i), now)
	}
	result = getSourceOffsets(ot, routing.IncrementalSourceTopic, partition)
	require.ElementsMatch(t, result, []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.IncrementalSourceConsumed,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    9,
					Timestamp: now.UnixMilli(),
				},
			},
		},
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    0,
				},
			},
		},
	})
}
