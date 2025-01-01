package hydro

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/proto"
)

// Publisher is used to produce Hydro event to its configured Sink. Events are
// encoded using its configured Encoder. It must be created with NewPublisher
// and configured with PublisherOptions. It is safe for concurrent use by
// multiple goroutines.
type Publisher struct {
	sink           Sink
	topicFormatter topicFormatter
	encoder        Encoder
	stats          stats.Client
}

// PublisherOption is a function that configures a Publisher and returns an
// error if encountered.
type PublisherOption func(*Publisher) error

// WithTopicFormat is a PublisherOption that overrides the default TopicFormat
// version used when formatting the topic name an event will be published to.
//
// See TopicFormat and DefaultTopicFormat for more details.
func WithTopicFormat(tf TopicFormat) PublisherOption {
	return func(p *Publisher) error {
		if err := tf.validate(); err != nil {
			return err
		}
		p.topicFormatter.version = tf
		return nil
	}
}

// WithSiteName is a PublisherOption that overrides the default site name
// ("cp1-iad") used by TopicFormatV1.
//
// The default site name should almost never be overridden outside of tests.
func WithSiteName(s string) PublisherOption {
	return func(p *Publisher) error {
		if s == "" {
			return errors.New("site name must not be empty")
		}
		p.topicFormatter.site = s
		return nil
	}
}

// WithNamespace is a PublisherOption that overrides the default namespace
// ("ingest") used by TopicFormatV1.
//
// The default namespace should almost never be overridden outside of tests.
func WithNamespace(s string) PublisherOption {
	return func(p *Publisher) error {
		if s == "" {
			return errors.New("namespace must not be empty")
		}
		p.topicFormatter.namespace = s
		return nil
	}
}

// WithEncoder is a PublisherOption that overrides the default encoder used to
// encode events when publishing.
func WithEncoder(e Encoder) PublisherOption {
	return func(p *Publisher) error {
		if e == nil {
			return errors.New("encoder must not be nil")
		}
		p.encoder = e
		return nil
	}
}

// WithPublisherStats is a PublisherOption that overrides the default
// stats.Client used to report Publisher stats.
func WithPublisherStats(sc stats.Client) PublisherOption {
	return func(p *Publisher) error {
		p.stats = sc
		return nil
	}
}

type publishConfig struct {
	topic                   string
	partition               *int32
	key                     []byte
	partitionKey            []byte
	verificationSecretLabel string
	verificationSecret      string
	timestamp               *time.Time
	headers                 map[string]string
	nilMsg                  bool
}

func processPublishOpts(opts []PublishOption) (publishConfig, error) {
	var cfg publishConfig
	for _, o := range opts {
		if err := o(&cfg); err != nil {
			return cfg, err
		}
	}

	if cfg.nilMsg {
		// require a topic since it can't be inferred from the msg type
		if cfg.topic == "" {
			return cfg, errors.New("a topic must be provided using WithTopic when producing WithNilMessage")
		}

		// require a msg key since they're used for topic compaction
		if len(cfg.key) == 0 {
			return cfg, errors.New("a key must be provided using WithKey when producing WithNilMessage")
		}

		// use msg key as its partition key if not overridden
		if cfg.partitionKey == nil {
			cfg.partitionKey = cfg.key
		}
	}

	return cfg, nil
}

func (cfg *publishConfig) getTimestamp() time.Time {
	if cfg.timestamp != nil {
		return *cfg.timestamp
	}
	return time.Now()
}

// PublishOption is a functional option that controls the behavior of a
// Publisher's Publish method.
type PublishOption func(*publishConfig) error

// WithTopic is the PublishOption that overrides the behavior of a TopicFormat
// when formatting the topic name an event will be published to.
//
// See the definition of the TopicFormat configured for a Publisher for details
// about what this controls.
func WithTopic(s string) PublishOption {
	return func(c *publishConfig) error {
		if s == "" {
			return errors.New("topic must be non-empty")
		}
		c.topic = s
		return nil
	}
}

