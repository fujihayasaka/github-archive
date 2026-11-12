package deltaingest

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
)

const (
	topic     = "example.topic"
	partition = 1
)

func Test_OffsetsCompletingNormalOrder(t *testing.T) {
	consumer := &kafkafakes.FakeIngestConsumer{}
	sink := NewTestCollectOp()
	offsetTracker := kafka.NewOffsetTracker(consumer)
	op := NewOffsetTrackingOp(offsetTracker, sink)

	op.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 0))
	op.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 1))

	require.Equal(t, 2, len(sink.tasks))
	require.Equal(t, 0, len(sink.finishedTasks))
	require.Equal(t, 0, consumer.MarkMessageCallCount()) // no offset should have been marked yet

	// will finish offset=1 (the first task)
	sink.FinishFirstOne(nil)

	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 1, consumer.MarkMessageCallCount())                 // should have committed this offset
	require.EqualValues(t, 0, consumer.MarkMessageArgsForCall(0).Offset) // safeToCommit should be offset=1
	require.EqualValues(t, partition, consumer.MarkMessageArgsForCall(0).Partition)
	require.Equal(t, topic, consumer.MarkMessageArgsForCall(0).Topic)

	// will finish offset=2 (the second task)
	sink.FinishFirstOne(nil)

	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 2, len(sink.finishedTasks))
	require.Equal(t, 2, consumer.MarkMessageCallCount())                 // another offset safe to commit now
	require.EqualValues(t, 1, consumer.MarkMessageArgsForCall(1).Offset) // safeToCommit should be offset=2
	require.EqualValues(t, partition, consumer.MarkMessageArgsForCall(1).Partition)
	require.Equal(t, topic, consumer.MarkMessageArgsForCall(1).Topic)
}

func Test_OffsetsCompletingOutOfOrder(t *testing.T) {
	consumer := &kafkafakes.FakeIngestConsumer{}
	sink := NewTestCollectOp()
	offsetTracker := kafka.NewOffsetTracker(consumer)
	op := NewOffsetTrackingOp(offsetTracker, sink)

	op.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 1))
	op.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 2))

	require.Equal(t, 2, len(sink.tasks))
	require.Equal(t, 0, len(sink.finishedTasks))
	require.Equal(t, 0, consumer.MarkMessageCallCount()) // no offset should have been marked yet

	// will finish offset=2 (the second task)
	sink.FinishLastOne(nil)

	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 0, consumer.MarkMessageCallCount()) // no calls to MarkMessage

	// will finish offset=1 (the first task): should commit all offsets now
	sink.FinishLastOne(nil)

	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 2, len(sink.finishedTasks))
	require.Equal(t, 1, consumer.MarkMessageCallCount())                 // offsets safe to commit now
	require.EqualValues(t, 2, consumer.MarkMessageArgsForCall(0).Offset) // safeToCommit should be offset=2
	require.EqualValues(t, partition, consumer.MarkMessageArgsForCall(0).Partition)
	require.Equal(t, topic, consumer.MarkMessageArgsForCall(0).Topic)
}

func Test_OffsetsAlreadyConsumedAndCommitted(t *testing.T) {
	consumer := &kafkafakes.FakeIngestConsumer{}
	sink := NewTestCollectOp()
	offsetTracker := kafka.NewOffsetTracker(consumer)
	op := NewOffsetTrackingOp(offsetTracker, sink)
	buf := NewBufferOp(op)

	// run a task and finish it (should consume and mark/commit offset)
	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 1))
	sink.FinishLastOne(nil)

	require.Equal(t, 1, len(buf.inTasks))
	require.Equal(t, 1, len(buf.doneTasks))
	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 1, consumer.MarkMessageCallCount())                 // offsets safe to commit now
	require.EqualValues(t, 1, consumer.MarkMessageArgsForCall(0).Offset) // safeToCommit should be offset=1
	require.EqualValues(t, partition, consumer.MarkMessageArgsForCall(0).Partition)
	require.Equal(t, topic, consumer.MarkMessageArgsForCall(0).Topic)

	// run the exact same task again: this is a noop
	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 1))

	// we ran and marked this second task done
	require.Equal(t, 2, len(buf.inTasks))
	require.Equal(t, 2, len(buf.doneTasks))
	// all other state should be identical
	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 1, consumer.MarkMessageCallCount())                 // offsets safe to commit now
	require.EqualValues(t, 1, consumer.MarkMessageArgsForCall(0).Offset) // safeToCommit should be offset=1
	require.EqualValues(t, partition, consumer.MarkMessageArgsForCall(0).Partition)
	require.Equal(t, topic, consumer.MarkMessageArgsForCall(0).Topic)
}

func Test_OffsetsAlreadyConsumedAndInflight(t *testing.T) {
	consumer := &kafkafakes.FakeIngestConsumer{}
	sink := NewTestCollectOp()
	offsetTracker := kafka.NewOffsetTracker(consumer)
	op := NewOffsetTrackingOp(offsetTracker, sink)
	buf := NewBufferOp(op)

	// run a task so that it's inflight
	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 1))

	require.Equal(t, 1, len(buf.inTasks))
	require.Equal(t, 0, len(buf.doneTasks))
	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 0, len(sink.finishedTasks))
	require.Equal(t, 0, consumer.MarkMessageCallCount())

	// run the exact same task: this is a noop
	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 1))

	// we sent two tasks, the duplicate was immediately marked as done
	require.Equal(t, 2, len(buf.inTasks))
	require.Equal(t, 1, len(buf.doneTasks))
	// the rest of our state is the same
	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 0, len(sink.finishedTasks))
	require.Equal(t, 0, consumer.MarkMessageCallCount())
}

