package hydro

import (
	"context"
	"log"
	"os"

	"github.com/Shopify/sarama"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/interfaces"
	telemetryLogger "github.com/github/github-telemetry-go/log"
	"github.com/github/hydro-client-go/v5/pkg/hydro"
	"github.com/pkg/errors"
)

func NewHydroPublisher(ctx context.Context, cfg *config.Config, logger telemetryLogger.Logger) (interfaces.HydroPublisher, error) {
	// Set the kafka logger to surface any problems from sarama, the underlying kafka client library.
	hydroLogger := log.New(os.Stdout, "", log.Ldate|log.Ltime|log.Lshortfile)
	hydro.SetKafkaLogger(hydroLogger) // this doesn't seem to work with "github.com/github/github-telemetry-go/log"

	brokers := cfg.ParsedHydroKafkaBrokers()

	var sink hydro.Sink
	var err error
	if cfg.HydroKafkaCAPath != "" {
		logger.Info("found HydroKafkaCAPath, using kafka sink")
		kafkaOptions := []hydro.KafkaConfigOption{
			hydro.WithClientID("billing-platform"),
			hydro.WithRootCA(cfg.HydroKafkaCAPath),
		}
		kc, err := hydro.NewKafkaConfig(brokers, kafkaOptions...)
		if err != nil {
			return nil, errors.Wrap(err, "building kafka config")
		}
		sink, err = hydro.NewKafkaSink(*kc)
		if err != nil {
			return nil, errors.Wrap(err, "building kafka sink")
		}
	} else {
		logger.Info("missing HydroKafkaCAPath, using memory sink")
		events := make(chan hydro.Message, 100)
		sink, err = hydro.NewMemorySink(events)
		if err != nil {
			return nil, errors.Wrap(err, "building memory sink")
		}
	}

	publisher, err := hydro.NewPublisher(sink)
	if err != nil {
		return nil, errors.Wrap(err, "building publisher")
	}

	return publisher, nil
}

func NewKafkaConfig(ctx context.Context, appConfig *config.Config) (*hydro.KafkaConfig, error) {
	brokers := appConfig.ParsedHydroKafkaBrokers()

	clientID, err := os.Hostname()
	if err != nil {
		return nil, errors.Wrap(err, "building hostname")
	}

	kafkaOpts := []hydro.KafkaConfigOption{
		hydro.WithClientID(clientID),
	}

	if appConfig.IsLocal() || appConfig.IsRemoteNonProd() {
		kafkaOpts = append(kafkaOpts, hydro.WithKafkaVersion(sarama.V1_1_1_0.String()))
	}

	if !appConfig.IsLocal() && !appConfig.IsRemoteNonProd() {
		kafkaOpts = append(kafkaOpts, hydro.WithRootCA(appConfig.HydroKafkaCAPath))
		kafkaOpts = append(kafkaOpts, hydro.WithSaramaConfig(func(c *sarama.Config) {
			c.Consumer.Offsets.Initial = sarama.OffsetNewest
		}))
	}

	cfg, err := hydro.NewKafkaConfig(brokers, kafkaOpts...)
	if err != nil {
		return nil, errors.Wrap(err, "building kafka config")
	}

	return cfg, nil
}