// WithKey is the PublishOption that sets an optional key when publishing with
// a Sink that supports keys. This field can be used as metadata for consumers.
func WithKey(s string) PublishOption {
	return func(c *publishConfig) error {
		c.key = []byte(s)
		return nil
	}
}

// WithPartition is the PublishOption that overrides the default random
// partitioning behavior by manually assigning which partition the event will
// be produced to. It returns an error if the value is negative.
//
// Manual partition assignment is discouraged as it can be error prone and
// cause an uneven distribution across partitions. If an invalid partition is
// assigned it may result in the event not being published (with or without
// error).
func WithPartition(n int32) PublishOption {
	return func(c *publishConfig) error {
		if n < 0 {
			return errors.New("partition must be >= 0")
		}
		c.partition = &n
		return nil
	}
}

// WithVerificationHeaders is the PublishOption that specifies that a HMAC signiture
// of the data should be calculated and sent as a header (along with the label)
func WithVerificationHeaders(label, secret string) PublishOption {
	return func(c *publishConfig) error {
		c.verificationSecretLabel = label
		c.verificationSecret = secret
		return nil
	}
}

// WithPartitionKey is the PublishOption that overrides the default random
// partitioning behavior by assigning a partition calculated by modular hashing
// the provided key. For logically related Hydro events that require
// per-partition ordering the partition key must be stable.
func WithPartitionKey(s string) PublishOption {
	return func(c *publishConfig) error {
		c.partitionKey = []byte(s)
		return nil
	}
}

func WithCustomHeaders(headers map[string]string) PublishOption {
	return func(c *publishConfig) error {
		c.headers = headers
		return nil
	}

}

// WithTimestamp is the PublishOption that overrides which timestamp a message
// is encoded with (if supported by the Encoder). If this PublishOption is not
// provided, time.Now() will be used when Publish is called.
//
// This allows for use cases where you need to publish a message that was
// created at some past time, e.g. backfilling events.
func WithTimestamp(t time.Time) PublishOption {
	return func(c *publishConfig) error {
		c.timestamp = &t
		return nil
	}
}

// WithNilMessage is the PublishOption that allows for producing a "tombstone
// record" to a compacted topic when publishing with a KafkaSink.
//
// Kafka uses a message's key for topic compaction, so a valid topic and key
// must be provided using [WithTopic] and [WithKey].
//
// Compacted topics require deterministic and consistent partitioning.
// Partitioning behavior is controlled by (highest to lowest precedence):
//  1. Manually using [WithPartition]
//  2. Calculated from [WithPartitionKey]
//  3. Calculated from [WithKey]
func WithNilMessage() PublishOption {
	return func(c *publishConfig) error {
		c.nilMsg = true
		return nil
	}
}

// NewPublisher returns a Publisher capable of publishing Hydro events to the
// provided Sink and Site of origin. The Publisher is configured by applying
// PublisherOptions returning any errors encountered.
//
// The caller is responsible for calling the Close method.
//
// Unless overridden by a PublisherOption it uses the DefaultEncoder,
// DefaultTopicFormat, and stats.NullStatter.
func NewPublisher(sink Sink, opts ...PublisherOption) (*Publisher, error) {
	p := &Publisher{
		topicFormatter: defaultTopicFormatter(),
	}
	for _, opt := range opts {
		if err := opt(p); err != nil {
			return nil, err
		}
	}

	if sink == nil {
		return nil, errors.New("sink must be non-nil")
	}
	p.sink = sink

	if p.encoder == nil {
		p.encoder = NewDefaultEncoder()
	}

	if p.stats == nil {
		p.stats = stats.NullStatter
	}

	return p, nil
}

