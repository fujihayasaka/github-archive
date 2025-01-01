package kafka

import (
	"context"
	"sync"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/utils"
)

// DelayedTimestampReader uses Kafka (via a MessageReader interface) to find messages on the source
// topic with a timestamp at least 10 minutes old. It then keeps track of that message's delayed
// timestamp (per partition) and allows computing lag as compared to the source kafka info
// timestamps we persist in the indexers.
type DelayedTimestampReader struct {
	getReader  func() MessageReader
	topic      string
	mutex      sync.RWMutex
	timestamps map[int32]time.Time
}

func NewDelayedTimestampReader(getReader func() MessageReader, topic string) *DelayedTimestampReader {
	return &DelayedTimestampReader{getReader, topic, sync.RWMutex{}, make(map[int32]time.Time)}
}

// Runs a goroutine to keep the delayed timestamps up-to-date, computes the current state once up
// front before it returns. Runs until the context is cancelled.
func (d *DelayedTimestampReader) Run(ctx context.Context) {
	// compute once up front, then keep the value up-to-date on a ticker
	d.Refresh(ctx)

	go func() {
		defer utils.PanicLogger(ctx)

		ticker := time.NewTicker(1 * time.Minute)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				d.Refresh(ctx)
			case <-ctx.Done():
				return
			}
		}
	}()
}

const noLag = 0 * time.Second
const unknownLag = 24 * time.Hour

// For the partition p, returns the time since t as compared to the cached (delayed) message's timestamp.
func (d *DelayedTimestampReader) Since(t time.Time, p int32) time.Duration {
	d.mutex.RLock()
	defer d.mutex.RUnlock()

	ts := d.timestamps[p]
	switch {
	case ts.IsZero():
		return noLag
	case ts == unableToReadMarker:
		return unknownLag
	default:
		return d.timestamps[p].Sub(t)
	}
}

// For all partitions, returns the time since t as compared to the cached (delayed) message's timestamp.
func (d *DelayedTimestampReader) SinceAll(t time.Time) []time.Duration {
	d.mutex.RLock()
	defer d.mutex.RUnlock()

	timestamps := make([]time.Duration, len(d.timestamps))
	for p, ts := range d.timestamps {
		switch {
		case ts.IsZero():
			timestamps[p] = noLag
		case ts == unableToReadMarker:
			timestamps[p] = unknownLag
		default:
			timestamps[p] = ts.Sub(t)
		}
	}
	return timestamps
}

// Refresh the cache of delayed timestamps for each partition. This is called by `Run` on an
// interval.
func (d *DelayedTimestampReader) Refresh(ctx context.Context) {
	reader := d.getReader()
	defer reader.Close()

	ps, err := reader.Partitions(d.topic)
	if err != nil {
		logging.Error(ctx, "failed to get partitions", kvp.Err(err))
		return
	}
	partitionCount := int32(len(ps))

	// get an offset from _delay_ mins ago on each partition
	const delayWindow = -10 * time.Minute
	ts := time.Now().Add(delayWindow).UnixMilli()
	for p := int32(0); p < partitionCount; p++ {
		// NB: Important to fill each slot in the map with a timestamp, even if it's zero.
		d.set(d.getTimestamp(ctx, reader, p, ts), p)
	}
}

func (d *DelayedTimestampReader) set(l time.Time, partition int32) {
	d.mutex.Lock()
	defer d.mutex.Unlock()

	if l.After(d.timestamps[partition]) {
		d.timestamps[partition] = l
	}
}

var zeroLagMarker = time.Time{}
var unableToReadMarker = time.UnixMilli(1)

