// Kafka Producing
//
// KafkaSinks are used for producing messages to Kafka. Messages are sent to
// the lead broker for a topic and partition. Broker addresses and
// topic/partition ownership is provided by cluster metadata. This metadata
// will initially be fetched from the configured bootstrap brokers on
// initialization. Metadata will continuously be refreshed.
//
// KafkaSinks can be configured for either synchronously or asynchronously
// producing. This can be set using the WithAsync option. In synchronous
// producing mode calls to Write block until the message is written or fails
// returning the error. In asynchronous producing mode calls to Write send the
// message on an internal channel and immediately return with no error. In this
// mode errors are passed asynchronously to an error handler if enabled using
// the WithWriteErrorHandler option.
//
// KafkaSinks batch messages internally. Batches are maintained by topic and
// partition. Batching behavior can be configured using the WithBatchBytes,
// WithBatchSize, and WithBatchTimeout options. By default batches will be
// flushed as quickly as possible. When flushed a batch's messages are sent to
// a broker as a single producer request. Messages that would be placed in a
// batch that is currently being flushed will be placed in the subsequent
// batch.
//
// To successfully complete a produce request a lead broker for a topic and
// partition must receive the number of required acknowledgements from its
// replicas. This number can be configured using the WithRequiredAcks option.
//
// When a produce request fails it will be retried. The amount of retries can
// be configured using the WithSendAttempts option. A request that fails its
// final attempt will result in an error. The error will be handled depending
// on the producing mode and configuration of the KafkaSink.
package hydro

import (
	"errors"
	"fmt"
	"hash"
	"hash/fnv"
	"sync"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-stats"
)

// Partitioner is the partitioning strategy a Kafka producer will use for
// deciding which partition for a topic to route a Message to.
//
// Deprecated: Partitioning must be controlled with PublishOptions.
type Partitioner int

const (
	// RandomPartitioner is the Partitioner strategy that randomly chooses a
	// partition a Message is produce to. This strategy helps ensure an even
	// distribution of messages across a topic's partitions. This strategy
	// should not be used when ordering of logically related messages is
	// required.
	RandomPartitioner Partitioner = iota

	// RoundRobinPartitioner is the Partitioner strategy that cycles through each
	// topic's partition. It has the same constraints as RandomPartitioner.
	RoundRobinPartitioner

	// HashPartitioner is the Partitioner strategy that uses a hash of a
	// Message's key to choose the partition. It ensures Messages with the same
	// key always end up on the same partition. When the key is nil it will
	// choose a random partition. It uses the same hashing behavior as the Java
	// client. This strategy should only be used when message ordering by key
	// is required as it can result in an uneven distribution of messages
	// across partitions. Note that the partition new messages with the same
	// key are produced to may change when a topic's partition count is
	// modified.
	HashPartitioner

	// ManualPartitioner is the Partitioner strategy that uses the partition
	// manually specified by a Message. This strategy is NOT recommended for
	// use outside of testing. The caller is responsible for providing a valid
	// partition for a Message. If the Message's partition field wasn't set it
	// will always route to it's zero value, partition 0, which will create a
	// hot partition.
	ManualPartitioner
)

func (p Partitioner) toSarama() (sarama.PartitionerConstructor, error) {
	switch p {
	case RandomPartitioner:
		return sarama.NewRandomPartitioner, nil
	case RoundRobinPartitioner:
		return sarama.NewRoundRobinPartitioner, nil
	case HashPartitioner:
		// This uses sarama's NewReferenceHashPartitioner instead of
		// NewHashPartitioner to have behavior consistent with the Java Kafka
		// client implementation. This is due to NewHashPartition's
		// unintentional behavior being kept in the API after people started
		// depending on it.
		return sarama.NewReferenceHashPartitioner, nil
	case ManualPartitioner:
		return sarama.NewManualPartitioner, nil
	default:
		return nil, errors.New("invalid Partitioner")
	}
}

// RequiredAcks controls the number of acknowledgements from replicas the lead
// broker for a topic and partition must receive before responding to a produce
// request. This effectively controls the durability requirements of produced
// messages.
type RequiredAcks int

