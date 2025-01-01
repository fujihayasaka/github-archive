package kafka_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/IBM/sarama"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
)

func Test_DelayedReaderEmptyTopic(t *testing.T) {
	r := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		mock := &kafkafakes.FakeMessageReader{}
		mock.PartitionsReturns([]int32{0, 1}, nil)
		mock.GetOffsetStub = func(topic string, partition int32, ts int64) (int64, error) {
			if ts > 0 {
				return sarama.OffsetNewest, nil
			}
			return 0, nil
		}
		mock.ReadMessageStub = func(ctx context.Context, topic string, partition int32, offset int64) (*sarama.ConsumerMessage, error) {
			return nil, fmt.Errorf("no messages on topic %s, partition=%d", topic, partition)
		}
		return mock
	}, "test")

	ctx := context.Background()
	r.Refresh(ctx)

	// No messages, so no lag
	require.EqualValues(t, 0, r.Since(time.Now(), 0).Milliseconds())
	require.EqualValues(t, 0, r.Since(time.Now(), 1).Milliseconds())
}

func Test_DelayedReader(t *testing.T) {
	ctx := context.Background()
	consumedTo := time.Now().Add(-15 * time.Minute)
	partition := int32(0)
	tests := []struct {
		name                string
		delayedMsgOffset    int64
		delayedMsgTimestamp time.Time
		nextOffsetToRead    int64
		expectedLagMs       int64
	}{
		{
			name:                "no messages in the partition",
			delayedMsgOffset:    sarama.OffsetNewest,
			delayedMsgTimestamp: time.Now(), // NB: this value is not used
			nextOffsetToRead:    0,
			expectedLagMs:       0,
		},
		{
			name:                "first message in the partition",
			delayedMsgOffset:    0,
			delayedMsgTimestamp: consumedTo, // NB: this value is not used
			nextOffsetToRead:    1,
			expectedLagMs:       0,
		},
		{
			name:                "no new messages in the partition and indexer is caught up (no lag)",
			delayedMsgOffset:    -1,
			delayedMsgTimestamp: consumedTo,
			nextOffsetToRead:    10,
			expectedLagMs:       0,
		},
		{
			name:                "indexer is ahead by 1s (negative delay lag)",
			delayedMsgOffset:    1,
			delayedMsgTimestamp: consumedTo.Add(-1 * time.Second),
			nextOffsetToRead:    2,
			expectedLagMs:       -1000,
		},
		{
			name:                "indexer is behind by 1s (delay lag)",
			delayedMsgOffset:    1,
			delayedMsgTimestamp: consumedTo.Add(1 * time.Second),
			nextOffsetToRead:    2,
			expectedLagMs:       1000,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			r := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
				mock := &kafkafakes.FakeMessageReader{}
				mock.PartitionsReturns([]int32{partition}, nil)
				mock.GetOffsetStub = mockKafkaGetOffset(test.delayedMsgOffset, test.nextOffsetToRead)
				mock.ReadMessageStub = mockKafkaReadMessage(test.delayedMsgOffset, test.nextOffsetToRead, test.delayedMsgTimestamp)
				return mock
			}, "test-topic-name")
			r.Refresh(ctx)
			require.EqualValues(t, test.expectedLagMs, r.Since(consumedTo, partition).Milliseconds())
		})
	}
}

func Test_DelayedReaderRetention(t *testing.T) {
	delayedMsgOffset := int64(-1) // NB: Kafka retention cleaned up, so we get the special value for: use the latest
	nextOffsetToRead := int64(10)
	now := time.Now()
	latestMsgTimestamp := now.Add(-10 * time.Minute).Add(-1 * time.Second)
	consumedTo := now.Add(-10 * time.Minute).Add(-6 * time.Second) // 5s of lag

	r := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		mock := &kafkafakes.FakeMessageReader{}
		mock.PartitionsReturns([]int32{0}, nil)
		mock.GetOffsetStub = mockKafkaGetOffset(delayedMsgOffset, nextOffsetToRead)
		mock.ReadMessageStub = func(ctx context.Context, topic string, partition int32, offset int64) (*sarama.ConsumerMessage, error) {
			switch offset {
			case nextOffsetToRead - 1:
				return &sarama.ConsumerMessage{Timestamp: latestMsgTimestamp}, nil
			default:
				return nil, fmt.Errorf("unexpected read of offset %d", offset)
			}
		}
		return mock
	}, "test-topic-name")
	r.Refresh(context.Background())
	require.EqualValues(t, 5000, r.Since(consumedTo, 0).Milliseconds())
}

func Test_ReadMessageFails(t *testing.T) {
	delayedMsgOffset := int64(5)
	nextOffsetToRead := int64(10)
	now := time.Now()
	delayedMsgTimestamp := now.Add(-10 * time.Minute).Add(-1 * time.Second)
	consumedTo := now.Add(-10 * time.Minute).Add(-6 * time.Second) // 5s of lag

	sentFailure := false
	r := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		mock := &kafkafakes.FakeMessageReader{}
		mock.PartitionsReturns([]int32{0}, nil)
		mock.GetOffsetStub = mockKafkaGetOffset(delayedMsgOffset, nextOffsetToRead)
		mock.ReadMessageStub = func(ctx context.Context, topic string, partition int32, offset int64) (*sarama.ConsumerMessage, error) {
			if sentFailure {
				return &sarama.ConsumerMessage{Timestamp: delayedMsgTimestamp}, nil
			}
			sentFailure = true
			return nil, fmt.Errorf("unexpected failure to read offset %d", offset)
		}
		return mock
	}, "test-topic-name")
	r.Refresh(context.Background())
	// NB: 24hrs is a marker of failure to read a valid lag value: system state is unknown
	require.GreaterOrEqual(t, r.Since(consumedTo, 0).Milliseconds(), 24*time.Hour.Milliseconds())

	// Now refresh again and test that a valid value can be sent
	r.Refresh(context.Background())
	require.EqualValues(t, 5000, r.Since(consumedTo, 0).Milliseconds())
}

