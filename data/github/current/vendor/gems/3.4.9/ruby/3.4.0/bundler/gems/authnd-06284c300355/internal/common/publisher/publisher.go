package publisher

import (
	"context"
	"encoding/json"
	"os"

	"github.com/github/authnd/internal/common/config"
	"github.com/github/authnd/internal/common/diagnostics"
	"google.golang.org/protobuf/protoadapt"
	"google.golang.org/protobuf/runtime/protoiface"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/pkg/errors"
)

const KafkaDevelopmentFile = "tmp/hydro-messages.txt"

type Publisher interface {
	PublishMessage(ctx context.Context, hydroTopic string, msg protoiface.MessageV1) error
	Close() error
}

type hydroPublisher struct {
	publisher *hydro.Publisher
}

type WithSink func(hydro.KafkaConfig) (hydro.Sink, error)

// NewPublisher creates a new hydro publisher
// Used to write protobufs to a hydro topic for replication messages that failed to be processed
// withSink is an optional func to specify a custom sink. If it's nil, we will use a default.
// Always call .Close when the publisher is no longer needed
func NewPublisher(ctx context.Context, commonConfig *config.CommonConfig, brokers string, format hydro.TopicFormat, withSink WithSink) (Publisher, error) {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	clientID, err := os.Hostname()
	if err != nil {
		return nil, errors.WithStack(err)
	}

	hydro.SetKafkaLogger(diagnostics.TrimmingLogger(
		logger.WithLevel(log.DebugLevel).WithFields(kvp.String("component", "kafka"))))
	kafka, err := commonConfig.NewHydroKafkaConfig(brokers, hydro.WithClientID(clientID), hydro.WithKafkaStats(statter))
	if err != nil {
		return nil, err
	}

	if withSink == nil {
		return nil, errors.New("provided WithSink function is nil")
	}
	sink, err := withSink(*kafka)
	if err != nil {
		return nil, err
	}

	publisher, err := hydro.NewPublisher(sink, hydro.WithTopicFormat(format), hydro.WithSiteName(commonConfig.HydroSite()))
	if err != nil {
		return nil, errors.WithStack(err)
	}

	// the topic name is constructed using the site, namespace, and HEAVEN_DEPLOYED_ENV (topicDeployment)
	// for example, the topic name for development would look like: cp1-iad.ingest.authnd.replicator.development.v0.DeadLetter
	return &hydroPublisher{
		publisher: publisher,
	}, nil
}

func (p *hydroPublisher) PublishMessage(ctx context.Context, hydroTopic string, msg protoiface.MessageV1) error {
	diagnostics.Logger(ctx).Debug("publishing message", kvp.String("topic", hydroTopic), kvp.Any("msg", msg))
	v2Msg := protoadapt.MessageV2Of(msg)
	err := p.publisher.Publish(v2Msg, hydro.WithTopic(hydroTopic))
	if err != nil {
		return errors.WithStack(err)
	}
	return nil
}

func (np *NullPublisher) PublishMessage(ctx context.Context, hydroTopic string, msg protoiface.MessageV1) error {
	return errors.New("Cannot publish message with null publisher")
}

// WithDefaultSinkFn constructs a sink backed by a remove Kafka server.
// A sink is responsible for writing events to a destination.
// By default, the hydro lib sets retry attempts to 30 - We are using 30 explicitly so it's clear in our code
// By default, the hydro lib uses "AcksOne" which requires waiting only an acknowledgement from the leader that a
// message was written to its local log. We are using "AcksAll" which requires waiting on acknowledgements from the leader and all
// in-sync replicas that a message was received. This provides the
// strongest durability guaranteeing and since we _expect_ little traffic publishing to the dead letter topic, it doesn't hurt performance to use AcksAll
func WithDefaultSinkFn(kafka hydro.KafkaConfig) (hydro.Sink, error) {
	sink, err := hydro.NewKafkaSink(kafka, hydro.WithSendAttempts(30), hydro.WithRequiredAcks(hydro.AcksAll))
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return sink, nil
}

func (p *hydroPublisher) Close() error {
	return p.publisher.Close()
}

func (np *NullPublisher) Close() error {
	return nil
}

// WithDevelopmentSinkFn constructs a file-backed sink to be used in development environments where
// Kafka/Hydro are not present.
func WithDevelopmentSinkFn(_ hydro.KafkaConfig) (hydro.Sink, error) {
	f, err := os.Create(KafkaDevelopmentFile)
	if err != nil {
		return nil, err
	}
	return &fileSink{
		file: f,
	}, nil
}

type fileSink struct {
	file *os.File
}

func (s *fileSink) Write(message hydro.Message) error {
	data, err := json.Marshal(message)
	if err != nil {
		return err
	}
	data = append(data, []byte("\n")...)
	_, err = s.file.Write(data)
	return err
}

func (ms *fileSink) WriteBatch(msgs []hydro.Message) (err error) {
	for _, msg := range msgs {
		if err := ms.Write(msg); err != nil {
			return err
		}
	}

	return nil
}

func (s *fileSink) Flush() error {
	// nothing is buffered
	return nil
}

func (s *fileSink) Close() error {
	return s.file.Close()
}
