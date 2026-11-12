package ingest

import (
	"context"
	"testing"
	"time"

	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_sourceKafkaOffsets(t *testing.T) {
	ctx := context.Background()
	partition := int32(1)
	now := time.Now()
	ot := kafka.NewOffsetTracker(&kafkafakes.FakeIngestConsumer{})

	// Track offset: 0 on partition: 1
	// We should get that offset 0 is consumed (and a valid timestamp) and that
	// offset 0 is committed, because to read the message with offset 0 it must be.
	ot.TrackMsg(ctx, routing.IncrementalSourceTopic, partition, kafka.NewMarkedKafkaOffset(0), now)
	result := getSourceOffsets(ot, routing.IncrementalSourceTopic, partition)
	require.ElementsMatch(t, result, []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.ConsumedTopic(routing.IncrementalSourceTopic),
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

	// Now mark offset 0 as complete. Since Kafka stores the offset of the next message to be consumed, the committed offset is 1.
	ot.MarkOffset(ctx, routing.IncrementalSourceTopic, partition, kafka.NewMarkedKafkaOffset(0))
	result = getSourceOffsets(ot, routing.IncrementalSourceTopic, partition)
	require.ElementsMatch(t, result, []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.ConsumedTopic(routing.IncrementalSourceTopic),
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
					Offset:    1,
				},
			},
		},
	})

	// Now, consume ahead bit and the consumed source offsets should move forward, but the committed
	// offset is still 1.
	for i := 1; i < 10; i++ {
		ot.TrackMsg(ctx, routing.IncrementalSourceTopic, partition, kafka.NewMarkedKafkaOffset(int64(i)), now)
	}
	result = getSourceOffsets(ot, routing.IncrementalSourceTopic, partition)
	require.ElementsMatch(t, result, []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.ConsumedTopic(routing.IncrementalSourceTopic),
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
					Offset:    1,
				},
			},
		},
	})

	// Now track and mark a new message with a marked offset
	mko := helpers.MarkedKafkaOffsetWithMark(t, 10)
	ot.TrackMsg(ctx, routing.IncrementalSourceTopic, partition, mko, now)
	ot.MarkOffset(ctx, routing.IncrementalSourceTopic, partition, mko)
	result = getSourceOffsets(ot, routing.IncrementalSourceTopic, partition)
	require.ElementsMatch(t, result, []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.ConsumedTopic(routing.IncrementalSourceTopic),
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    10, // NOTE: Not marked because last committed is still 1
					Timestamp: now.UnixMilli(),
				},
			},
		},
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    1,
				},
			},
		},
	})

	// Now finish the prior messages so last committed >= earliest marked
	for i := 1; i < 10; i++ {
		ot.MarkOffset(ctx, routing.IncrementalSourceTopic, partition, kafka.NewMarkedKafkaOffset(int64(i)))
	}
	result = getSourceOffsets(ot, routing.IncrementalSourceTopic, partition)
	require.ElementsMatch(t, result, []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.ConsumedTopic(routing.IncrementalSourceTopic),
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    mko.Raw(),
					Timestamp: now.UnixMilli(),
				},
			},
		},
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: partition,
					Offset:    helpers.MarkedKafkaOffsetWithMark(t, 11).Raw(), // committed offset is mko+1
				},
			},
		},
	})
}
