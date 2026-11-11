package hydro

import (
	"fmt"
	"os"

	"github.com/IBM/sarama"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-server/runtime/telemetry/reporter"
	"github.com/github/go-stats"
	hydro_pkg "github.com/github/hydro-client-go/v7/pkg/hydro"
)

// newConfig returns a new Hydro configuration.
func newConfig(clientID, kafkaVersion string, brokers []string, logger log.Logger, reporter reporter.ExceptionReporter, stats stats.Client, isDevelopment bool) (*hydro_pkg.KafkaConfig, error) {
	// Enable package level logging on the underlying Kafka client to surface
	// any connection level problems.
	hydroLogger := NewHydroLogger(logger)
	hydro_pkg.SetKafkaLogger(hydroLogger)

	hydroOpts := []hydro_pkg.KafkaConfigOption{
		hydro_pkg.WithClientID(clientID),
		hydro_pkg.WithKafkaLogger(hydroLogger),
		hydro_pkg.WithKafkaStats(stats),
		hydro_pkg.WithKafkaVersion(kafkaVersion),
		hydro_pkg.WithKafkaErrorReporter(reporter),
		hydro_pkg.WithSaramaConfig(func(cfg *sarama.Config) {
			cfg.Consumer.Group.Rebalance.GroupStrategies = []sarama.BalanceStrategy{sarama.NewBalanceStrategyRoundRobin()}
		}),
	}

	if !isDevelopment {
		hydroOpts = append(hydroOpts, hydro_pkg.WithSSL())
	}
	return hydro_pkg.NewKafkaConfig(brokers, hydroOpts...)
}

// NewPublisher returns a new Hydro publisher.
func NewPublisher(isDevelopment bool, clientID, kafkaVersion string, brokers []string, logger log.Logger, reporter reporter.ExceptionReporter, stats stats.Client) (*hydro_pkg.Publisher, error) {
	l := logger.Named("hydro-publisher")
	hl := NewHydroLogger(l)
	if isDevelopment {
		// In development, we log to stdout instead of sending to Kafka.
		hydroSink := hydro_pkg.NewLogSink(hl)
		return hydro_pkg.NewPublisher(hydroSink, hydro_pkg.WithEncoder(hydro_pkg.NewJSONEncoder()))
	}

	hydroCfg, err := newConfig(clientID, kafkaVersion, brokers, l, reporter, stats, isDevelopment)
	if err != nil {
		return nil, fmt.Errorf("creating hydro config: %w", err)
	}

	// Set the kafka logger to surface any problems from sarama, the underlying kafka client library.
	hydro_pkg.SetKafkaLogger(hl)

	hydroSink, err := hydro_pkg.NewKafkaSink(*hydroCfg)
	if err != nil {
		return nil, fmt.Errorf("creating hydro sink: %w", err)
	}

	publisher, err := hydro_pkg.NewPublisher(hydroSink, hydro_pkg.WithTopicFormat(hydro_pkg.TopicFormatV2), hydro_pkg.WithPublisherStats(stats))
	if err != nil {
		return nil, fmt.Errorf("creating hydro publisher: %w", err)
	}

	return publisher, nil
}

func NewConsumer(isDevelopment bool, clientID, kafkaVersion, hydroGroupName string, brokers, topics []string, logger log.Logger, reporter reporter.ExceptionReporter, stats stats.Client) (*hydro_pkg.KafkaSource, error) {
	hydroCfg, err := newConfig(clientID, kafkaVersion, brokers, logger.Named("hydro-consumer"), reporter, stats, isDevelopment)
	if err != nil {
		return nil, fmt.Errorf("creating hydro config: %w", err)
	}
	return hydro_pkg.NewKafkaSource(*hydroCfg, hydroGroupName, topics)
}

// CreateReadinessProbeFile creates a file at /tmp/consumer_healthy to be used as a
// readiness probe for the consumer. This is created right before we start consuming
// messages.
func CreateReadinessProbeFile() error {
	_, err := os.Create("/tmp/consumer_healthy")
	if err != nil {
		return fmt.Errorf("error creating consumer_healthy file for readiness probe: %w", err)
	}

	return nil
}
