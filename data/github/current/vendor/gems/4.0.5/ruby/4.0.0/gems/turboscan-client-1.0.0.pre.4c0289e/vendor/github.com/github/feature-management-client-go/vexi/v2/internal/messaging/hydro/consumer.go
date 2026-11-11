// Package hydro contains the client for consuming messages from hydro.
package hydro

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/internal"
	"github.com/github/feature-management-client-go/vexi/v2/internal/messaging"
	hydro_client_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"golang.org/x/sync/syncmap"
	"google.golang.org/protobuf/proto"
)

// ConsumerConfig is the configuration required to load the hydro consumer.
type ConsumerConfig struct {
	HydroBrokers  string                       // Comma delimited broker strings for Hydro
	HydroRootCA   string                       // Root CA for Hydro. Used for TLS if not using the system configuration.
	IsDevelopment bool                         // IsDevelopment configures if we use TLS certificates if enabled.
	KafkaOptions  []hydropkg.KafkaConfigOption // KafkaOptions additional configuration options to pass to underlying Kafka client.
}

// Validate determines if the configuration is correct.
func (c *ConsumerConfig) Validate() error {
	if c.HydroBrokers == "" {
		return vexi_errors.NewValidationError("The Hydro broker list is required")
	}
	return nil
}

// SingleTopicStatelessConsumer is a message consumer that can consume events from a single topic in Hydro.
type SingleTopicStatelessConsumer struct {
	t                   internal.Telemetry
	manualKafkaSource   manualKafkaSourceInterface
	partitionsOffsetMap syncmap.Map
	topic               string
	subscribed          bool
	PartitionIDs        map[int32]bool
}

// NewSingleTopicStatelessConsumer subscribes to the specified topic from the oldest message and returns a new instance of the SingleTopicStatelessConsumer.
func NewSingleTopicStatelessConsumer(ctx context.Context, cfg ConsumerConfig, t internal.Telemetry, topic string, partitionIDs map[int32]bool) (*SingleTopicStatelessConsumer, error) {
	manualKafkaSource, err := newManualKafkaSource(ctx, cfg, t)
	if err != nil {
		return nil, err
	}

	return &SingleTopicStatelessConsumer{
		t:                   t,
		manualKafkaSource:   manualKafkaSource,
		partitionsOffsetMap: syncmap.Map{},
		topic:               topic,
		subscribed:          false,
		PartitionIDs:        partitionIDs,
	}, nil
}

// Start subscribes to the configured topic.
func (s *SingleTopicStatelessConsumer) Start(ctx context.Context) error {
	if s.subscribed {
		return nil
	}

	if s.PartitionIDs[messaging.AllPartitions] {
		err := s.manualKafkaSource.SubscribeToTopic(s.topic, int64(hydropkg.OffsetOldest))
		if err != nil {
			return vexi_errors.NewWrappedError(err, fmt.Sprintf("error subscribing to topic %s", s.topic))
		}
	} else {
		for partitionID := range s.PartitionIDs {
			err := s.manualKafkaSource.Subscribe(s.topic, partitionID, int64(hydropkg.OffsetOldest))
			if err != nil {
				return vexi_errors.NewWrappedError(err, fmt.Sprintf("error subscribing to topic %s on partition ID %d", s.topic, partitionID))
			}
		}
	}

	s.subscribed = true

	return nil
}

// ReadMessage reads a message from the topic and converts and replaces hydro message values from the hydro envelope with actual protobuf payload message bytes.
func (s *SingleTopicStatelessConsumer) ReadMessage(ctx context.Context) (*messaging.Message, error) {
	if !s.subscribed {
		return nil, errors.New("consumer has not been started, call start() first")
	}

	msg, err := s.manualKafkaSource.ReadMessage(ctx)
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, fmt.Sprintf("error reading message from topic %s", s.topic))
	}

	// Even if there is an error after this at this point we've already read the message from the topic and have to advance the offset.
	s.partitionsOffsetMap.Store(msg.Partition, msg.Offset)

	// The hydro.Message contains an encoded protobuf, so we must decode the event.
	envelope := &hydro_client_pb.Envelope{}
	if err := proto.Unmarshal(msg.Value, envelope); err != nil {
		return nil, vexi_errors.NewWrappedError(err, fmt.Sprintf("error unmarshalling the payload to the hydro envelope struct for message with offset %d and partition %d", msg.Offset, msg.Partition))
	}

	// Convert the envelope message to a messaging.Message.
	return &messaging.Message{
		Topic:     s.topic,
		Key:       msg.Key,
		Value:     envelope.Message,
		Partition: msg.Partition,
		Offset:    msg.Offset,
		Timestamp: msg.Timestamp,
		Headers:   msg.Headers,
		Metadata: &messaging.PartitionerMetadata{
			Partition:    &msg.Partition,
			PartitionKey: msg.Key,
		},
	}, nil
}