const (
	// AcksNone requires no acknowledgement from the leader that a message was
	// received when producing. If a produce request should fail to be
	// processed by the leader it will not be retried. It is not recommended
	// for use unless you have relaxed message durability requirements or need
	// to make the trade-off for throughput.
	AcksNone RequiredAcks = 0

	// AcksOne requires waiting only an acknowledgement from the leader that a
	// message was written to its local log. If the leader should fail before
	// the message can be replicated by any followers it will be lost.
	AcksOne RequiredAcks = 1

	// AcksAll requires waiting on acknowledgements from the leader and all
	// in-sync replicas that a message was received. This provides the
	// strongest durability guaranteeing that a message will not be lost as
	// long as at least 1 in-sync replica remains alive.
	AcksAll RequiredAcks = -1
)

func (ra RequiredAcks) toSarama() (sarama.RequiredAcks, error) {
	switch ra {
	case AcksNone:
		return sarama.NoResponse, nil
	case AcksOne:
		return sarama.WaitForLocal, nil
	case AcksAll:
		return sarama.WaitForAll, nil
	default:
		return sarama.RequiredAcks(0), errors.New("invalid RequiredAcks")
	}
}

// CompressionCodec specifies which compression codec (supported by Kafka) to
// use when producing messages.
type CompressionCodec int8

const (
	CompressionNone CompressionCodec = iota
	CompressionGZIP
	CompressionSnappy
	CompressionLZ4
	CompressionZSTD
)

func (cc CompressionCodec) toSarama() (sarama.CompressionCodec, error) {
	switch cc {
	case CompressionNone:
		return sarama.CompressionNone, nil
	case CompressionGZIP:
		return sarama.CompressionGZIP, nil
	case CompressionSnappy:
		return sarama.CompressionSnappy, nil
	case CompressionLZ4:
		return sarama.CompressionLZ4, nil
	case CompressionZSTD:
		return sarama.CompressionZSTD, nil
	default:
		return sarama.CompressionCodec(0), errors.New("invalid CompressionCodec")
	}
}

type kafkaSinkConfig struct {
	acks        *RequiredAcks
	compression struct {
		codec *CompressionCodec
		level *int
	}
	batch struct {
		bytes   *int
		size    *int
		timeout *time.Duration
	}
	sendAttempts   *int
	async          bool
	enqueueTimeout *time.Duration
	errorHandler   func(Message, error)
	producer       producer
}

// KafkaSinkOption is a functional option type that applies an optional config
// to a KafkaSink returning any encountered error.
type KafkaSinkOption = func(*kafkaSinkConfig) error

// WithPartitioner is the KafkaSinkOption that sets which Partitioner will be
// used when producing messages. Refer to the Partitioner docs for information
// about its behavior and/or requirements.
//
// Deprecated: Partitioning must be controlled with PublishOptions.
func WithPartitioner(p Partitioner) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		return nil
	}
}

// WithRequiredAcks is the KafkaSinkOption that specifies which RequiredAcks
// behavior will be used when producing messages. Refer to the RequiredAcks
// docs for information about the behavior and implications when producing.
func WithRequiredAcks(acks RequiredAcks) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		cfg.acks = &acks
		return nil
	}
}

// WithCompressionCodec is the KafkaSinkOption that sets which compression
// codec is used when producing messages. A codec will use its default
// compression level unless one is set using WithCompressionLevel.
func WithCompressionCodec(c CompressionCodec) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		cfg.compression.codec = &c
		return nil
	}
}

// WithCompressionLevel is the KafkaSinkOption that overrides the default
// compression level used by a CompressionCodec when producing messages.
func WithCompressionLevel(n int) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		cfg.compression.level = &n
		return nil
	}
}

// WithBatchBytes is the KafkaSinkOption that controls message batching
// behavior by enabling a threshold for the maximum number of bytes before a
// flush is triggered. A value of 0 disables this behavior.
//
// See the package overview section Kafka Producing details about batching.
func WithBatchBytes(n int) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		if n > int(sarama.MaxRequestSize) {
			return fmt.Errorf("max batch size bytes cannot exceed %d", sarama.MaxRequestSize)
		}
		cfg.batch.bytes = &n
		return nil
	}
}

// WithBatchSize is the KafkaSinkOption that controls message batching behavior
// by enabling a threshold for the maximum number of messages before a flush is
// triggered. A value of 0 disables this behavior.
//
// See the package overview section Kafka Producing details about batching.
func WithBatchSize(n int) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		cfg.batch.size = &n
		return nil
	}
}

