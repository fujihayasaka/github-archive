package kafka

import (
	"context"
	"fmt"
	"sync"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/segmentio/kafka-go"
	"golang.org/x/exp/maps"
)

type (
	// offsetCommiter is a struct that keeps track of the offsets of messages that have been seen
	// and committed to Kafka.
	offsetCommiter struct {
		mutex sync.Mutex
		topic string
		// initialized is a set of partitions that we have seen the first message for
		initialized map[int]struct{}
		// committed is the last committed offset for each partition
		committed map[int]int64
		// pending is a set of offsets that we have seen but not yet committed
		// because we are waiting for a contiguous set of offsets starting from the last committed offset
		pending map[int]map[int64]struct{}
		logger  log.Logger
	}

	commitMessageFunc func(ctx context.Context, m ...kafka.Message) error
)

func newOffsetCommiter(topic string, logger log.Logger) *offsetCommiter {
	o := &offsetCommiter{
		topic:       topic,
		initialized: make(map[int]struct{}),
		committed:   make(map[int]int64),
		pending:     make(map[int]map[int64]struct{}),
		logger:      logger.WithFields(kvp.String("component", "offsetCommiter")),
	}

	return o
}

func (o *offsetCommiter) seen(m *kafka.Message) {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	if _, ok := o.initialized[m.Partition]; ok {
		return
	}
	o.initialized[m.Partition] = struct{}{}

	o.logger.Debug("initial committed offset found", kvp.Int("partition", m.Partition), kvp.Int64("offset", m.Offset-1))
	o.committed[m.Partition] = m.Offset - 1
}

func (o *offsetCommiter) processed(ctx context.Context, commitFn commitMessageFunc, m *kafka.Message) error {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	// last committed offset for this partition
	committed := o.committed[m.Partition]

	logger := o.logger.WithFields(
		kvp.Int("partition", m.Partition),
		kvp.Int64("offset", m.Offset),
		kvp.Int64("last-committed", committed))
	logger.Debug("processed message")

	// if we have already committed this offset, we can return early
	if m.Offset <= committed {
		logger.Debug("message already committed")
		return nil
	}

	// add the offset to the pending set
	if _, ok := o.pending[m.Partition]; !ok {
		o.pending[m.Partition] = make(map[int64]struct{})
	}
	o.pending[m.Partition][m.Offset] = struct{}{}

	// check if we have a set of pending offsets for this partition that we can commit
	// we can commit a set of offsets if they are contiguous to the last committed offset
	commit := int64(-1)
	offset := committed + 1
	for {
		if _, ok := o.pending[m.Partition][offset]; !ok {
			break
		}
		delete(o.pending[m.Partition], offset)
		commit = offset
		offset++
	}

	// we don't have any pending offsets to commit because there are gaps in the offsets
	if commit == -1 {
		logger.Debug("no commit as there are gaps", kvp.Int64s("pending", maps.Keys(o.pending[m.Partition])))
		return nil
	}

	// commit the offset
	if err := commitFn(ctx, kafka.Message{Topic: o.topic, Partition: m.Partition, Offset: commit}); err != nil {
		logger.WithError(err).Error("error committing offset")
		return fmt.Errorf("error committing offset: %w", err)
	}
	logger.Debug("offset committed", kvp.Int64("committed_offset", commit))

	o.committed[m.Partition] = commit

	return nil
}