// HighWaterMarks returns the current high water marks for each partition.
func (s *SingleTopicStatelessConsumer) HighWaterMarks() (map[int32]int64, error) {
	if !s.subscribed {
		return nil, errors.New("consumer has not been started, call start() first")
	}

	// Get the high water marks for the feature flags and validate it.
	highWaterMarks := s.manualKafkaSource.HighWaterMarks()

	if len(highWaterMarks) > 1 {
		topics := make([]string, 0, len(highWaterMarks))
		for topic := range highWaterMarks {
			topics = append(topics, topic)
		}
		return nil, fmt.Errorf("the consumer appears to have more than one topic: %v", topics)
	}

	if len(highWaterMarks) == 0 {
		return nil, fmt.Errorf("no high water marks found for the configured topic %s", s.topic)
	}

	return highWaterMarks[s.topic], nil
}

// CurrentWaterMarks returns the current local water marks for each partition.
func (s *SingleTopicStatelessConsumer) CurrentWaterMarks(ctx context.Context) map[int32]int64 {
	currentWaterMarks := make(map[int32]int64)

	s.partitionsOffsetMap.Range(func(key, value interface{}) bool {
		partition, ok := key.(int32)
		if !ok {
			// Log here in case the map gets corrupted. This should ideally never occur since we guard against with type safety.
			err := vexi_errors.NewValidationError(fmt.Sprintf("non int32 value %v found as key in the current water marks map", key))
			s.t.LogWithError(ctx, err, "error getting current water marks due to corrupted partition offset map")

			// Ignore the error and continue to the next iteration.
			return true
		}

		offset, ok := value.(int64)
		if !ok {
			// Log here in case the map gets corrupted. This should ideally never occur since we guard against with type safety.
			err := vexi_errors.NewValidationError(fmt.Sprintf("non int64 value %v found as value for partition %d in the current water marks map", value, partition))
			s.t.LogWithError(ctx, err, "error getting current water marks due to corrupted partition offset map")

			// Ignore the error and continue to the next iteration.
			return true
		}

		currentWaterMarks[partition] = offset
		return true
	})

	return currentWaterMarks
}

// Close closes the consumer.
func (s *SingleTopicStatelessConsumer) Close() error {
	if !s.subscribed {
		return nil
	}

	err := s.manualKafkaSource.Close()
	if err != nil {
		return vexi_errors.NewWrappedError(err, "error closing the consumer")
	}

	return nil
}

// newManualKafkaSource creates a hydro publisher given the current system configuration.
func newManualKafkaSource(ctx context.Context, cfg ConsumerConfig, t internal.Telemetry) (*hydropkg.ManualKafkaSource, error) {
	// Set the kafka logger to surface any problems from sarama, the underlying kafka client library.
	logger := NewLogger(ctx, t)
	brokers := strings.Split(cfg.HydroBrokers, ",")

	t.LogInfo(ctx, "Creating a new manual kafka source")

	clientID, err := os.Hostname()
	if err != nil {
		return nil, err
	}

	var kafkaConfig *hydropkg.KafkaConfig

	kafkaOptions := append(cfg.KafkaOptions, //nolint:gocritic // False positive, assigning append result to a new var intentionally.
		hydropkg.WithClientID(clientID),
		hydropkg.WithKafkaLogger(logger),
	)

	if !cfg.IsDevelopment {
		if cfg.HydroRootCA == "" {
			kafkaOptions = append(kafkaOptions, hydropkg.WithSSL()) // Use System Root Certification Configuration to support automatic rotation of certificates.
		} else {
			kafkaOptions = append(kafkaOptions, hydropkg.WithRootCA(cfg.HydroRootCA))
		}
	}

	kafkaConfig, err = hydropkg.NewKafkaConfig(brokers, kafkaOptions...)
	if err != nil {
		return nil, err
	}

	return hydropkg.NewManualKafkaSource(*kafkaConfig)
}
