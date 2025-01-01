package hydro

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-stats"
)

// ManualKafkaSource is a low-level Kafka source for manually consuming from
// specific topic/partitions without a consumer group. Unless you have a valid
// use-case and fully understand the semantics of not using a consumer group
// you should use a KafkaSource.
//
// It must be created using NewManualKafkaSource.
//
// It implements the Source & Consumer interfaces, so consuming works the same
// as a KafkaSource (excluding any consumer group semantics).
//
// Caution: Kafka is optimized for consuming using consumer groups. Frequent
// consumption of older topic/partition data can impact broker IO, degrading
// performance of a cluster. Please use responsibly.
type ManualKafkaSource struct {
	client   sarama.Client
	consumer sarama.Consumer

	messages chan Message

	closed    chan struct{}
	closeOnce sync.Once
	wg        sync.WaitGroup

	log           Logger
	errReporter   ErrorReporter
	statsReporter *saramaStatsReporter
}

// NewManualKafkaSource returns a new ManualKafkaSource for manual consumption
// of specific topic/partition(s) without a consumer group.
//
// It uses the KafkaConfig and applies each KafkaSourceOption, returning any
// config errors. All KafkaSourceOption related to consumer groups are ignored.
//
// Callers must manually add topic/partition subscriptions with the Subscribe method.
//
// Callers are responsible for calling Close.
func NewManualKafkaSource(kc KafkaConfig, opts ...KafkaSourceOption) (*ManualKafkaSource, error) {
	ksc := new(kafkaSourceConfig)
	for _, o := range opts {
		if err := o(ksc); err != nil {
			return nil, fmt.Errorf("applying KafkaSourceOption: %w", err)
		}
	}

	scfg := kc.toSarama()

	// sarama.Config.Consumer.Fetch configs
	scfg.Consumer.Fetch.Min = fetchMinBytesLimit
	if ksc.fetch.min != nil {
		scfg.Consumer.Fetch.Min = *ksc.fetch.min
	}
	scfg.Consumer.Fetch.Default = fetchDefaultBytes
	if ksc.fetch.avg != nil {
		scfg.Consumer.Fetch.Default = *ksc.fetch.avg
	}
	if ksc.fetch.max != nil {
		scfg.Consumer.Fetch.Max = *ksc.fetch.max
	}
	scfg.Consumer.MaxWaitTime = fetchTimeoutDefault
	if ksc.fetch.timeout != nil {
		scfg.Consumer.MaxWaitTime = *ksc.fetch.timeout
	}

	// sarama.Config.Consumer.Return configs
	scfg.Consumer.Return.Errors = true // errors chan must be drained

	// sarama.Config.Consumer.Offsets configs
	scfg.Consumer.Offsets.AutoCommit.Enable = true
	if ksc.offsetFlushInterval != nil {
		scfg.Consumer.Offsets.AutoCommit.Interval = *ksc.offsetFlushInterval
	}
	scfg.Consumer.Offsets.Initial = sarama.OffsetOldest

	// apply optional overrides of the final sarama configs
	for _, override := range kc.overrides {
		override(scfg)
	}

	client, err := sarama.NewClient(kc.brokers, scfg)
	if err != nil {
		return nil, fmt.Errorf("creating sarama client: %w", err)
	}

	consumer, err := sarama.NewConsumerFromClient(client)
	if err != nil {
		return nil, fmt.Errorf("creating sarama consumer: %w", err)
	}

	var statsReporter *saramaStatsReporter
	if kc.stats != stats.NullStatter {
		statsReporter = &saramaStatsReporter{
			metrics: scfg.MetricRegistry,
			adapter: &metricStatsAdapter{
				prefix: "kafka.",
				client: kc.stats,
			},
			ticker: time.NewTicker(kc.sampleRate),
		}
		go statsReporter.Run()
	}

	mks := &ManualKafkaSource{
		client:        client,
		consumer:      consumer,
		messages:      make(chan Message),
		closed:        make(chan struct{}),
		log:           kc.log,
		errReporter:   kc.errReporter,
		statsReporter: statsReporter,
	}

	return mks, nil
}

// HighWaterMarks returns the current high water marks for each topic and partition.
// Consistency between partitions is not guaranteed since high water marks are updated separately.
func (mks *ManualKafkaSource) HighWaterMarks() map[string]map[int32]int64 {
	return mks.consumer.HighWaterMarks()
}

// ReadMessage attempts to return the next Message from one of its
// topic/partition subscriptions (ordering between multiple topic/partitions is
// non-deterministic).
//
// It blocks until a Message is read, the provided context is canceled, or the
// source is closed.
//
// It returns the context's error when canceled/timed-out or ErrSourceClosed if
// the source has been closed.
//
// When an error is returned the Message must be discarded.
func (mks *ManualKafkaSource) ReadMessage(ctx context.Context) (Message, error) {
	select {
	case <-ctx.Done():
		return Message{}, ctx.Err()
	case <-mks.closed:
		return Message{}, ErrSourceClosed
	case msg := <-mks.messages:
		if mks.isClosed() {
			return Message{}, ErrSourceClosed
		}
		return msg, nil
	}
}

