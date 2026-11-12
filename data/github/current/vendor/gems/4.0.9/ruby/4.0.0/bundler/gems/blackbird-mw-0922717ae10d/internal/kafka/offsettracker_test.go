package kafka_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_IsOffsetConsumable(t *testing.T) {
	tests := []struct {
		name       string
		partition  int32
		offset     int64
		consumable bool
	}{
		{
			name:       "First offset",
			partition:  1,
			offset:     0,
			consumable: true,
		},
		{
			name:       "Next consumable offset",
			partition:  1,
			offset:     1,
			consumable: true,
		},
		{
			name:       "Non-consumable offset",
			partition:  1,
			offset:     1,
			consumable: false,
		},
		{
			name:       "Skipped ahead some offsets",
			partition:  1,
			offset:     3,
			consumable: true,
		},
	}

	consumer := &kafkafakes.FakeIngestConsumer{}
	tracker := kafka.NewOffsetTracker(consumer)
	topic := "blackbird.v0.BlackbirdOnboard"

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Helper()
			consumable := tracker.TrackMsg(context.Background(), topic, test.partition, kafka.NewMarkedKafkaOffset(test.offset), time.Now())
			require.Equal(t, test.consumable, consumable)
		})
	}
}

func Test_GetLastCommittedOffset(t *testing.T) {
	ctx := context.Background()
	consumer := &kafkafakes.FakeIngestConsumer{}
	tracker := kafka.NewOffsetTracker(consumer)
	topic := "blackbird.v0.BlackbirdOnboard"

	// We shouldn't have an invalid topic/partition so
	// we should panic.
	// This topic/partition is invalid because the offsets have not been consumed or marked yet.
	// If lastCommittedOffset is invalid, don't return any sourceKafkaOffsets
	require.PanicsWithValue(t, "failed to get last committed offset for unknown topic/partition blackbird.v0.BlackbirdOnboard-1", func() {
		_ = tracker.GetCommittedOffset(topic, 1)
	})

	tracker.TrackMsg(context.Background(), topic, 1, kafka.NewMarkedKafkaOffset(1), time.Now())
	tracker.MarkOffset(ctx, topic, 1, kafka.NewMarkedKafkaOffset(1))
	offset := tracker.GetCommittedOffset(topic, 1)
	require.Equal(t, int64(2), offset.Get())
	require.False(t, offset.IsMarked())
}

func Test_MarkOffset(t *testing.T) {
	ctx := context.Background()
	consumer := &kafkafakes.FakeIngestConsumer{}
	tracker := kafka.NewOffsetTracker(consumer)
	topic := "blackbird.v0.BlackbirdOnboard"
	partition := int32(1)

	// Test marking offset for unknown topic/partition
	require.PanicsWithValue(t, "invalid to mark offset for unknown topic=blackbird.v0.BlackbirdOnboard partition=1", func() {
		tracker.MarkOffset(ctx, topic, partition, kafka.NewMarkedKafkaOffset(1))
	})

	// Test marking new offset - should not panic
	tracker.TrackMsg(context.Background(), topic, 1, kafka.NewMarkedKafkaOffset(1), time.Now())
	tracker.TrackMsg(context.Background(), topic, 1, kafka.NewMarkedKafkaOffset(2), time.Now())
	require.NotPanics(t, func() {
		tracker.MarkOffset(ctx, topic, partition, kafka.NewMarkedKafkaOffset(1))
	})

	// Panic when marking offset with offset <= lastCommitted
	require.PanicsWithValue(t, "cannot finish unknown offset 1", func() {
		tracker.MarkOffset(ctx, topic, partition, kafka.NewMarkedKafkaOffset(1))
	})

	// Should not error/panic when processing next valid offset and committed should be updated
	tracker.MarkOffset(ctx, topic, partition, kafka.NewMarkedKafkaOffset(2))
	offset := tracker.GetCommittedOffset(topic, partition)
	require.Equal(t, kafka.NewMarkedKafkaOffset(3), offset)

	// Marking an offset with the marked flag set should commit earlier offsets
	tracker.TrackMsg(context.Background(), topic, 1, kafka.NewMarkedKafkaOffset(3), time.Now())
	mko := helpers.MarkedKafkaOffsetWithMark(t, 4)
	tracker.TrackMsg(context.Background(), topic, 1, mko, time.Now())
	tracker.MarkOffset(ctx, topic, partition, kafka.NewMarkedKafkaOffset(3))
	tracker.MarkOffset(ctx, topic, partition, mko)
	offset = tracker.GetCommittedOffset(topic, partition)
	require.Equal(t, helpers.MarkedKafkaOffsetWithMark(t, 5), offset)
}