// Publish encodes the proto.Message Hydro event and writes it to the
// Publisher's configured Sink.
//
// The event will be produced to a Hydro topic formatted using the Publisher's
// configured TopicFormat. See TopicFormat for formatting details.
//
// When the configured Sink supports partitioning, a random partition will be
// assigned by default. This behavior can be overridden by providing one of the
// partitioning related PublishOptions. See WithPartition and WithPartitionKey
// for more details.
//
// It is safe for use by concurrent goroutines.
func (p *Publisher) Publish(m proto.Message, opts ...PublishOption) error {
	var topic string
	var err error

	start := time.Now()
	defer func() {
		status := success
		if err != nil {
			status = failed
		}
		tags := stats.Tags{"status": status}
		if topic != "" {
			tags["topic"] = topic
		}
		p.stats.Timing("publish.time", tags, time.Since(start))
	}()

	cfg, err := processPublishOpts(opts)
	if err != nil {
		return fmt.Errorf("applying PublishOptions: %w", err)
	}

	if cfg.nilMsg {
		m = nil
	}

	topic, err = p.resolveTopic(m, cfg)
	if err != nil {
		return fmt.Errorf("resolving topic: %w", err)
	}

	encoded, err := p.encode(topic, m, cfg.getTimestamp())
	if err != nil {
		return fmt.Errorf("encoding message: %w", err)
	}

	headers, err := p.buildVerificationHeaders(cfg.verificationSecret, cfg.verificationSecretLabel, encoded)
	if err != nil {
		return fmt.Errorf("generating verification signature: %w", err)
	}

	headers = p.buildHeaders(headers, cfg.headers)

	var metadata *PartitionerMetadata
	if cfg.partition != nil || len(cfg.partitionKey) > 0 {
		metadata = &PartitionerMetadata{
			Partition:    cfg.partition,
			PartitionKey: cfg.partitionKey,
		}
	}

	payload := Message{
		Topic:    topic,
		Key:      cfg.key,
		Value:    encoded,
		Metadata: metadata,
		Headers:  headers,
	}
	if err := p.sink.Write(payload); err != nil {
		return fmt.Errorf("writing message to topic %q: %w", topic, err)
	}

	return nil
}

type BatchMessage struct {
	msg  proto.Message
	opts []PublishOption
}

type Batch struct {
	msgs []BatchMessage
}

func NewBatch() *Batch {
	return &Batch{}
}

func (b *Batch) Add(m proto.Message, opts ...PublishOption) {
	b.msgs = append(b.msgs, BatchMessage{
		msg:  m,
		opts: opts,
	})
}

// PublishBatch publishes a batch of messages to the Publisher's configured Sink
// in a single request. This is a synchronous operation, so you will get an
// error if the batch fails to publish.
func (p *Publisher) PublishBatch(batch *Batch) error {
	var topic string
	var err error

	start := time.Now()
	defer func() {
		status := success
		if err != nil {
			status = failed
		}
		tags := stats.Tags{"status": status}
		if topic != "" {
			tags["topic"] = topic
		}
		p.stats.Timing("publish.batch.time", tags, time.Since(start))
	}()

	if len(batch.msgs) == 0 {
		return errors.New("batch must not be empty")
	}

	payloads := make([]Message, len(batch.msgs))
	for i, m := range batch.msgs {
		cfg, err := processPublishOpts(m.opts)
		if err != nil {
			return fmt.Errorf("applying PublishOptions: %w", err)
		}

		if cfg.nilMsg {
			m.msg = nil
		}

		topic, err = p.resolveTopic(m.msg, cfg)
		if err != nil {
			return fmt.Errorf("resolving topic: %w", err)
		}

		encoded, err := p.encode(topic, m.msg, cfg.getTimestamp())
		if err != nil {
			return fmt.Errorf("encoding message: %w", err)
		}

		headers, err := p.buildVerificationHeaders(cfg.verificationSecret, cfg.verificationSecretLabel, encoded)
		if err != nil {
			return fmt.Errorf("generating verification signature: %w", err)
		}

		headers = p.buildHeaders(headers, cfg.headers)

		var metadata *PartitionerMetadata
		if cfg.partition != nil || len(cfg.partitionKey) > 0 {
			metadata = &PartitionerMetadata{
				Partition:    cfg.partition,
				PartitionKey: cfg.partitionKey,
			}
		}

		payloads[i] = Message{
			Topic:    topic,
			Key:      cfg.key,
			Value:    encoded,
			Metadata: metadata,
			Headers:  headers,
		}
	}

	if err := p.sink.WriteBatch(payloads); err != nil {
		return fmt.Errorf("writing batch: %w", joinSaramaErrors(err))
	}

	return nil
}

