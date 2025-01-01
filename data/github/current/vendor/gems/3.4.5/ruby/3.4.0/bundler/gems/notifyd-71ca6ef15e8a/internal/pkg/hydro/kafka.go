package hydro

import (
	"os"
	"strings"

	"github.com/IBM/sarama"
	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/github/notifyd/internal/pkg/errors"
)

// Config represents the configuration for the Kafka publisher.
type Config struct {
	// KafkaAdminDev defines the URL in which the Kafka admin lives. This is used in development/test
	// in order to reset the queues.
	KafkaAdminDev string `config:"http://localhost:9094,env=KAFKA_ADMIN_DEV"`

	// KafkaBrokers is a comma-separated list of Kafka brokers.
	KafkaBrokers string `config:"localhost:9092,env=KAFKA_BROKERS"`

	// KafkaSetVersion allows you to set an explicit version for Kafka config
	// dev and test environments needs this to be set.
	KafkaSetVersion string `config:",env=KAFKA_SET_VERSION"`
}

// Brokers returns the list of Kafka brokers.
func (c *Config) Brokers() (brokers []string) {
	split := strings.Split(c.KafkaBrokers, ",")
	for _, broker := range split {
		brokers = append(brokers, strings.TrimSpace(broker))
	}
	return brokers
}

// NewKafkaPublisher returns a new hydro.Publisher.
func NewKafkaPublisher(cfg Config) (*hydro.Publisher, error) {
	kafkaConfig, err := buildKafkaConfig(cfg)
	if err != nil {
		return nil, errors.Wrap(err, "building kafka config")
	}

	// Build a KafkaSink for the publisher to write to
	sink, err := hydro.NewKafkaSink(*kafkaConfig)
	if err != nil {
		return nil, errors.Wrap(err, "starting kafka sink")
	}

	publisher, err := hydro.NewPublisher(sink, hydro.WithTopicFormat(hydro.TopicFormatV2))
	if err != nil {
		return nil, errors.Wrap(err, "starting kafka sink")
	}

	return publisher, nil
}

// GroupID represents the ID used by our consumer groups. These are fixed and should never change as
// the kafka offest is associated with them.
//
// Changing them would reprocess all the messages currently in the queue, which would be a disaster
// for many reasons, but among other things because it would redeliver all the notifications.
type GroupID string

// Consumer group IDs.
var (
	NotifyGroupID            = GroupID("notify-consumer")
	DeliverMobilePushGroupID = GroupID("mobile-consumer")
	DeliverEmailGroupID      = GroupID("email-consumer")
)

func buildKafkaConfig(cfg Config) (*hydro.KafkaConfig, error) {
	// Construct a client ID from the hostname.
	clientID, err := os.Hostname()
	if err != nil {
		return nil, errors.Wrap(err, "building hostname")
	}

	opts := []hydro.KafkaConfigOption{ // Set the client ID
		hydro.WithClientID(clientID),

		// Ensure we only process new events not old ones
		hydro.WithSaramaConfig(func(scfg *sarama.Config) {
			scfg.Consumer.Offsets.Initial = sarama.OffsetNewest
		}),

		hydro.WithSSL(),
	}

	// depending on if the host uses kafka-lite or kafka, this needs to be set
	// needed for dev mode to work on dotcom codespaces machine and for integration tests
	if cfg.KafkaSetVersion != "" {
		opts = append(opts, hydro.WithKafkaVersion(cfg.KafkaSetVersion))
	}

	return hydro.NewKafkaConfig(cfg.Brokers(), opts...)
}
