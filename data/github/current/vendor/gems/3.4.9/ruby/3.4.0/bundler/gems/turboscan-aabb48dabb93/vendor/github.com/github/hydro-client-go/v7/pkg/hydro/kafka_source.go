package hydro

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-stats"
)

type kafkaSourceConfig struct {
	fetch struct {
		min     *int32
		avg     *int32
		max     *int32
		timeout *time.Duration
	}
	offsetFlushInterval *time.Duration
}

// KafkaSourceOption is a functional option type that applies an config to a
// KafkaSource returning any encountered error.
type KafkaSourceOption = func(*kafkaSourceConfig) error

const (
	fetchMinBytesLimit  = 1
	fetchTimeoutDefault = 500 * time.Millisecond
	fetchTimeoutLimit   = 25 * time.Millisecond
	fetchDefaultBytes   = 1 * 1024 * 1024 // 1MiB
)

// WithFetchMinBytes is the KafkaSourceOption that sets the minimum amount of
// bytes a broker will wait to become available before responding to a fetch
// request for a batch of messages. It returns an error for values below 1.
func WithFetchMinBytes(n int32) KafkaSourceOption {
	return func(ksc *kafkaSourceConfig) error {
		if n < fetchMinBytesLimit {
			return fmt.Errorf("fetch min bytes must be >= %d", fetchMinBytesLimit)
		}
		ksc.fetch.min = &n
		return nil
	}
}

// WithFetchDefaultBytes is the KafkaSourceOption that sets the default amount
// of bytes a broker will wait to become available before responding to a fetch
// request for a batch of messages. It is recommended to set this to a multiple
// of your average message size.
func WithFetchDefaultBytes(n int32) KafkaSourceOption {
	return func(ksc *kafkaSourceConfig) error {
		ksc.fetch.avg = &n
		return nil
	}
}

// WithFetchMaxBytes is the KafkaSourceOption that sets the maximum amount of
// bytes a KafkaSource will accept for a single request when fetching a batch
// of messages. It is not recommended to set this to a value smaller than the
// largest supported Hydro message size (MaxMessageBytes).
func WithFetchMaxBytes(n int32) KafkaSourceOption {
	return func(ksc *kafkaSourceConfig) error {
		ksc.fetch.max = &n
		return nil
	}
}

// WithFetchTimeout is the KafkaSourceOption that sets the maximum amount of
// time a broker will wait for "fetch min bytes" to become available before
// responding to a fetch request for a batch of messages. It returns an error
// for values below 25ms.
func WithFetchTimeout(d time.Duration) KafkaSourceOption {
	return func(ksc *kafkaSourceConfig) error {
		if d < fetchTimeoutLimit {
			return fmt.Errorf("fetch timeout must be >= %v", fetchTimeoutLimit)
		}
		ksc.fetch.timeout = &d
		return nil
	}
}

// WithOffsetFlushInterval is the KafkaSourceOption that sets the interval
// message offsets marked to be committed will be flushed.
func WithOffsetFlushInterval(d time.Duration) KafkaSourceOption {
	return func(ksc *kafkaSourceConfig) error {
		if d == 0 {
			return errors.New("offset flush interval must be > 0")
		}
		ksc.offsetFlushInterval = &d
		return nil
	}
}

// Duration to wait until retrying a new a consumer group session.
const consumeRetryBackoff = 10 * time.Second

// KafkaSource implements the Source interface for consuming Messages from one
// or more Kafka topics in a consumer group. It must be created using
// NewKafkaSource and configured with KafkaSourceOptions.
type KafkaSource struct {
	client      sarama.Client
	consumer    sarama.ConsumerGroup
	reporter    *saramaStatsReporter
	topics      []string
	log         Logger
	stats       stats.Client
	cgh         *consumerGroupHandler
	errReporter ErrorReporter
}

