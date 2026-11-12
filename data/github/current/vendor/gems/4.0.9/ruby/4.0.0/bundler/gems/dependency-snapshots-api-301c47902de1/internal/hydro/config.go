package hydro

import (
	"crypto/tls"
	"crypto/x509"
	"os"
	"strings"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/IBM/sarama"
	"github.com/pkg/errors"
)

// NewKafkaPublisherConfig initializes a new config object for Kafka publisher
func NewKafkaPublisherConfig(cfg *config.Config, logger log.Logger, statter stats.Client) (*hydro.KafkaConfig, error) {
	brokers, enableTLS, err := cfg.ParseHydroKafkaBrokers()
	if err != nil {
		return nil, errors.Wrap(err, "failed parsing hydro brokers")
	}

	kafkaOpts, err := newKafkaOpts(cfg, logger, statter, enableTLS, false)
	if err != nil {
		return nil, errors.Wrap(err, "failed creating kafka options")
	}

	kafkaConfig, err := hydro.NewKafkaConfig(brokers, kafkaOpts...)
	if err != nil {
		return nil, err
	}

	return kafkaConfig, err
}

// NewKafkaConsumerConfig initializes a new config object for Kafka consumer
func NewKafkaConsumerConfig(cfg *config.Config, logger log.Logger, statter stats.Client) (*hydro.KafkaConfig, error) {
	brokers, enableTLS, err := cfg.ParseHydroKafkaBrokers()
	if err != nil {
		return nil, errors.Wrap(err, "failed parsing hydro brokers")
	}

	kafkaOpts, err := newKafkaOpts(cfg, logger, statter, enableTLS, true)
	if err != nil {
		return nil, errors.Wrap(err, "failed creating kafka options")
	}

	kafkaConfig, err := hydro.NewKafkaConfig(brokers, kafkaOpts...)
	if err != nil {
		return nil, err
	}

	return kafkaConfig, err
}

// newKafkaOpts creates common Kafka options for publisher and consumer
func newKafkaOpts(cfg *config.Config, logger log.Logger, statter stats.Client, enableTLS, forConsumer bool) ([]hydro.KafkaConfigOption, error) {
	if len(cfg.KafkaClientID) == 0 {
		return nil, errors.New("KafkaClientID must be non-empty")
	}
	kafkaOpts := []hydro.KafkaConfigOption{
		hydro.WithClientID(cfg.KafkaClientID),
	}

	hydroLogger := NewHydroLogger(logger)
	kafkaOpts = append(kafkaOpts, hydro.WithKafkaLogger(hydroLogger))

	if cfg.IsDevelopment() || cfg.KafkaStatsEnabled {
		kafkaOpts = append(kafkaOpts, hydro.WithKafkaStats(statter))
	}

	if cfg.IsDevelopment() || cfg.IsGHES() {
		kafkaOpts = append(kafkaOpts, hydro.WithKafkaVersion(sarama.V1_1_1_0.String()))
	}

	if enableTLS {
		if len(cfg.KafkaSSLCertLocation) == 0 {
			return nil, errors.New("KAFKA_SSL_CERTIFICATE_LOCATION must be assigned if connecting to Kafka brokers on port 9093")
		}

		tlsConfig, err := loadKafkaTLSConfig(cfg.KafkaSSLCertLocation)
		if err != nil {
			return nil, err
		}
		kafkaOpts = append(kafkaOpts, hydro.WithTLS(tlsConfig))
	}

	// set consumer options if a consumer group name is configured
	if forConsumer {
		if len(cfg.KafkaConsumerGroup) == 0 {
			return nil, errors.New("KafkaConsumerGroup must be non-empty for consumers")
		}

		// if this is the first time a consumer group name has been registered
		// with the Hydro (Kafka) brokers, you have the option to choose whether
		// the consumer will start with the oldest or newest offsets on the topics
		// you'll be consuming. This is useful in combination with incrementing
		// the version tag on a consumer group name to rewind the topic for a
		// backfill, or fast-fwd during a topic cutover
		switch strings.ToLower(cfg.KafkaInitialOffsets) {
		case "", "newest":
			// this should be the default as it avoids the risk
			// of accidentally changing a group name or deploying
			// a new consumer pool and rewinding the whole topic
			kafkaOpts = append(kafkaOpts, hydro.WithSaramaConfig(
				func(sarmaCfg *sarama.Config) {
					sarmaCfg.Consumer.Offsets.Initial = sarama.OffsetNewest
				}))

		case "oldest":
			// To backfill a Kafka topic:
			// 1. Decide the scope and target consumer for your backfill
			//    - Typical case: backfill *a single consumer and env* by overriding config/kustomize/overlays/<target> only!
			//    - Unusual case: backfill *all deploy envs at once* update config/kustomize/base/deployments
			//
			// 2. Update the env vars to rename the consumer group and set the rewind/fast-fwd configs:
			//    - KAFKA_CONSUMER_GROUP: override by incrementing the group name version suffix
			//    - KAFKA_INITIAL_OFFSETS=oldest
			//
			// 3. Regenerate k8s from Kustomize overrides, PR the changeset, and merge to begin the backfill
			//
			// 4. After the backfill:
			//    - Revert or remove KAFKA_INITIAL_OFFSETS overrides from Kustomize
			//    - Leave KAFKA_CONSUMER_GROUP_NAME overrides on the new value you chose in Step 2
			kafkaOpts = append(kafkaOpts, hydro.WithSaramaConfig(
				func(sarmaCfg *sarama.Config) {
					sarmaCfg.Consumer.Offsets.Initial = sarama.OffsetOldest
				}))

		default:
			return nil, errors.Errorf(
				"invalid Kafka initial offsets config value: consumer_group=%s, initial_offsets=%s",
				cfg.KafkaConsumerGroup, cfg.KafkaInitialOffsets)
		}
	}

	return kafkaOpts, nil
}

// loadKafkaTLSConfig loads the TLS configuration for Kafka connections
// using the provided root CA certificate file path.
func loadKafkaTLSConfig(rootCACertPath string) (*tls.Config, error) {
	rootCA, err := os.ReadFile(rootCACertPath)
	if err != nil {
		return nil, errors.Wrap(err, "reading root CA file for Kafka")
	}

	certPool := x509.NewCertPool()
	if ok := certPool.AppendCertsFromPEM(rootCA); !ok {
		return nil, errors.New("adding root CA to cert pool for Kafka")
	}

	return &tls.Config{
		RootCAs:    certPool,
		MinVersion: tls.VersionTLS12,
	}, nil
}