// MarkMessage is a NOOP implementation to satisfy the Consumer interface.
//
// Committing offsets is exclusive to consumer groups.
func (mks *ManualKafkaSource) MarkMessage(_ Message) error {
	return nil
}

// Consume follows the same behavior as a KafkaSource with the exception of any
// consumer group semantics.
//
// See the KafkaSource's Consume method for details.
func (mks *ManualKafkaSource) Consume(ctx context.Context, fn MessageHandler) error {
	return consumeWithHandler(ctx, mks.log.Println, mks.errReporter, mks, fn)
}

// Subscribe adds a subscription to the provided topic partition at the
// specific offset for consumption.
//
// Both sarama.OffsetNewest and sarama.OffsetOldest are accepted offset values,
// see their definitions for details.
//
// It returns any error from the underlying Kafka client creating its
// topic/partition consumer.
//
// Subsequent calls for the same topic and partition will return an error.
//
// It returns ErrSourceClosed if the source has been closed.
func (mks *ManualKafkaSource) Subscribe(topic string, partition int32, offset int64) error {
	if mks.isClosed() {
		return ErrSourceClosed
	}

	pc, err := mks.consumer.ConsumePartition(topic, partition, offset)
	if err != nil {
		return fmt.Errorf("creating partition consumer for %s/%d/%d: %w", topic, partition, offset, err)
	}

	forwardMsgs := func() {
		defer func() {
			pc.AsyncClose()
			for range pc.Messages() {
				// drain Messages
			}
			mks.wg.Done()
		}()

		for {
			select {
			case <-mks.closed:
				return
			case msg := <-pc.Messages():
				if msg == nil {
					return // unexpected case
				}

				select {
				case <-mks.closed:
					return
				case mks.messages <- ConsumerMessageToMessage(msg):
				}
			}
		}
	}

	reportErrs := func() {
		defer mks.wg.Done()
		for err := range pc.Errors() {
			if err == nil {
				continue
			}
			_ = mks.errReporter.Report(context.Background(),
				fmt.Errorf("consumer error: %w", err),
				map[string]string{
					"topic":     err.Topic,
					"partition": strconv.Itoa(int(err.Partition)),
				},
			)
		}
	}

	mks.wg.Add(2)
	go forwardMsgs()
	go reportErrs()

	return nil
}

type offset int64

const (
	// OffsetNewest is a special offset value that means the newest message
	// available on the topic at the time the message is received.
	OffsetNewest offset = offset(sarama.OffsetNewest)

	// OffsetOldest is a special offset value that means the oldest message
	// available on the topic at the time the message is received.
	OffsetOldest offset = offset(sarama.OffsetOldest)
)

// SubscribeToTopic adds a subscription to all the partitions of the provided
// topic at the specific offset for consumption. The only two valid offsets are
// [OffsetNewest] and [OffsetOldest].
//
// It returns if the offset provided isn't [OffsetNewest] or [OffsetOldest] and
// any error from the underlying Kafka client creating its topic/partition
// consumers.
//
// Subsequent calls for the same topic will return an error.
//
// It returns ErrSourceClosed if the source has been closed.
func (mks *ManualKafkaSource) SubscribeToTopic(topic string, offset int64) error {
	if offset != int64(OffsetNewest) && offset != int64(OffsetOldest) {
		return fmt.Errorf("invalid offset value: %d", offset)
	}

	if mks.isClosed() {
		return ErrSourceClosed
	}

	partitions, err := mks.consumer.Partitions(topic)
	if err != nil {
		return fmt.Errorf("fetching partitions for %s: %w", topic, err)
	}

	for _, partition := range partitions {
		if err := mks.Subscribe(topic, partition, offset); err != nil {
			return err
		}
	}

	return nil
}

// Close closes the source, blocking until all internal resources have been
// closed.
//
// Any error(s) that occur during its shutdown process will be returned as an
// ErrorList.
//
// It's not recommended to be called multiple times or concurrently in order to
// best ensure the caller handles any error(s) returned during its synchronized
// shutdown process.
//
// Once closed the ManualKafkaSource cannot be reused.
func (mks *ManualKafkaSource) Close() error {
	var el ErrorList

	mks.closeOnce.Do(func() {
		close(mks.closed) // signal sarama.PartitionConsumers to close themselves

		// sarama.PartitionConsumers must be closed before sarama.Consumer
		mks.wg.Wait()
		if err := mks.consumer.Close(); err != nil {
			el = append(el, fmt.Errorf("closing sarama consumer: %w", err))
		}

		if mks.statsReporter != nil {
			mks.statsReporter.Stop()
		}

		// sarama client must be closed last
		if err := mks.client.Close(); err != nil {
			el = append(el, fmt.Errorf("closing sarama client: %w", err))
		}
	})

	if len(el) > 0 {
		return el
	}
	return nil
}

func (mks *ManualKafkaSource) isClosed() bool {
	select {
	case <-mks.closed:
		return true
	default:
	}
	return false
}
