package kafka

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// Related to OffsetsCompletingNormalOrder
func Test_partitionOffsetStateCanStartAtZero(t *testing.T) {
	state := newPartitionOffsetState(0, time.Now())
	require.EqualValues(t, 0, state.lastConsumed)
	require.EqualValues(t, -1, state.lastCommitted)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[0].String())
	require.Equal(t, 1, state.pq.Len())
}

// Related to OffsetsCompletingNormalOrder
func Test_partitionOffsetState(t *testing.T) {
	state := newPartitionOffsetState(1, time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 0, state.lastCommitted)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	// consume two more
	state.markConsumed(2, time.Now())
	state.markConsumed(3, time.Now())

	require.EqualValues(t, 3, state.lastConsumed)
	require.EqualValues(t, 0, state.lastCommitted)
	require.Equal(t, 3, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, "inflight", state.inflight[2].String())
	require.Equal(t, "inflight", state.inflight[3].String())
	require.Equal(t, 3, state.pq.Len())

	// first one finishes
	offset := state.beginMarkFinished(context.Background(), 1)
	require.EqualValues(t, 1, offset)

	// lastCommitted doesn't move forward, but the the rest of our state is updated
	require.EqualValues(t, 3, state.lastConsumed)
	require.EqualValues(t, 0, state.lastCommitted)
	require.Equal(t, 2, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[2].String())
	require.Equal(t, "inflight", state.inflight[3].String())
	require.Equal(t, 2, state.pq.Len())
}

func Test_partitionOffsetStateInvalidOffset(t *testing.T) {
	require.PanicsWithValue(t, "-1 is not a valid offset", func() {
		_ = newPartitionOffsetState(-1, time.Now())
	})
}

// Related to OffsetsCompletingOutOfOrder
func Test_partitionOffsetStateOutOfOrder(t *testing.T) {
	state := newPartitionOffsetState(1, time.Now())

	require.PanicsWithValue(t, "cannot consume offset 3, last consumed offset is 1", func() {
		state.markConsumed(3, time.Now())
	})
}

// Related to OffsetsAlreadyConsumedAndCommitted
func Test_partitionOffsetStateMarkConsumeTwicePanics(t *testing.T) {
	state := newPartitionOffsetState(1, time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 0, state.lastCommitted)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	require.PanicsWithValue(t, "cannot consume offset 1, last consumed offset is 1", func() {
		state.markConsumed(1, time.Now())
	})
}

// Related to OffsetsAlreadyConsumedAndInflight
func Test_partitionOffsetStateMarkFinishWithoutConsumePanics(t *testing.T) {
	state := newPartitionOffsetState(1, time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 0, state.lastCommitted)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	require.PanicsWithValue(t, "cannot finish unknown offset 2", func() {
		_ = state.beginMarkFinished(context.Background(), 2)
	})
}

// Related to OffsetsRebalanceAwayAndBack
func Test_partitionOffsetStateSkipAndMark(t *testing.T) {
	state := newPartitionOffsetState(1, time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 0, state.lastCommitted)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	state.markConsumed(2, time.Now())
	state.markConsumed(3, time.Now())

	require.EqualValues(t, 3, state.lastConsumed)
	require.EqualValues(t, 0, state.lastCommitted)
	require.Equal(t, 3, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, "inflight", state.inflight[2].String())
	require.Equal(t, "inflight", state.inflight[3].String())
	require.Equal(t, 3, state.pq.Len())

	state.skipAndMarkConsumed(10, time.Now())

	require.EqualValues(t, 10, state.lastConsumed)
	require.EqualValues(t, 9, state.lastCommitted)
	require.Equal(t, 4, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, "inflight", state.inflight[2].String())
	require.Equal(t, "inflight", state.inflight[3].String())
	require.Equal(t, "inflight", state.inflight[10].String())
	require.Equal(t, 4, state.pq.Len())
}

func Test_partitionOffsetStateSkipAndMarkTwicePanics(t *testing.T) {
	state := newPartitionOffsetState(1, time.Now())
	require.EqualValues(t, 1, state.lastConsumed)
	require.EqualValues(t, 0, state.lastCommitted)
	require.Equal(t, 1, len(state.inflight))
	require.Equal(t, "inflight", state.inflight[1].String())
	require.Equal(t, 1, state.pq.Len())

	state.skipAndMarkConsumed(10, time.Now())
	require.PanicsWithValue(t, "already consumed offset 10", func() {
		state.skipAndMarkConsumed(10, time.Now())
	})
}
