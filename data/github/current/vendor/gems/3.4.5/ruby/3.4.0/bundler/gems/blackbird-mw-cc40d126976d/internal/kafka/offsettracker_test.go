package kafka_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
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
			consumable := tracker.TrackMsg(context.Background(), topic, test.partition, test.offset, time.Now())
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
		_ = tracker.GetLastCommittedOffset(topic, 1)
	})

	tracker.TrackMsg(context.Background(), topic, 1, 1, time.Now())
	tracker.MarkOffset(ctx, topic, 1, 1)
	offset := tracker.GetLastCommittedOffset(topic, 1)
	require.Equal(t, int64(1), offset)
}

func Test_MarkOffset(t *testing.T) {
	ctx := context.Background()
	consumer := &kafkafakes.FakeIngestConsumer{}
	tracker := kafka.NewOffsetTracker(consumer)
	topic := "blackbird.v0.BlackbirdOnboard"
	partition := int32(1)
	offset := int64(1)

	// Test marking offset for unknown topic/partition
	require.PanicsWithValue(t, "invalid to mark offset for unknown topic=blackbird.v0.BlackbirdOnboard partition=1", func() {
		tracker.MarkOffset(ctx, topic, partition, offset)
	})

	// Test marking new offset - should not panic
	tracker.TrackMsg(context.Background(), topic, 1, 1, time.Now())
	tracker.TrackMsg(context.Background(), topic, 1, 2, time.Now())
	require.NotPanics(t, func() {
		tracker.MarkOffset(ctx, topic, partition, 1)
	})

	// Panic when marking offset with offset <= lastCommitted
	require.PanicsWithValue(t, "cannot finish unknown offset 1", func() {
		tracker.MarkOffset(ctx, topic, partition, 1)
	})

	// Should not error/panic when processing next valid offset and lastCommittedOffset should be updated
	tracker.MarkOffset(ctx, topic, partition, 2)
	offset = tracker.GetLastCommittedOffset(topic, partition)
	require.Equal(t, int64(2), offset)
}