// WithBatchTimeout is the KafkaSinkOption that controls message batching
// behavior by setting the timeout used to trigger a flush. By default no
// timeout will be used and batches will be flushed as quickly as possible.
//
// See the package overview section Kafka Producing details about batching.
func WithBatchTimeout(d time.Duration) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		if d < 0 {
			return errors.New("batch timeout must be >= 0")
		}
		cfg.batch.timeout = &d
		return nil
	}
}

// WithSendAttempts is the KafkaSinkOption that sets the amount of retries that
// will be attempted when a message batch send request fails, usually due to
// failure to meet the required acknowledgements.
func WithSendAttempts(n int) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		cfg.sendAttempts = &n
		return nil
	}
}

// WithAsync is the KafkaSinkOption that enables asynchronous producing. When
// enabled calls to Write will not block and any producer errors will be
// delivered asynchronously. The caller is responsible for handling the errors
// by setting a handler using WithWriteErrorHandler.
func WithAsync(b bool) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		cfg.async = b
		return nil
	}
}

// WithEnqueueTimeout is the KafkaSinkOption that sets the amount of time to
// block when sending a message to the internal producer channel, when running
// in async mode. By default no timeout will be used and the producer will
// block indefinitely. If set to -1 the timeout is disabled.
func WithEnqueueTimeout(d time.Duration) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		if d < 0 {
			cfg.enqueueTimeout = nil
		}
		cfg.enqueueTimeout = &d
		return nil
	}
}

// withProducer is a test-only option to override the sarama producer.
func withProducer(p producer) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		cfg.producer = p
		return nil
	}
}

// WithWriteErrorHandler is the KafkaSinkOption that sets a func(Message,
// error) handler used for async producer error handling. When async is enabled
// and a producer error occurs the handler will be called with the failed
// Message and error.
//
// If an error handler panics it will be recovered and logged but the error
// will not retried. It is recommended but not required for handlers to be safe
// for concurrent use. Handler funcs must not block or they may deadlock the
// producer.
func WithWriteErrorHandler(fn func(Message, error)) KafkaSinkOption {
	return func(cfg *kafkaSinkConfig) error {
		cfg.errorHandler = fn
		return nil
	}
}

// KafkaSink implements the Sink interface for producing Messages to Kafka. It
// must be created using NewKafkaSink and configured with KafkaSinkOptions.
type KafkaSink struct {
	client   sarama.Client
	producer producer
	reporter *saramaStatsReporter
}

