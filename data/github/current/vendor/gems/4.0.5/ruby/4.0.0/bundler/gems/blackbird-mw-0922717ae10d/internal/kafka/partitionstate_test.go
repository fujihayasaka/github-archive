package kafka

import (
	"context"
	"math"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// Related to OffsetsCompletingNormalOrder
func Test_partitionOffsetStateCanStartAtZero(t *testing.T) {
	state := newPartitionOffsetState(NewMarkedKafkaOffset(0), time.Now())
	require.EqualValues(t, 0, state.lastConsumed)
	require.EqualValues(t, 0, state.committed)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[0].String())
	require.Equal(t, 1, state.pq.Len())
}

// Related to OffsetsCompletingNormalOrder
func Test_partitionOffsetState(t *testing.T) {
	state := newPartitionOffsetState(NewMarkedKafkaOffset(1), time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 1, state.committed)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	// consume two more
	state.markConsumed(NewMarkedKafkaOffset(2), time.Now())
	state.markConsumed(NewMarkedKafkaOffset(3), time.Now())

	require.EqualValues(t, 3, state.lastConsumed)
	require.EqualValues(t, 1, state.committed)
	require.Equal(t, 3, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, "inflight", state.inflight[2].String())
	require.Equal(t, "inflight", state.inflight[3].String())
	require.Equal(t, 3, state.pq.Len())

	// first one finishes
	offset := state.beginMarkFinished(context.Background(), 1)
	require.EqualValues(t, 2, offset)

	// committed doesn't move forward, but the the rest of our state is updated
	require.EqualValues(t, 3, state.lastConsumed)
	require.EqualValues(t, 1, state.committed)
	require.Equal(t, 2, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[2].String())
	require.Equal(t, "inflight", state.inflight[3].String())
	require.Equal(t, 2, state.pq.Len())
}

func Test_partitionOffsetStateInvalidOffset(t *testing.T) {
	require.PanicsWithValue(t, "-1 is not a valid offset", func() {
		_ = newPartitionOffsetState(NewMarkedKafkaOffset(-1), time.Now())
	})
}

// Related to OffsetsCompletingOutOfOrder
func Test_partitionOffsetStateOutOfOrder(t *testing.T) {
	state := newPartitionOffsetState(NewMarkedKafkaOffset(1), time.Now())

	require.PanicsWithValue(t, "cannot consume offset 3, last consumed offset is 1", func() {
		state.markConsumed(NewMarkedKafkaOffset(3), time.Now())
	})
}

// Related to OffsetsAlreadyConsumedAndCommitted
func Test_partitionOffsetStateMarkConsumeTwicePanics(t *testing.T) {
	state := newPartitionOffsetState(NewMarkedKafkaOffset(1), time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 1, state.committed)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	require.PanicsWithValue(t, "cannot consume offset 1, last consumed offset is 1", func() {
		state.markConsumed(NewMarkedKafkaOffset(1), time.Now())
	})
}

// Related to OffsetsAlreadyConsumedAndInflight
func Test_partitionOffsetStateMarkFinishWithoutConsumePanics(t *testing.T) {
	state := newPartitionOffsetState(NewMarkedKafkaOffset(1), time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 1, state.committed)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	require.PanicsWithValue(t, "cannot finish unknown offset 2", func() {
		_ = state.beginMarkFinished(context.Background(), 2)
	})
}

// Related to OffsetsRebalanceAwayAndBack
func Test_partitionOffsetStateSkipAndMark(t *testing.T) {
	state := newPartitionOffsetState(NewMarkedKafkaOffset(1), time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 1, state.committed)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	state.markConsumed(NewMarkedKafkaOffset(2), time.Now())
	state.markConsumed(NewMarkedKafkaOffset(3), time.Now())

	require.EqualValues(t, 3, state.lastConsumed)
	require.EqualValues(t, 1, state.committed)
	require.Equal(t, 3, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, "inflight", state.inflight[2].String())
	require.Equal(t, "inflight", state.inflight[3].String())
	require.Equal(t, 3, state.pq.Len())

	state.skipAndMarkConsumed(NewMarkedKafkaOffset(10), time.Now())

	require.EqualValues(t, 10, state.lastConsumed)
	require.EqualValues(t, 10, state.committed)
	require.EqualValues(t, math.MaxInt64, state.earliestMarked) // no marked offsets seen yet
	require.Equal(t, 4, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, "inflight", state.inflight[2].String())
	require.Equal(t, "inflight", state.inflight[3].String())
	require.Equal(t, "inflight", state.inflight[10].String())
	require.Equal(t, 4, state.pq.Len())

	// Mark the skipped over offsets done and see that offsetToCommit is the committed offset
	offsetToCommit := state.beginMarkFinished(context.Background(), 1)
	require.EqualValues(t, 10, offsetToCommit)
	require.EqualValues(t, 10, state.lastConsumed)
	require.EqualValues(t, 10, state.committed)

	offsetToCommit = state.beginMarkFinished(context.Background(), 2)
	require.EqualValues(t, 10, offsetToCommit)
	require.EqualValues(t, 10, state.lastConsumed)
	require.EqualValues(t, 10, state.committed)

	offsetToCommit = state.beginMarkFinished(context.Background(), 3)
	require.EqualValues(t, 10, offsetToCommit)
	require.EqualValues(t, 10, state.lastConsumed)
	require.EqualValues(t, 10, state.committed)

	// Finishing the offset we skipped to now increments the offset to commit
	offsetToCommit = state.beginMarkFinished(context.Background(), 10)
	require.EqualValues(t, 11, offsetToCommit)
	require.EqualValues(t, 10, state.lastConsumed)
	require.EqualValues(t, 10, state.committed)
	require.Equal(t, 0, len(state.inflight))
	require.Equal(t, 0, state.pq.Len())
}

func Test_partitionOffsetStateSkipAndMarkTwicePanics(t *testing.T) {
	state := newPartitionOffsetState(NewMarkedKafkaOffset(1), time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 1, state.committed)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	state.skipAndMarkConsumed(NewMarkedKafkaOffset(10), time.Now())
	require.PanicsWithValue(t, "already consumed offset 10", func() {
		state.skipAndMarkConsumed(NewMarkedKafkaOffset(10), time.Now())
	})
}