func Test_OffsetsAlreadyConsumedNotCommittedOrInflight(t *testing.T) {
	consumer := &kafkafakes.FakeIngestConsumer{}
	sink := NewTestCollectOp()
	offsetTracker := kafka.NewOffsetTracker(consumer)
	op := NewOffsetTrackingOp(offsetTracker, sink)
	buf := NewBufferOp(op)

	// simulate a task that failed to commit offsets
	consumer.MarkMessageReturns(errors.New("rebalance"))
	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 1))
	sink.FinishLastOne(nil)

	require.Equal(t, 1, len(buf.inTasks))
	require.Equal(t, 1, len(buf.doneTasks))
	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 1, consumer.MarkMessageCallCount())
	require.EqualValues(t, 1, consumer.MarkMessageArgsForCall(0).Offset) // safeToCommit should be offset=1
	require.EqualValues(t, partition, consumer.MarkMessageArgsForCall(0).Partition)
	require.Equal(t, topic, consumer.MarkMessageArgsForCall(0).Topic)

	// now simulate that we receive an identical message
	// as far as we're concerned, we've moved on so this is a noop, but the next task on the partition will run and commit offsets as expected
	consumer.MarkMessageReturns(nil) // committing offsets is allowed to succeed this time
	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 1))

	require.Equal(t, 2, len(buf.inTasks))
	require.Equal(t, 2, len(buf.doneTasks))
	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 1, consumer.MarkMessageCallCount()) // there were no more calls to MarkMessage

	// here's our next offset
	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 2))

	require.Equal(t, 3, len(buf.inTasks))
	require.Equal(t, 2, len(buf.doneTasks))
	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 1, consumer.MarkMessageCallCount()) // there were no more calls to MarkMessage

	// run that task: now we should get back in sync with kafka
	sink.FinishLastOne(nil)

	require.Equal(t, 3, len(buf.inTasks))
	require.Equal(t, 3, len(buf.doneTasks))
	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 2, len(sink.finishedTasks))
	require.Equal(t, 2, consumer.MarkMessageCallCount())                 // one more call to MarkMessage
	require.EqualValues(t, 2, consumer.MarkMessageArgsForCall(1).Offset) // safeToCommit should be offset=1
	require.EqualValues(t, partition, consumer.MarkMessageArgsForCall(1).Partition)
	require.Equal(t, topic, consumer.MarkMessageArgsForCall(1).Topic)
}

// Tests the scenario where a partition is rebalanced away and the back again:
//
// a pod consumes 1 message
// rebalance
// partition is assigned and new pod
// new pod consumes, processes and commits an offset
// partition is then assigned back to original pod
// original pod consumes...
func Test_OffsetsRebalanceAwayAndBack(t *testing.T) {
	consumer := &kafkafakes.FakeIngestConsumer{}
	offsetTracker := kafka.NewOffsetTracker(consumer)
	sink := NewTestCollectOp()
	op := NewOffsetTrackingOp(offsetTracker, sink)
	buf := NewBufferOp(op)

	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 0))

	require.Equal(t, 1, len(buf.inTasks))
	require.Equal(t, 0, len(buf.doneTasks))
	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 0, len(sink.finishedTasks))
	require.Equal(t, 0, consumer.MarkMessageCallCount())

	// rebalance:
	// 2nd pod consumes offset=0, does work, commits offset
	// 2nd pod consumes offset=1, does work, commits offset
	// rebalance:
	// 1st pod consumes offset=2...

	buf.Run(newTaskWithTopicPartitionOffset(t, topic, partition, 2))

	require.Equal(t, 2, len(buf.inTasks))
	require.Equal(t, 0, len(buf.doneTasks))
	require.Equal(t, 2, len(sink.tasks))
	require.Equal(t, 0, len(sink.finishedTasks))
	require.Equal(t, 0, consumer.MarkMessageCallCount())

	// finish offset=0 (the offset that was processed by another pod too)
	sink.FinishFirstOne(nil)

	require.Equal(t, 2, len(buf.inTasks))
	require.Equal(t, 1, len(buf.doneTasks))
	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 0, consumer.MarkMessageCallCount()) // no call to MarkMessage

	// finish offset=2
	sink.FinishFirstOne(nil)

	require.Equal(t, 2, len(buf.inTasks))
	require.Equal(t, 2, len(buf.doneTasks))
	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 2, len(sink.finishedTasks))
	require.Equal(t, 1, consumer.MarkMessageCallCount())                 // called MarkMessage again
	require.EqualValues(t, 2, consumer.MarkMessageArgsForCall(0).Offset) // safeToCommit should be offset=2
	require.EqualValues(t, partition, consumer.MarkMessageArgsForCall(0).Partition)
	require.Equal(t, topic, consumer.MarkMessageArgsForCall(0).Topic)
}
