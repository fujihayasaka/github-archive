package kafka

import (
	"container/heap"
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

// An operation that tracks Kafka offsets for each topic/partition
// being consumed.
type OffsetTracker struct {
	consumer   IngestConsumer
	partitions map[PartitionKey]*partitionOffsetState
	mutex      *sync.Mutex
}

func NewOffsetTracker(consumer IngestConsumer) *OffsetTracker {
	return &OffsetTracker{
		consumer:   consumer,
		partitions: map[PartitionKey]*partitionOffsetState{},
		mutex:      &sync.Mutex{},
	}
}

// TrackMsg begins tracking state for a given kafka message (identified by topic, partition, offset)
// so that it can later be marked committed (See `MarkOffset`).
//
// Returns true if this message should be processed. Returns false if the offset has already been
// consumed (someone else called `TrackMsg` on this offset already).
func (o *OffsetTracker) TrackMsg(ctx context.Context, topic string, partition int32, offset int64, ts time.Time) bool {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	key := PartitionKey{topic, partition}
	state, ok := o.partitions[key]
	if !ok {
		// first offset for this topic/partition: ok to run
		logging.Info(ctx, "offset tracking: consuming first offset for this partition")
		o.partitions[key] = newPartitionOffsetState(offset, ts)
		return true
	}

	switch {
	case offset == state.lastConsumed+1:
		// next expected offset
		state.markConsumed(offset, ts)
		return true
	case offset <= state.lastConsumed:
		// replay of a message we've already consumed
		logging.Info(ctx, "offset tracking: already consumed this committed offset", kvp.Int64("last_consumed_offset", state.lastConsumed))
		return false
	default:
		// we skipped some offsets: we must update our state to
		// record that we've skipped ahead in the partition.
		//
		// This can happen during a rebalance: e.g., a partition is moved to
		// another pod (which commits offsets) and then reassigned back to this
		// pod which starts consuming again, but from a later offset.
		logging.Info(ctx, "offset tracking: skipped over some offsets: run task and fast forward state", kvp.Int64("last_consumed_offset", state.lastConsumed))
		state.skipAndMarkConsumed(offset, ts)
		return true
	}
}

// Mark this message's offset as finished and commit any outstanding offsets to
// Kafka.
//
// We update internal state transactionally by calling `commit()` iff
// MarkMessage succeeds as a failure to mark means a rebalance (this pod is no
// longer assigned to this partition and cannot mark offsets).
//
// If the rebalanced partition is never assigned back to this pod we'll leave a
// little extra state for the topic/partition hanging around but that's OK.
//
// If the rebalanced partition is ever assigned back to this pod we'll be able
// to ensure that downstream operations on this task receive tasks once and only
// once in strict monotonically increasing offset order.
//
// NB: Even if MarkMessage returns successfully: it is still possible to
// re-receive this same message/offset as the actual committing of offsets to
// Kafka is async. From the ConsumerGroupSession.MarkOffset docs:
//
//	Note: calling MarkOffset does not necessarily commit the offset to the backend
//	store immediately for efficiency reasons, and it may never be committed if
//	your application crashes. This means that you may end up processing the same
//	message twice, and your processing should ideally be idempotent.
//
// The OffsetTracker state tracking properly handles these sorts of message
// replays.
func (o *OffsetTracker) MarkOffset(ctx context.Context, topic string, partition int32, offset int64) {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	state, ok := o.partitions[PartitionKey{topic, partition}]
	if !ok {
		panic(fmt.Sprintf("invalid to mark offset for unknown topic=%s partition=%d", topic, partition))
	}

	offset = state.beginMarkFinished(ctx, offset)
	if offset <= state.lastCommitted {
		return
	}

	if err := o.consumer.MarkMessage(hydro.Message{Topic: topic, Partition: partition, Offset: offset}); err != nil {
		logging.Info(ctx, "failed to mark offsets, consumer rebalancing?", kvp.Err(err))
		statting.Counter(ctx, "ingest.consumer.kafka_rebalance", 1, stats.Tags{"topicpartition": fmt.Sprintf("%s-%d", topic, partition)})
		return
	}

	// record the last committed offset
	state.lastCommitted = offset
	statting.Gauge(ctx, "ingest.consumer.kafka_offset", offset, stats.Tags{"topicpartition": fmt.Sprintf("%s-%d", topic, partition)})
	logging.Info(ctx, "successfully marked offset") // NOTE: topic/partition/offset already in task.ctx
}

// GetLastCommittedOffset returns the last committed offset for a given topic/partition. Panics if
// this topic/partition is not being tracked.
func (o *OffsetTracker) GetLastCommittedOffset(topic string, partition int32) int64 {
	o.mutex.Lock()
	defer o.mutex.Unlock()
	state, ok := o.partitions[PartitionKey{topic, partition}]
	if !ok {
		panic(fmt.Sprintf("failed to get last committed offset for unknown topic/partition %s-%d", topic, partition))
	}
	return state.lastCommitted
}

// GetLastConsumed returns the last consumed offset and timestamp for a given
// topic/partition. Panics if this topic/partition is not being tracked.
func (o *OffsetTracker) GetLastConsumed(topic string, partition int32) (int64, time.Time) {
	o.mutex.Lock()
	defer o.mutex.Unlock()
	state, ok := o.partitions[PartitionKey{topic, partition}]
	if !ok {
		panic(fmt.Sprintf("failed to get last consumed offset for unknown topic/partition %s-%d", topic, partition))
	}
	return state.lastConsumed, state.lastConsumedTs
}

// GetAllLastConsumed returns the last consumed offset and timestamp for every
// Topic/Partition.
//
// Prefer GetLastConsumed when dealing with a single topic/partition, for
// example when processing an ingest event.
func (o *OffsetTracker) GetAllLastConsumed() map[PartitionKey]LastConsumed {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	out := make(map[PartitionKey]LastConsumed, len(o.partitions))
	for pk, state := range o.partitions {
		out[pk] = LastConsumed{Offset: state.lastConsumed, Ts: state.lastConsumedTs}
	}

	return out
}

func (o *OffsetTracker) GetAllLastCommitted() map[PartitionKey]int64 {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	out := make(map[PartitionKey]int64, len(o.partitions))
	for pk, state := range o.partitions {
		out[pk] = state.lastCommitted
	}

	return out
}

type LastConsumed struct {
	Offset int64
	Ts     time.Time
}

type PartitionKey struct {
	Topic     string
	Partition int32
}

// The state of offsets on an individual partition.
//
// Invariants:
// - offsets start at zero
// - lastConsumed >= lastCommitted
type partitionOffsetState struct {
	lastConsumed   int64
	lastConsumedTs time.Time
	lastCommitted  int64
	inflight       map[int64]offsetState
	pq             priorityQueue
}

func newPartitionOffsetState(offset int64, ts time.Time) *partitionOffsetState {
	if offset < 0 {
		panic(fmt.Sprintf("%d is not a valid offset", offset))
	}

	pq := make(priorityQueue, 0)
	heap.Init(&pq)
	heap.Push(&pq, offset)
	return &partitionOffsetState{
		lastConsumed:   offset,
		lastConsumedTs: ts,
		// NB: this is the first offset we've received for the topic/partition,
		// assume we've committed up to this point.
		lastCommitted: offset - 1,
		inflight:      map[int64]offsetState{offset: inflight},
		pq:            pq,
	}
}

func (p *partitionOffsetState) markConsumed(offset int64, ts time.Time) {
	if p.lastConsumed+1 != offset {
		panic(fmt.Sprintf("cannot consume offset %d, last consumed offset is %d", offset, p.lastConsumed))
	}

	if offset < p.lastCommitted {
		panic(fmt.Sprintf("cannot consume offset %d, must be >= last committed offset %d", offset, p.lastCommitted))
	}

	if _, ok := p.inflight[offset]; ok {
		panic(fmt.Sprintf("already consumed offset %d", offset))
	}

	p.lastConsumed = offset
	p.lastConsumedTs = ts
	p.inflight[offset] = inflight
	heap.Push(&p.pq, offset)
}

// Assumes that all offsets before this one have been consumed and committed.
func (p *partitionOffsetState) skipAndMarkConsumed(offset int64, ts time.Time) {
	if _, ok := p.inflight[offset]; ok {
		panic(fmt.Sprintf("already consumed offset %d", offset))
	}

	p.lastConsumed = offset
	p.lastConsumedTs = ts
	p.lastCommitted = offset - 1
	p.inflight[offset] = inflight
	heap.Push(&p.pq, offset)
}

// Marks the offset as finished and computes a safe to commit offset (if any).
// You can only finish an offset if a matching call to markConsumed or
// skipAndMarkConsumed has been made.
func (p *partitionOffsetState) beginMarkFinished(ctx context.Context, offset int64) int64 {
	if p.lastCommitted > offset {
		// this happens when we skipAndMarkConsumed (when a partition is assigned to
		// another pod which does work and then re-assigned back to this pod).
		logging.Info(ctx, "marking offset as finished but it is earlier than the last committed offset", kvp.Int64("last_committed_offset", p.lastCommitted))
	}

	if _, ok := p.inflight[offset]; !ok {
		panic(fmt.Sprintf("cannot finish unknown offset %d", offset))
	}

	if p.inflight[offset] != inflight {
		// TODO: Can we test this panic?
		panic(fmt.Sprintf("cannot finish offset %d that's not inflight", offset))
	}

	// Mark this offset as finished
	p.inflight[offset] = finished

	// Compute a safe to commit offset (if any) on a copy of the priorityQueue and
	// return a func to commit this state change.
	safeToCommit := p.lastCommitted
	for {
		if p.pq.Len() == 0 {
			break
		}

		off := heap.Pop(&p.pq).(int64)
		state, ok := p.inflight[off]
		if ok && state == finished {
			safeToCommit = off
			delete(p.inflight, off)
			continue
		}

		// NB: This one isn't finished, b/c we don't have a Peek, push it back on the heap.
		safeToCommit = off - 1
		heap.Push(&p.pq, off)
		break
	}

	return safeToCommit
}

type offsetState int

func (o offsetState) String() string {
	return []string{"inflight", "finished"}[o]
}

const (
	inflight offsetState = iota
	finished
)

// Implement a Priority Queue using the heap interface. From the example in the
// Go documentation: https://pkg.go.dev/container/heap
type priorityQueue []int64

func (pq priorityQueue) Len() int { return len(pq) }

func (pq priorityQueue) Less(i, j int) bool {
	return pq[i] < pq[j]
}

func (pq *priorityQueue) Pop() interface{} {
	old := *pq
	n := len(old)
	item := old[n-1]
	*pq = old[0 : n-1]
	return item
}

func (pq *priorityQueue) Push(x interface{}) {
	item := x.(int64)
	*pq = append(*pq, item)
}

func (pq priorityQueue) Swap(i, j int) {
	pq[i], pq[j] = pq[j], pq[i]
}