func Test_GetOffsetForTsFails(t *testing.T) {
	delayedMsgOffset := int64(5)
	nextOffsetToRead := int64(10)
	now := time.Now()
	delayedMsgTimestamp := now.Add(-10 * time.Minute).Add(-1 * time.Second)
	consumedTo := now.Add(-10 * time.Minute).Add(-6 * time.Second) // 5s of lag

	r := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		mock := &kafkafakes.FakeMessageReader{}
		mock.PartitionsReturns([]int32{0}, nil)
		mock.GetOffsetStub = func(topic string, partition int32, ts int64) (int64, error) {
			if ts > 0 {
				return 0, fmt.Errorf("unexpected failure to get offset for timestamp %d", ts)
			}
			return nextOffsetToRead, nil
		}
		mock.ReadMessageStub = mockKafkaReadMessage(delayedMsgOffset, nextOffsetToRead, delayedMsgTimestamp)
		return mock
	}, "test-topic-name")
	r.Refresh(context.Background())
	// NB: 24hrs is a marker of failure to read a valid lag value: system state is unknown
	require.GreaterOrEqual(t, r.Since(consumedTo, 0).Milliseconds(), 24*time.Hour.Milliseconds())
}

func Test_GetOffsetForNewestFails(t *testing.T) {
	delayedMsgOffset := int64(5)
	nextOffsetToRead := int64(10)
	now := time.Now()
	delayedMsgTimestamp := now.Add(-10 * time.Minute).Add(-1 * time.Second)
	consumedTo := now.Add(-10 * time.Minute).Add(-6 * time.Second) // 5s of lag

	r := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		mock := &kafkafakes.FakeMessageReader{}
		mock.PartitionsReturns([]int32{0}, nil)
		mock.GetOffsetStub = func(topic string, partition int32, ts int64) (int64, error) {
			if ts > 0 {
				return delayedMsgOffset, nil
			}
			return 0, fmt.Errorf("unexpected failure to get offset for timestamp %d", ts)
		}
		mock.ReadMessageStub = mockKafkaReadMessage(delayedMsgOffset, nextOffsetToRead, delayedMsgTimestamp)
		return mock
	}, "test-topic-name")
	r.Refresh(context.Background())
	// NB: 24hrs is a marker of failure to read a valid lag value: system state is unknown
	require.GreaterOrEqual(t, r.Since(consumedTo, 0).Milliseconds(), 24*time.Hour.Milliseconds())
}

func Test_ReadMessageOffsetOutOfRange(t *testing.T) {
	r := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		mock := &kafkafakes.FakeMessageReader{}
		mock.PartitionsReturns([]int32{0}, nil)
		mock.GetOffsetStub = func(topic string, partition int32, ts int64) (int64, error) {
			return 1, nil
		}
		mock.ReadMessageStub = func(ctx context.Context, topic string, partition int32, offset int64) (*sarama.ConsumerMessage, error) {
			return nil, sarama.ErrOffsetOutOfRange
		}
		return mock
	}, "test-topic-name")
	r.Refresh(context.Background())
	require.EqualValues(t, 0, r.Since(time.Now(), 0).Milliseconds())
}

func Test_DelayedReaderMessageInvalidTimestampInvariant(t *testing.T) {
	delayedMsgOffset := int64(1)
	nextOffsetToRead := int64(2)
	delayedMsgTimestamp := time.Now().Add(-9 * time.Minute)
	r := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		mock := &kafkafakes.FakeMessageReader{}
		mock.PartitionsReturns([]int32{0}, nil)
		mock.GetOffsetStub = mockKafkaGetOffset(delayedMsgOffset, nextOffsetToRead)
		mock.ReadMessageStub = mockKafkaReadMessage(delayedMsgOffset, nextOffsetToRead, delayedMsgTimestamp)
		return mock
	}, "test-topic-name")
	require.Panics(t, func() {
		r.Refresh(context.Background())
	})
}

func mockKafkaGetOffset(delayedMsgOffset, nextOffsetToRead int64) func(topic string, partition int32, ts int64) (int64, error) {
	return func(topic string, partition int32, ts int64) (int64, error) {
		if ts > 0 {
			return delayedMsgOffset, nil
		}
		return nextOffsetToRead, nil
	}
}

func mockKafkaReadMessage(delayedMsgOffset, nextOffsetToRead int64, msgTs time.Time) func(ctx context.Context, topic string, partition int32, offset int64) (*sarama.ConsumerMessage, error) {
	return func(ctx context.Context, topic string, partition int32, offset int64) (*sarama.ConsumerMessage, error) {
		if offset < 0 {
			return nil, fmt.Errorf("unexpected read of offset %d", offset)
		}
		switch offset {
		case delayedMsgOffset - 1: // the prior message
			return &sarama.ConsumerMessage{Timestamp: msgTs}, nil
		case nextOffsetToRead - 1: // the last message on the partition
			return &sarama.ConsumerMessage{Timestamp: msgTs}, nil
		default:
			return nil, fmt.Errorf("unexpected read of offset %d", offset)
		}
	}
}