// NewKafkaSink returns a new KafkaSink using the provided KafkaConfig and
// KafkaSinkOptions. It returns an error if the KafkaConfig is invalid or a
// KafkaSinkOption fails to apply.
//
// The caller must call Close when done using the KafkaSink.
//
// Unless overridden with a KafkaSinkOption it will be configured with the
// following defaults: RandomPartitioner, AcksOne, no compression, sync
// producing, and 3 send retry attempts.
func NewKafkaSink(kc KafkaConfig, opts ...KafkaSinkOption) (*KafkaSink, error) {
	ksc := new(kafkaSinkConfig)
	for _, o := range opts {
		if err := o(ksc); err != nil {
			return nil, fmt.Errorf("applying KafkaSinkOption: %w", err)
		}
	}

	if ksc.acks == nil {
		acks := AcksOne
		ksc.acks = &acks
	}
	acks, err := ksc.acks.toSarama()
	if err != nil {
		return nil, err
	}

	if ksc.compression.codec == nil {
		c := CompressionNone
		ksc.compression.codec = &c
	}
	compression, err := ksc.compression.codec.toSarama()
	if err != nil {
		return nil, err
	}

	sc := kc.toSarama()

	// sarama.Config.Producer configs
	sc.Producer.MaxMessageBytes = MaxMessageBytes
	sc.Producer.RequiredAcks = acks
	sc.Producer.Compression = compression
	if ksc.compression.level != nil {
		sc.Producer.CompressionLevel = *ksc.compression.level
	}
	sc.Producer.Partitioner = newPartitioner

	// sarama.Config.Producer.Return configs
	if ksc.async {
		sc.Producer.Return.Successes = false
		sc.Producer.Return.Errors = true
	} else {
		sc.Producer.Return.Successes = true
		sc.Producer.Return.Errors = true
	}

	// sarama.Config.Producer.Flush configs
	if ksc.batch.bytes != nil {
		sc.Producer.Flush.Bytes = *ksc.batch.bytes
	}
	if ksc.batch.size != nil {
		sc.Producer.Flush.Messages = *ksc.batch.size
	}
	if ksc.batch.timeout != nil {
		sc.Producer.Flush.Frequency = *ksc.batch.timeout
	}

	// sarama.Config.Producer.Retry configs With a retry backoff of 100ms and
	// assuming 5ms metadata requests, we expect the producer to block for up
	// to ~3150ms (30 * (100ms + 5ms)) by default.
	sc.Producer.Retry.Max = 30
	if ksc.sendAttempts != nil {
		sc.Producer.Retry.Max = *ksc.sendAttempts
	}

	// apply optional overrides of the final sarama configs
	for _, override := range kc.overrides {
		override(sc)
	}

	client, err := sarama.NewClient(kc.brokers, sc)
	if err != nil {
		return nil, fmt.Errorf("creating sarama client: %w", err)
	}

	var p producer
	switch {
	case ksc.producer != nil:
		p = ksc.producer
	case ksc.async:
		ap, err := sarama.NewAsyncProducerFromClient(client)
		if err != nil {
			return nil, fmt.Errorf("creating async producer: %w", err)
		}

		errHandler := &producerErrorHandler{
			fn: func(pe *sarama.ProducerError) {
				// TODO: add stat for async produce error count

				msg, err := producerMessageToMessage(pe.Msg)
				if err != nil {
					kc.log.Printf("error converting producer message: %v", err)
				}

				if ksc.errorHandler != nil {
					ksc.errorHandler(msg, pe.Err)
				}
			},
			log: kc.log,
		}
		errHandler.startHandle(ap.Errors())

		p = &asyncProducer{
			p:              ap,
			enqueueTimeout: ksc.enqueueTimeout,
			errHandler:     errHandler,
		}
	default:
		p, err = sarama.NewSyncProducerFromClient(client)
		if err != nil {
			return nil, fmt.Errorf("creating sync producer: %w", err)
		}
	}

	var reporter *saramaStatsReporter
	if kc.stats != stats.NullStatter {
		reporter = &saramaStatsReporter{
			metrics: sc.MetricRegistry,
			adapter: &metricStatsAdapter{
				prefix: "kafka.",
				client: kc.stats,
			},
			ticker: time.NewTicker(kc.sampleRate),
		}
		go reporter.Run()
	}

	return &KafkaSink{
		client:   client,
		producer: p,
		reporter: reporter,
	}, nil
}

// Write writes the Message to its topic and a partition controlled by its
// metadata (see the section on Partitioning for details). It is safe for
// concurrent use.
//
// When sync producing is enabled the call blocks until the Message has been
// written and satisfies the configured RequiredAcks. It will return an error
// if the request fails.
//
// When async producing is enabled the call blocks until the Message has been
// sent on an internal channel. The configured RequiredAcks and retry attempts
// will still be honored. If the request fails it returns nil and the error
// will be asynchronously handled by the write error handler if configured.
func (ks *KafkaSink) Write(m Message) error {
	// TODO: report write stats
	pm := messageToProducerMessage(m)
	_, _, err := ks.producer.SendMessage(pm)
	return err
}

func (ks *KafkaSink) WriteBatch(msgs []Message) error {
	pms := make([]*sarama.ProducerMessage, len(msgs))
	for i, msg := range msgs {
		pms[i] = messageToProducerMessage(msg)
	}
	// TODO: report write stats
	return ks.producer.SendMessages(pms)
}

// Flush has no effect on a KafkaSink.
func (ks *KafkaSink) Flush() error {
	return nil
}

// Close initiates a shutdown blocking until it's complete. It will attempt to
// flush any pending writes. While shutting down concurrent calls to Write may
// error. After Close returns all subsequent calls to Write will error. Close
// is not safe for concurrent use and should not be called multiple times.
//
// The shutdown process involves actions that may independently fail. As a
// result Close can return multiple errors. When it returns an error the caller
// is recommended to check for the Errors interface.
func (ks *KafkaSink) Close() error {
	var el ErrorList

	// producer must be closed before the client
	if err := ks.producer.Close(); err != nil {
		el = append(el, fmt.Errorf("closing sarama producer: %w", err))
	}

	if ks.reporter != nil {
		ks.reporter.Stop()
	}

	if err := ks.client.Close(); err != nil {
		el = append(el, fmt.Errorf("closing sarama client: %w", err))
	}

	if len(el) > 0 {
		return el
	}
	return nil
}