// NewKafkaSource returns a new KafkaSource for consuming from the provided
// list of topics in a consumer group. It uses the KafkaConfig and applies each
// KafkaSourceOptions returning any encountered error.
//
// To consume messages you must exclusively use either the high-level Consume
// method (see method and Source docs) or the low-level Source interface
// methods.
//
// To ensure a graceful shutdown the caller must call the Close method when
// done using the KafkaSource.
func NewKafkaSource(kc KafkaConfig, groupName string, topics []string, opts ...KafkaSourceOption) (*KafkaSource, error) {
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

	// verify we can get metadata for all provided topics
	if err := client.RefreshMetadata(topics...); err != nil {
		return nil, err
	}

	cg, err := sarama.NewConsumerGroupFromClient(groupName, client)
	if err != nil {
		return nil, fmt.Errorf("creating consumer group: %w", err)
	}

	// ensure consumer group errors channel is drained to prevent deadlocking
	go func() {
		for err := range cg.Errors() {
			// TODO: report stat
			kc.log.Printf("consumer group error: %v", err)
		}
	}()

	var reporter *saramaStatsReporter
	if kc.stats != stats.NullStatter {
		reporter = &saramaStatsReporter{
			metrics: scfg.MetricRegistry,
			adapter: &metricStatsAdapter{
				prefix: "kafka.",
				client: kc.stats,
			},
			ticker: time.NewTicker(kc.sampleRate),
		}
		go reporter.Run()
	}

	ks := &KafkaSource{
		client:      client,
		consumer:    cg,
		reporter:    reporter,
		topics:      topics,
		log:         kc.log,
		stats:       kc.stats,
		cgh:         new(consumerGroupHandler),
		errReporter: kc.errReporter,
	}

	go ks.consumerLoop(consumeRetryBackoff)

	return ks, nil
}

func (ks *KafkaSource) ReadMessage(ctx context.Context) (Message, error) {
	return ks.cgh.ReadMessage(ctx)
}

func (ks *KafkaSource) MarkMessage(message Message) error {
	return ks.cgh.MarkMessage(message)
}

func (ks *KafkaSource) CommitOffsets() error {
	return ks.cgh.CommitOffsets()
}

// Consume starts a long running consumer loop that joins its consumer group
// and consumes messages using the MessageHandler. It returns when the
// KafkaSource is closed or the provided context is canceled. When the context
// is canceled it returns the context's error. If an internal error occurs it
// will be returned.
//
// See MessageHandler for implementation recommendations and requirements.
//
// Consumer group level errors are reported using configured logger. It's
// recommended for a logger to be set using the WithKafkaLogger option.
//
// Consume must not be called concurrently.
func (ks *KafkaSource) Consume(ctx context.Context, fn MessageHandler) error {
	return consumeWithHandler(ctx, ks.log.Println, ks.errReporter, ks, fn)
}

func (ks *KafkaSource) consumerLoop(backoff time.Duration) {
	ks.log.Println("starting consumerLoop...")
	defer ks.log.Println("exiting consumerLoop...")

	for {
		err := ks.consumer.Consume(context.Background(), ks.topics, ks.cgh)
		if err == nil {
			// indicates a clean exit likely due to a rebalance, start a new
			// session
			continue
		}
		if errors.Is(err, sarama.ErrClosedConsumerGroup) {
			// sarama client has been closed, exit consumer loop
			return
		}
		ks.log.Printf("consume error: %v", err.Error())

		ks.log.Printf("consumer reconnecting in %v...", backoff)
		time.Sleep(backoff)
	}
}

// Close closes the KafkaSource by shutting down its consumer group session and
// Kafka client. MessageHandlers are given a grace period to finish handling
// their current message. It's critical for handlers to return as quickly as
// possible to ensure final offsets are committed.
//
// It returns any errors encountered while closing. When multiple errors occur
// they will be returned using the Errors interface.
//
// Once the Close method has been called the KafkaSource must be discarded.
func (ks *KafkaSource) Close() error {
	// TODO: mention that this can return Errors
	var el ErrorList

	if err := ks.consumer.Close(); err != nil {
		el = append(el, fmt.Errorf("closing sarama consumer group: %w", err))
	}

	if ks.reporter != nil {
		ks.reporter.Stop()
	}

	// sarama client must be closed last
	if err := ks.client.Close(); err != nil {
		el = append(el, fmt.Errorf("closing sarama client: %w", err))
	}

	if len(el) > 0 {
		return el
	}
	return nil
}

func ConsumerMessageToMessage(cm *sarama.ConsumerMessage) Message {
	var headers map[string]string
	if len(cm.Headers) > 0 {
		headers = make(map[string]string, len(cm.Headers))
		for _, header := range cm.Headers {
			headers[string(header.Key)] = string(header.Value)
		}
	}

	return Message{
		Topic:     cm.Topic,
		Key:       cm.Key,
		Value:     cm.Value,
		Partition: cm.Partition,
		Offset:    cm.Offset,
		Timestamp: cm.Timestamp,
		Headers:   headers,
	}
}