// joinSaramaErrors reformats the error returned by sarama to actually print out
// the sub errors. It consolidates the errors by topic and error message, since
// it's likely errors are all going to be the same a lot of the time.
func joinSaramaErrors(err error) error {
	var producerErrs sarama.ProducerErrors
	if !errors.As(err, &producerErrs) {
		return err
	}

	type topicErr struct {
		topic string
		err   string
	}

	// dedup so we don't print the same error a million times
	topicErrs := map[topicErr]error{}
	for _, e := range producerErrs {
		topicErrs[topicErr{e.Msg.Topic, e.Err.Error()}] = e
	}

	errStrings := make([]string, 0, len(topicErrs))
	// add the original error to the front so we maintain that overall error message,
	// and ensure that if any code was looking for that original error, it still exists
	for _, e := range topicErrs {
		errStrings = append(errStrings, e.Error())
	}
	// concatenate the underlying error messages together, using the original
	// error as the first line. This will give the same error message as using
	// the go 1.20's stdlib errors.Join.
	return fmt.Errorf("%w\n%s", err, strings.Join(errStrings, "\n"))
}

const (
	success string = "success"
	failed  string = "failed"
)

// PublishToTopic calls Publish using the WithTopic option to publish the Hydro
// event to a specific topic.
//
// Deprecated: Publish using WithTopic should be used instead.
func (p *Publisher) PublishToTopic(m proto.Message, suffix string) (err error) {
	return p.Publish(m, WithTopic(suffix))
}

func (p *Publisher) resolveTopic(m proto.Message, cfg publishConfig) (string, error) {
	if m == nil && !cfg.nilMsg {
		return "", errors.New("message must not be nil unless using WithNilMessage")
	}

	topic, err := p.topicFormatter.Format(m, cfg.topic)
	if err != nil {
		return "", fmt.Errorf("formatting topic: %w", err)
	}

	return topic, nil
}

func (p *Publisher) encode(topic string, m proto.Message, timestamp time.Time) ([]byte, error) {
	if m == nil {
		return nil, nil
	}

	t := time.Now()
	status := success
	bytes, err := p.encoder.Encode(m, timestamp)
	if err != nil {
		status = failed
	}

	tags := stats.Tags{"topic": topic, "status": status}
	p.stats.Timing("encode.time", tags, time.Since(t))
	return bytes, err
}

func (p *Publisher) buildVerificationHeaders(secret, label string, data []byte) (map[string]string, error) {
	if secret == "" {
		return nil, nil
	}

	mac := hmac.New(sha256.New, []byte(secret))
	_, err := mac.Write(data)
	if err != nil {
		return nil, err
	}

	signature := hex.EncodeToString(mac.Sum(nil))

	return map[string]string{
		"verification_secret_label": label,
		"verification_signature":    signature,
	}, nil
}

func (p *Publisher) buildHeaders(verificationHeaders map[string]string, headers map[string]string) map[string]string {

	if len(verificationHeaders) == 0 && len(headers) == 0 {
		return nil
	}

	mergedHeaders := make(map[string]string)

	if len(verificationHeaders) > 0 {
		for label, secret := range verificationHeaders {
			mergedHeaders[label] = secret
		}
	}

	if len(headers) > 0 {
		for headerKey, headerValue := range headers {
			mergedHeaders[headerKey] = headerValue
		}
	}
	return mergedHeaders

}

// Close closes the Publisher by flushing and closing its Sink. It returns any
// errors encountered while closing. When multiple errors occur they will be
// returned using the Errors interface. Once the Close method has been called
// the Publisher must be discarded.
func (p *Publisher) Close() error {
	var el ErrorList

	if err := p.Flush(); err != nil {
		el = append(el, err)
	}

	if err := p.sink.Close(); err != nil {
		el = append(el, err)
	}

	if len(el) > 0 {
		return el
	}

	return nil
}

// Flush flushes the Publisher's Sink. Calls to Flush are not required as they
// will be handled internally.
func (p *Publisher) Flush() error {
	return p.sink.Flush()
}