// producer is the interface that wraps the SendMessage and Close methods. This
// is required because sarama's sync and async producers don't have a common
// interface.
type producer interface {
	SendMessage(msg *sarama.ProducerMessage) (partition int32, offset int64, err error)
	SendMessages(msgs []*sarama.ProducerMessage) error
	Close() error
}

// asyncProducer implements the producer interface by wrapping a
// sarama.AsyncProducer.
type asyncProducer struct {
	p              sarama.AsyncProducer
	enqueueTimeout *time.Duration
	errHandler     *producerErrorHandler
}

// SendMessage does a send of the *sarama.ProducerMessage on to the wrapped
// sarama.AsyncProducer's internal channel. By default, the send is blocking,
// and SendMessage will never return an error. If an WithEnqueueTimeout is
// set, it will block only up-to `ap.enqueueTimeout`, and return an error if
// the timeout expires.
//
// If the timeout expires, the message is not queued for publishing. It is up
// to the caller to decide if it wants to retry sending message or to drop it.
//
// Errors writing to the kafka brokers are passed asynchronously to an error handler
// if enabled using the WithWriteErrorHandler option.
func (ap *asyncProducer) SendMessage(msg *sarama.ProducerMessage) (partition int32, offset int64, err error) {
	if ap.enqueueTimeout == nil {
		// Enqueue timeout is disabled
		ap.p.Input() <- msg
		return 0, 0, nil
	}

	select {
	case ap.p.Input() <- msg:
		return 0, 0, nil
	case <-time.After(*ap.enqueueTimeout):
		return 0, 0, errors.New("enqueue message timed out")
	}
}

// SendMessages does a blocking send of all *sarama.ProducerMessage on to the
// wrapped sarama.AsyncProducer's internal channel. It never returns an error.
func (ap *asyncProducer) SendMessages(msgs []*sarama.ProducerMessage) error {
	for _, msg := range msgs {
		_, _, _ = ap.SendMessage(msg)
	}
	return nil
}

// Close calls the blocking Close method on the wrapped sarama.AsyncProducer.
func (ap *asyncProducer) Close() error {
	err := ap.p.Close()

	// Wait for error handler to process any outstanding errors - otherwise
	// there might be unreported errors.
	ap.errHandler.waitForHandleToStop()

	// The Sarama async producer drains the error channel during Close, and
	// returns all the errors grouped together as sarama.ProducerErrors. This is
	// not desirable, because (a) it's inconsistent (we'd like all errors to be
	// passed to the error handler the user provided with WithWriteErrorHandler,
	// and (b) it's non-deterministic, because the error draining loop races
	// with producerErrorHandler.Handle.
	//
	// Therefore, this code unwraps the errors, and calls the error handler for
	// each one. The errors might be reported out of order, but they will all be
	// reported.

	list, ok := err.(sarama.ProducerErrors)
	if err == nil || !ok {
		return err
	}

	for _, pe := range list {
		ap.errHandler.handleSafe(pe)
	}
	return nil
}

// producerErrorFunc is a func type used to handle an async
// sarama.ProducerError.
type producerErrorFunc func(*sarama.ProducerError)

// producerErrorHandler enables safe handling of a async sarama.ProducerErrors
// from a sarama.AsyncProducer using a producerErrorFunc.
type producerErrorHandler struct {
	fn  producerErrorFunc
	log Logger
	wg  sync.WaitGroup // used during Close to wait for error handler to finish
}

func (peh *producerErrorHandler) startHandle(errors <-chan *sarama.ProducerError) {
	peh.wg.Add(1)
	go func() {
		defer peh.wg.Done()
		peh.Handle(errors)
	}()
}

func (peh *producerErrorHandler) waitForHandleToStop() {
	peh.wg.Wait()
}

// Handle ranges over the provided channel and safely invoking the
// producerErrorFunc with each sarama.ProducerError. It returns when the errors
// channel has been drained and closed.
func (peh *producerErrorHandler) Handle(errors <-chan *sarama.ProducerError) {
	if errors == nil {
		return
	}

	for err := range errors {
		// TODO: report error stat
		if peh.fn != nil {
			peh.handleSafe(err)
		}
	}
}