// getTimeStamp returns the LogAppendTime of the message strictly earlier than the provided delayed timestamp
// (our delay window of 10 mins ago) for the purposes of reporting lag.
func (d *DelayedTimestampReader) getTimestamp(ctx context.Context, reader MessageReader, p int32, delayedTs int64) time.Time {
	ctx = logging.With(ctx, kvp.Int("partition", int(p)), kvp.Int64("delayed_ts", delayedTs), kvp.Time("delayed_timestamp", time.UnixMilli(delayedTs)))

	// NB: The order of reading offsets from the partition is significant. We must read the next offset (current offset + 1) first,
	// before reading the delayed offset for the provided delayedTs. This is because a race condition can occur if we read the
	// delayed offset before the next offset. In that scenario the delayed offset can become invalid if a new message is published
	// to the partition after reading the delayed offset but before reading the next offset. This can cause subtle bugs and incorrect lag calculations.
	nextOffset, err := reader.GetOffset(d.topic, p, sarama.OffsetNewest)
	if err != nil {
		logging.Error(ctx, "failed to get newest offset", kvp.Err(err))
		return unableToReadMarker
	}
	if nextOffset < 0 {
		panic(errors.Errorf("got invalid offset %d after reading sarama.OffsetNewest on topic=%s, partition=%d", nextOffset, d.topic, p))
	}
	if nextOffset == 0 {
		logging.Info(ctx, "no messages in partition, cannot compute lag")
		return zeroLagMarker
	}

	// We assume reader.GetOffset returns the nearest offset whose timestamp is equal to or later than the provided timestamp.
	// Because reader.GetOffset can return an offset later than delayedTs, we always use the previous offset (if one exists),
	// which guarantees a message is read whose timestamp is strictly earlier than the delayedTs.
	delayedOffset, err := reader.GetOffset(d.topic, int32(p), delayedTs)
	if err != nil {
		logging.Error(ctx, "failed to get offset for timestamp", kvp.Err(err))
		return unableToReadMarker
	}

	var offsetToRead int64
	switch {
	case delayedOffset < 0:
		// This means either kafka retention kicked in, or there have been no messages published to the partition
		// between the delayedTs and now, so we fallback to using the offset of the message on the head of the partition (i.e. nextOffset - 1).
		// NB: The offset we calculate might still be unavailable due to kafka retention, but this is the best we can do.
		logging.Info(ctx, "no offset found for delayed timestamp, using partition's current offset")
		offsetToRead = nextOffset - 1
	case delayedOffset == 0:
		// Cannot compute lag without at least one message before the delayedTs.
		logging.Info(ctx, "first message is earlier than delayed timestamp, cannot compute lag")
		return zeroLagMarker
	default:
		// We found an offset at or later than the delayedTs, but to ensure we are reading a message with a timestamp
		// strictly earlier than the delayedTs, we read the message at the offset before the delayed offset found.
		offsetToRead = delayedOffset - 1
	}

	logging.Info(ctx, "got offsets", kvp.Int64("offset_delayed", delayedOffset), kvp.Int64("offset_next", nextOffset), kvp.Int64("offset_to_read", offsetToRead))

	delayedMsg, err := reader.ReadMessage(ctx, d.topic, p, offsetToRead)
	if err != nil {
		// If the offset to read is for a message that has been deleted due to retention, it is not possible to calculate lag.
		if errors.Is(err, sarama.ErrOffsetOutOfRange) {
			logging.Error(ctx, "failed to read message at offset", kvp.Err(err), kvp.Int64("offset", offsetToRead))
			return zeroLagMarker
		}

		logging.Error(ctx, "failed to read message", kvp.Err(err))
		return unableToReadMarker
	}

	logging.Info(ctx, "got msg", kvp.Int64("msg_offset", offsetToRead), kvp.Int64("msg_ts", delayedMsg.Timestamp.UnixMilli()), kvp.Time("msg_timestamp", delayedMsg.Timestamp))

	// NB: For correctly computing lag we require the delayed message timestamp to be strictly before the delayedTs.
	if time.UnixMilli(delayedTs).Before(delayedMsg.Timestamp) {
		panic(errors.Errorf("read message with offset: %d has timestamp: %s after the delayed timestamp: %s", offsetToRead, delayedMsg.Timestamp, time.UnixMilli(delayedTs)))
	}

	return delayedMsg.Timestamp
}

// MessageReader is an interface for reading arbitrary messages from Kafka.
//
//go:generate counterfeiter . MessageReader
type MessageReader interface {
	Partitions(topic string) ([]int32, error)
	GetOffset(topic string, partition int32, ts int64) (int64, error)
	ReadMessage(ctx context.Context, topic string, partition int32, offset int64) (*sarama.ConsumerMessage, error)
	Close()
}

// A specific implementation of MessageReader that uses sarama and talks to Kafka.
type SaramaMessageReader struct {
	kafkaClient   sarama.Client
	kafkaConsumer sarama.Consumer
}

func NewSaramaMessageReader(client sarama.Client) (*SaramaMessageReader, error) {
	consumer, err := sarama.NewConsumerFromClient(client)
	if err != nil {
		return nil, err
	}
	return &SaramaMessageReader{client, consumer}, nil
}

func (r *SaramaMessageReader) Partitions(topic string) ([]int32, error) {
	return r.kafkaClient.Partitions(topic)
}

func (r *SaramaMessageReader) GetOffset(topic string, partition int32, ts int64) (int64, error) {
	return r.kafkaClient.GetOffset(topic, partition, ts)
}

func (r *SaramaMessageReader) ReadMessage(ctx context.Context, topic string, partition int32, offset int64) (*sarama.ConsumerMessage, error) {
	pc, err := r.kafkaConsumer.ConsumePartition(topic, partition, offset)
	if err != nil {
		return nil, err
	}
	defer pc.Close()

	select {
	case msg := <-pc.Messages():
		return msg, nil
	case <-time.After(1 * time.Second):
		return nil, errors.New("timed out waiting for message")
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func (r *SaramaMessageReader) Close() {
	r.kafkaConsumer.Close()
	r.kafkaClient.Close()
}

var _ MessageReader = &SaramaMessageReader{}
