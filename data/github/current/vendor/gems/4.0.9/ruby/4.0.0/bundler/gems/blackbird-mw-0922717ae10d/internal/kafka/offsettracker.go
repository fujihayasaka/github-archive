package kafka

import (
	"container/heap"
	"context"
	"fmt"
	"math"
	"strings"
	"sync"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

// Some hoops required to do bit manipulation.
var one uint64 = 1
var markedOffsetMask int64 = int64(one << 63)

// MarkedKafkaOffset is a kafka offset with a flag. When the flag is true, the
// offset should be sent to the indexer with the high bit set.
type MarkedKafkaOffset struct {
	offset int64
	marked bool
}

// Create a `MarkedKafkaOffset` from a Kafka offset value. The marked flag will
// be false.
//
// The offset is allowed to be negative to ease kafka offset comparisons, but
// attempting to mark a negative offset will panic.
func NewMarkedKafkaOffset(offset int64) MarkedKafkaOffset {
	return MarkedKafkaOffset{offset: offset, marked: false}
}

// Create a `MarkedKafkaOffset` from a raw value.
// I.e. this raw offset might have the marker bit set or not.
func NewMarkedKafkaOffsetFromRaw(raw int64) MarkedKafkaOffset {
	marked := (raw & markedOffsetMask) != 0
	offset := raw & ^markedOffsetMask
	return MarkedKafkaOffset{offset: offset, marked: marked}
}

// Mark this offset.
//
// Panics if offset is negative, since negative offsets cannot have the marker bit set.
func (m *MarkedKafkaOffset) Mark() {
	if m.offset < 0 {
		panic("cannot mark a negative offset")
	}

	m.marked = true
}

// Return whether the mark is set.
func (m MarkedKafkaOffset) IsMarked() bool {
	return m.marked
}

// Get the actual offset value (without the marker bit). For use when comparing
// with Kafka offsets.
func (m MarkedKafkaOffset) Get() int64 {
	return m.offset
}

// Get the raw value including the marker bit. For use when sending offsets to
// the index.
//
// Panics if offset is negative and the mark is set.
func (m MarkedKafkaOffset) Raw() int64 {
	if m.marked {
		if m.offset < 0 {
			panic("cannot mark a negative offset")
		}

		return m.offset | markedOffsetMask
	}
	return m.offset
}

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
func (o *OffsetTracker) TrackMsg(ctx context.Context, topic string, partition int32, offset MarkedKafkaOffset, ts time.Time) bool {
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
	case offset.Get() == state.lastConsumed+1:
		// next expected offset
		state.markConsumed(offset, ts)
		return true
	case offset.Get() <= state.lastConsumed:
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
func (o *OffsetTracker) MarkOffset(ctx context.Context, topic string, partition int32, offset MarkedKafkaOffset) {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	state, ok := o.partitions[PartitionKey{topic, partition}]
	if !ok {
		panic(fmt.Sprintf("invalid to mark offset for unknown topic=%s partition=%d", topic, partition))
	}

	offsetToCommit := state.beginMarkFinished(ctx, offset.Get())
	if offsetToCommit <= state.committed {
		return
	}

	// NOTE: Hydro's MarkMessage adds 1 to the message's offset, so we subtract 1 here.
	if err := o.consumer.MarkMessage(hydro.Message{Topic: topic, Partition: partition, Offset: offsetToCommit - 1}); err != nil {
		logging.Info(ctx, "failed to mark offsets, consumer rebalancing?", kvp.Err(err))
		statting.Counter(ctx, "ingest.consumer.kafka_rebalance", 1, stats.Tags{"topicpartition": fmt.Sprintf("%s-%d", topic, partition)})
		return
	}

	// record the last committed offset
	state.committed = offsetToCommit
	statting.Gauge(ctx, "ingest.consumer.kafka_offset", state.committed, stats.Tags{"topicpartition": fmt.Sprintf("%s-%d", topic, partition)})
	logging.Debug(ctx, "successfully marked offset") // NOTE: topic/partition/offset already in task.ctx
}

// GetCommittedOffset returns the committed offset for a given topic/partition. Panics if
// this topic/partition is not being tracked.
func (o *OffsetTracker) GetCommittedOffset(topic string, partition int32) MarkedKafkaOffset {
	o.mutex.Lock()
	defer o.mutex.Unlock()
	state, ok := o.partitions[PartitionKey{topic, partition}]
	if !ok {
		panic(fmt.Sprintf("failed to get last committed offset for unknown topic/partition %s-%d", topic, partition))
	}
	return MarkedKafkaOffset{offset: state.committed, marked: state.isMarked()}
}

// GetLastConsumed returns the last consumed offset and timestamp for a given
// topic/partition. Panics if this topic/partition is not being tracked.
func (o *OffsetTracker) GetLastConsumed(topic string, partition int32) (MarkedKafkaOffset, time.Time) {
	o.mutex.Lock()
	defer o.mutex.Unlock()
	state, ok := o.partitions[PartitionKey{topic, partition}]
	if !ok {
		panic(fmt.Sprintf("failed to get last consumed offset for unknown topic/partition %s-%d", topic, partition))
	}
	return MarkedKafkaOffset{offset: state.lastConsumed, marked: state.isMarked()}, state.lastConsumedTs
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
		mko := MarkedKafkaOffset{offset: state.lastConsumed, marked: state.isMarked()}
		out[pk] = LastConsumed{Offset: mko, Ts: state.lastConsumedTs}
	}

	return out
}

func (o *OffsetTracker) GetAllCommitted() map[PartitionKey]MarkedKafkaOffset {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	out := make(map[PartitionKey]MarkedKafkaOffset, len(o.partitions))
	for pk, state := range o.partitions {
		out[pk] = MarkedKafkaOffset{offset: state.committed, marked: state.isMarked()}
	}

	return out
}

// Represent the current state of the OffsetTracker as a string for debugging.
func (o *OffsetTracker) String() string {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	partitions := []string{}
	for pk, state := range o.partitions {
		partition := fmt.Sprintf("[topic=%s, partition=%d]: lastConsumed=%d, committed=%d, earliestMarked=%d", pk.Topic, pk.Partition, state.lastConsumed, state.committed, state.earliestMarked)
		partitions = append(partitions, partition)
	}
	return fmt.Sprintf("OffsetTracker{%s}", strings.Join(partitions, ", "))
}

type LastConsumed struct {
	Offset MarkedKafkaOffset
	Ts     time.Time
}

type PartitionKey struct {
	Topic     string
	Partition int32
}

// The state of offsets on an individual partition.
//
// Invariant:
// - offsets start at zero
type partitionOffsetState struct {
	// Kafka offset of the last message seen on this partition.
	lastConsumed int64
	// Kafka message timestamp of the last message seen on this partition.
	lastConsumedTs time.Time
	// Committed Kafka offset. Remember that this is the offset of the NEXT message to consume.
	committed int64
	// Keeps track of messages that have not been committed yet.
	inflight map[int64]offsetState
	// First message offset seen that had the mark set.
	earliestMarked int64
	// Priority queue of offsets for inflight messages.
	pq priorityQueue
}

func newPartitionOffsetState(offset MarkedKafkaOffset, ts time.Time) *partitionOffsetState {
	if offset.Get() < 0 {
		panic(fmt.Sprintf("%d is not a valid offset", offset.Get()))
	}

	var earliestMarked int64 = math.MaxInt64
	if offset.IsMarked() {
		earliestMarked = offset.Get()
	}

	pq := make(priorityQueue, 0)
	heap.Init(&pq)
	heap.Push(&pq, offset.Get())
	return &partitionOffsetState{
		lastConsumed:   offset.Get(),
		lastConsumedTs: ts,
		// NB: this is the first offset we've received for the topic/partition,
		// assume we've committed up to this point.
		committed:      offset.Get(),
		inflight:       map[int64]offsetState{offset.Get(): inflight},
		earliestMarked: earliestMarked,
		pq:             pq,
	}
}

func (p *partitionOffsetState) markConsumed(offset MarkedKafkaOffset, ts time.Time) {
	if p.lastConsumed+1 != offset.Get() {
		panic(fmt.Sprintf("cannot consume offset %d, last consumed offset is %d", offset.Get(), p.lastConsumed))
	}

	if offset.Get() < p.committed {
		panic(fmt.Sprintf("cannot consume offset %d, must be >= committed offset %d", offset.Get(), p.committed))
	}

	if _, ok := p.inflight[offset.Get()]; ok {
		panic(fmt.Sprintf("already consumed offset %d", offset.Get()))
	}

	if offset.IsMarked() {
		p.earliestMarked = min(offset.Get(), p.earliestMarked)
	}

	p.lastConsumed = offset.Get()
	p.lastConsumedTs = ts
	p.inflight[offset.Get()] = inflight
	heap.Push(&p.pq, offset.Get())
}

// Assumes that all offsets before this one have been consumed and committed and update earliest marked if necessary.
func (p *partitionOffsetState) skipAndMarkConsumed(offset MarkedKafkaOffset, ts time.Time) {
	if _, ok := p.inflight[offset.Get()]; ok {
		panic(fmt.Sprintf("already consumed offset %d", offset.Get()))
	}

	if offset.IsMarked() {
		p.earliestMarked = min(offset.Get(), p.earliestMarked)
	}

	p.lastConsumed = offset.Get()
	p.lastConsumedTs = ts
	p.committed = offset.Get()
	p.inflight[offset.Get()] = inflight
	heap.Push(&p.pq, offset.Get())
}

// Marks the offset as finished and returns the offset to commit in Kafka.
//
// You can only finish an offset if a matching call to markConsumed or
// skipAndMarkConsumed has been made.
func (p *partitionOffsetState) beginMarkFinished(ctx context.Context, offset int64) int64 {
	if p.committed > offset {
		// this happens when we skipAndMarkConsumed (when a partition is assigned to
		// another pod which does work and then re-assigned back to this pod).
		logging.Info(ctx, "marking offset as finished but it is earlier than the committed offset", kvp.Int64("committed_offset", p.committed))
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

	// Compute a safe to commit offset (if any)
	safeToCommit := p.committed
	for p.pq.Len() != 0 {
		off := heap.Pop(&p.pq).(int64)
		state, ok := p.inflight[off]
		if ok && state == finished {
			safeToCommit = max(off+1, safeToCommit)
			delete(p.inflight, off)
			continue
		}

		// NB: This one isn't finished, b/c we don't have a Peek, push it back on the heap.
		heap.Push(&p.pq, off)
		break
	}

	return safeToCommit
}

func (p *partitionOffsetState) isMarked() bool {
	return p.committed > p.earliestMarked
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