// handleSafe calls the producerErrorFunc with the error. If the error func
// panics it will be recovered. Recovered panics will be logged when a Logger
// is set.
func (peh *producerErrorHandler) handleSafe(err *sarama.ProducerError) {
	defer func() {
		if r := recover(); r != nil {
			if peh.log != nil {
				peh.log.Printf("panic in async producer error handler: %v", r)
			}
		}
	}()
	peh.fn(err)
}

func messageToProducerMessage(m Message) *sarama.ProducerMessage {
	var saramaHeaders []sarama.RecordHeader
	if len(m.Headers) > 0 {
		for key, value := range m.Headers {
			saramaHeaders = append(saramaHeaders, sarama.RecordHeader{
				Key:   []byte(key),
				Value: []byte(value),
			})
		}
	}

	return &sarama.ProducerMessage{
		Topic:     m.Topic,
		Key:       sarama.ByteEncoder(m.Key),
		Value:     sarama.ByteEncoder(m.Value),
		Partition: m.Partition,
		Offset:    m.Offset,
		Timestamp: m.Timestamp,
		Metadata:  m.Metadata,
		Headers:   saramaHeaders,
	}
}

func producerMessageToMessage(pm *sarama.ProducerMessage) (Message, error) {
	var key, value []byte
	var err error

	if pm.Key != nil {
		key, err = pm.Key.Encode()
		if err != nil {
			return Message{}, fmt.Errorf("encoding key: %w", err)
		}
	}

	if pm.Value != nil {
		value, err = pm.Value.Encode()
		if err != nil {
			return Message{}, fmt.Errorf("encoding value: %w", err)
		}
	}

	meta, _ := pm.Metadata.(*PartitionerMetadata)
	var headers map[string]string
	if len(pm.Headers) > 0 {
		headers = make(map[string]string, len(pm.Headers))
		for _, header := range pm.Headers {
			headers[string(header.Key)] = string(header.Value)
		}
	}

	return Message{
		Topic:     pm.Topic,
		Key:       key,
		Value:     value,
		Partition: pm.Partition,
		Offset:    pm.Offset,
		Timestamp: pm.Timestamp,
		Metadata:  meta,
		Headers:   headers,
	}, nil
}

// partitioner implements the sarama.Partitioner interface by using
// PartitionerMetadata passed through a sarama.ProducerMessage's Metadata field
// to control it's partitioning behavior per Message.
type partitioner struct {
	random sarama.Partitioner
	hasher hash.Hash32
}

// newPartitioner implements the sarama.PartitionerConstructor interface for
// creating a topic partitioner that uses FNV for key based partitioning and
// sarama's implementation for random partitioning.
func newPartitioner(topic string) sarama.Partitioner {
	return &partitioner{
		random: sarama.NewRandomPartitioner(topic),
		hasher: fnv.New32a(),
	}
}

// Partition attempts to select a valid partition by using a
// PartitionerMetadata passed through the message's Metadata field.
//
// When a non-nil Partition field is present, its value will be returned. If
// the value is out-of-bounds it will return an error.
//
// When a non-empty PartitionKey field is present, a deterministic partition
// will be calculated by using modular hashing (same behavior as the Java
// reference implementation).
//
// When no PartitionerMetadata or eligible fields are present a random
// partition will be returned.
func (p *partitioner) Partition(m *sarama.ProducerMessage, numPartitions int32) (int32, error) {
	meta, _ := m.Metadata.(*PartitionerMetadata)
	if meta != nil {
		if meta.Partition != nil {
			n := *meta.Partition
			if n >= numPartitions {
				return -1, fmt.Errorf("partition %d is out-of-bounds for topic %q", n, m.Topic)
			}
			return n, nil
		}

		if len(meta.PartitionKey) > 0 {
			p.hasher.Reset()
			_, err := p.hasher.Write(meta.PartitionKey)
			if err != nil {
				return -1, err
			}
			return calculatePartition(p.hasher.Sum32(), numPartitions), nil
		}
	}

	return p.random.Partition(m, numPartitions)
}

func (p *partitioner) RequiresConsistency() bool { return true }

// calculatePartition returns the partition calculated from modular hashing
// with an uint32. It's based off of sarama's NewReferenceHashPartitioner that
// handles absolute values the same way as the reference Java implementation.
func calculatePartition(sum uint32, numPartitions int32) int32 {
	return (int32(sum) & 0x7fffffff) % numPartitions
}