func Test_KafkaMarkedOffsetTrackingAppliesMarkWhenLastConsumedIsMarked(t *testing.T) {
	ctx := context.Background()
	consumer := &kafkafakes.FakeIngestConsumer{}
	tracker := kafka.NewOffsetTracker(consumer)
	topic := "blackbird.v0.BlackbirdOnboard"
	partition := int32(1)

	tracker.TrackMsg(ctx, topic, partition, kafka.NewMarkedKafkaOffset(0), time.Now())
	tracker.TrackMsg(ctx, topic, partition, helpers.MarkedKafkaOffsetWithMark(t, 1), time.Now())
	tracker.MarkOffset(ctx, topic, partition, helpers.MarkedKafkaOffsetWithMark(t, 1))
	offset := tracker.GetCommittedOffset(topic, partition)
	require.Equal(t, int64(0), offset.Get())
	require.False(t, offset.IsMarked())

	// Now, message with offset 0 is done so we can commit offset 2
	tracker.MarkOffset(ctx, topic, partition, kafka.NewMarkedKafkaOffset(0))
	offset = tracker.GetCommittedOffset(topic, partition)
	require.Equal(t, int64(2), offset.Get())
	require.True(t, offset.IsMarked(), "wtf: %s", tracker.String())
}

// Once we've seen a marked offset, future offsets should generally be marked,
// too. But even if they are missing the mark, every offset after the first
// marked one is also marked.
func Test_KafkaMarkedOffsetTrackingLargerOffsetNotMarkedPreservesEarlierMark(t *testing.T) {
	ctx := context.Background()
	consumer := &kafkafakes.FakeIngestConsumer{}
	tracker := kafka.NewOffsetTracker(consumer)
	topic := "blackbird.v0.BlackbirdOnboard"
	partition := int32(1)

	tracker.TrackMsg(ctx, topic, partition, helpers.MarkedKafkaOffsetWithMark(t, 0), time.Now())
	tracker.TrackMsg(ctx, topic, partition, kafka.NewMarkedKafkaOffset(1), time.Now()) // oops, we lost the mark
	tracker.MarkOffset(ctx, topic, partition, kafka.NewMarkedKafkaOffset(1))
	offset := tracker.GetCommittedOffset(topic, partition)
	require.Equal(t, int64(0), offset.Get())
	require.False(t, offset.IsMarked())

	// Now, message with offset 0 is done so we can commit offset 2
	tracker.MarkOffset(ctx, topic, partition, helpers.MarkedKafkaOffsetWithMark(t, 0))
	offset = tracker.GetCommittedOffset(topic, partition)
	require.Equal(t, int64(2), offset.Get())
	require.True(t, offset.IsMarked())
}

// We expect an offset to stay marked between TrackMsg and MarkOffset, but TrackMsg is what actually records the mark.
func Test_KafkaMarkedOffsetTrackingTrackMsgIsWhatSetsMark(t *testing.T) {
	ctx := context.Background()
	consumer := &kafkafakes.FakeIngestConsumer{}
	tracker := kafka.NewOffsetTracker(consumer)
	topic := "blackbird.v0.BlackbirdOnboard"
	partition := int32(1)

	tracker.TrackMsg(ctx, topic, partition, kafka.NewMarkedKafkaOffset(0), time.Now())
	tracker.TrackMsg(ctx, topic, partition, helpers.MarkedKafkaOffsetWithMark(t, 1), time.Now())

	tracker.MarkOffset(ctx, topic, partition, helpers.MarkedKafkaOffsetWithMark(t, 0)) // oops, we added the mark
	offset := tracker.GetCommittedOffset(topic, partition)
	require.Equal(t, int64(1), offset.Get())
	require.False(t, offset.IsMarked(), "offset changed mark status: %s", tracker.String())

	tracker.MarkOffset(ctx, topic, partition, kafka.NewMarkedKafkaOffset(1)) // oops, we lost the mark
	offset = tracker.GetCommittedOffset(topic, partition)
	require.Equal(t, int64(2), offset.Get())
	require.True(t, offset.IsMarked(), "offset changed mark status: %s", tracker.String())
}
