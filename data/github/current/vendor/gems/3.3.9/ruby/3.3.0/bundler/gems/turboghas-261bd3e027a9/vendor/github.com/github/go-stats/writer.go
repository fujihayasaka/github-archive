package stats

import (
	"crypto/rand"
	"io"
	"math/big"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// writer is the implementation of a Statsd-compatible metrics writer. It is used
// internally by the metrics package to write and flush metrics to a given sink.
// This writer also supports the following extensions on top of the Statsd protocol:
//
// - Buffered metrics: by default all metrics are stored in a buffer and
// flushed to the sink after an interval
//
// - Downsampled metrics: metrics can be reported at a given rate
//
// - tagBuffer: metrics can be reportd with user-supplied tags attached (this is a
// DataDog feature which may not be supported by all statsd server
// implementations).
type writer struct {
	// A Sink is the endpoint where metrics will be periodically written to.
	// It should usually be an UDP socket pointing to the StatsD server, but
	// any other struct implementing io.Writer will also work.
	Sink io.Writer

	// Interval is the duration between flushes to the Sink. The metrics buffer
	// will be periodically flushed every time it reaches its maximum capacity
	// or every Interval, even if the buffer is not yet full.
	Interval time.Duration

	metrics  chan metric
	done     chan struct{}
	starting sync.WaitGroup
	running  sync.WaitGroup

	// should calls to writer.enqueue block until there is space for the metric.
	// defaults to false, which means the message will be dropped if there is no
	// space to enqueue the message.
	block bool

	// maxChannelSize is the maximum size of the channel used to buffer metrics. If not set, the default is 2048.
	maxChannelSize int

	// channelExceededReporting indicates whether to report the number of metrics dropped
	// due to the internal metrics channel being full.
	channelExceededReporting bool

	// numChannelExceeded is the number of metrics that have been dropped due to the internal
	// metrics channel being full. The counter is reset upon aggregated-reporting.
	numChannelExceeded atomic.Uint32

	// channelExceeded signals that a metric has been dropped due to the internal metrics
	// channel being full.
	channelExceeded chan struct{}

	// channelExceededAggregate signals that the delay for aggregating channel-exceeded counts has expired.
	channelExceededAggregate chan struct{}

	// channelExceededDelay is the amount of time to aggregate counts before writing
	// the dropped count. This helps prevent writing the dropped count too often.
	channelExceededDelay time.Duration

	// newChannelExceededMetric creates a new metric struct for reporting the number of metrics
	// dropped due to the internal metrics channel being full.
	newChannelExceededMetric func(count uint32) metric
}

const (
	// 60 bytes for IP header, 8 bytes for UDP leaves 1432 bytes with 1500 MTU.
	maxWriteSize = 1432

	maxWriteDelay = 500 * time.Millisecond

	defaulMaxChannelSize = 2048

	// defaultChannelExceededDelay is the default amount of time to aggregate counts before writing
	// the dropped count. This helps prevent writing the dropped count too often.
	defaultChannelExceededDelay = time.Second
)

// tagBuffer is the serialized form of the tags attached to a specific metric.
// It can be generated from a serialize.
type tagBuffer []byte

// tagBuffer generates a serialized tagBuffer struct from a serialize. The result
// of this serialization should be cached if possible.
func (t Tags) serialize() tagBuffer {
	if t == nil {
		return nil
	}

	var b tagBuffer
	for k, v := range t {
		b = append(b, k...)
		if v != "" {
			v = strings.ReplaceAll(v, "|", "/")
			b = append(b, ':')
			b = append(b, v...)
		}
		b = append(b, ',')
	}
	return b
}

func flush(sink io.Writer, buf []byte) []byte {
	if len(buf) > 0 {
		_, _ = sink.Write(buf)
		buf = buf[:0]
	}
	return buf
}

func writeMetric(sink io.Writer, dbuf, mbuf []byte, m *metric) []byte {
	// replace the metric buf with the new serialized metric
	mbuf = m.serialize(mbuf[:0])

	// ignore the metric if it's too big
	if len(mbuf) > maxWriteSize {
		return dbuf
	}

	// flush the delivery buffer if we don't have enough room
	if len(dbuf)+len(mbuf) > maxWriteSize {
		dbuf = flush(sink, dbuf)
	}

	// append the metric to the delivery buffer
	return append(dbuf, mbuf...)
}

func (st *writer) shutdown(dbuf, mbuf []byte) {
	flushing := true
	for flushing {
		select {
		case m := <-st.metrics:
			dbuf = writeMetric(st.Sink, dbuf, mbuf, &m)
		default:
			flushing = false
		}
	}
	flush(st.Sink, dbuf)
	st.running.Done()
}

func (st *writer) start() {
	if st.metrics != nil {
		return
	}
	st.done = make(chan struct{})

	// allocate a buffer to fill up for single-packet multi-metric deliveries, and
	// another to serialize the metrics into. These buffers are passed to both the
	// buffer flush and metrics serialization code to prevent new allocations,
	// and are continually overwritten/emptied.
	dbuf := make([]byte, 0, maxWriteSize)
	mbuf := make([]byte, 0, maxWriteSize)

	ticks := time.NewTicker(st.Interval)
	defer ticks.Stop()

	// metrics channel
	if st.maxChannelSize == 0 {
		st.maxChannelSize = defaulMaxChannelSize
	}
	st.metrics = make(chan metric, st.maxChannelSize)

	// channel-exceeded reporting?
	if st.channelExceededReporting {
		st.channelExceeded = make(chan struct{}, 1)
		st.channelExceededAggregate = make(chan struct{}, 1)
		if st.channelExceededDelay == 0 {
			st.channelExceededDelay = defaultChannelExceededDelay
		}
		go st.startAggregationDelays()
	}

	st.running.Add(1)
	st.starting.Done()

	for {
		select {
		case m := <-st.metrics:
			dbuf = writeMetric(st.Sink, dbuf, mbuf, &m)
		case <-st.channelExceededAggregate:
			count := st.numChannelExceeded.Swap(0)
			if count > 0 {
				m := st.newChannelExceededMetric(count)
				dbuf = writeMetric(st.Sink, dbuf, mbuf, &m)
			}
		case <-st.done:
			st.shutdown(dbuf, mbuf)
			return
		case <-ticks.C:
			dbuf = flush(st.Sink, dbuf)
		}
	}
}

// startAggregationDelays introduces a delay before reporting the channel-exceeded metric.
// This delay allows for aggregation, which avoids reporting too often.
func (st *writer) startAggregationDelays() {
	for {
		// receive from channel-exceeded
		select {
		case <-st.channelExceeded:
		case <-st.done:
			return
		}

		// delay
		select {
		case <-time.After(st.channelExceededDelay):
		case <-st.done:
			return
		}

		// blocking send to channel-exceeded-aggregate
		select {
		case st.channelExceededAggregate <- struct{}{}:
		case <-st.done:
			return
		}
	}
}

func (st *writer) stop() {
	close(st.done)
}

// RandIntn is a shortcut for generating a random integer between 0 and
// max using crypto/rand. Because Go thinks you should implement everything your own dang self.
// https://brandur.org/fragments/crypto-rand-float64
func RandIntn(maxInt int64) int64 {
	nBig, err := rand.Int(rand.Reader, big.NewInt(maxInt))
	if err != nil {
		panic(err)
	}
	return nBig.Int64()
}

// RandFloat64 is a shortcut for generating a random float between 0 and
// 1 using crypto/rand. Because Go thinks you should implement everything your own dang self.
// https://brandur.org/fragments/crypto-rand-float64
func RandFloat64() float64 {
	return float64(RandIntn(1<<53)) / (1 << 53)
}

func (st *writer) enqueue(m metric) {
	if st.metrics == nil {
		panic("stats: write on stopped client")
	}

	if m.rate < 1.0 && float32(RandFloat64()) > m.rate {
		return
	}

	// blocking send?
	if st.block {
		st.metrics <- m
		return
	}

	// non-blocking send
	select {
	case st.metrics <- m:
	default:
		// channel-exceeded reporting?
		if st.channelExceededReporting {
			// increment
			st.numChannelExceeded.Add(1)

			// non-blocking send
			select {
			case st.channelExceeded <- struct{}{}:
			default:
			}
		}
	}
}

// regularizePrefix ensures that the Prefix ends with a '.', so that it
// can be contatenated with a metric name to form a valid metric path.
func regularizePrefix(prefix string) string {
	if prefix != "" && !strings.HasSuffix(prefix, ".") {
		return prefix + "."
	}
	return prefix
}
