package kafka

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"

	"github.com/github/github-telemetry-go/log"
	"github.com/segmentio/kafka-go"
)

type (
	// Producer is an interface that defines the methods for Kafka producers.
	Producer interface {
		Produce(ctx context.Context, m []byte) error
	}

	// ProducerImpl is a Kafka producer that uses the `segmentio/kafka-go`
	ProducerImpl struct {
		kafkaWriter *kafka.Writer
		logger      log.Logger
	}

	// CustomBalancer is a simple balancer that randomly selects a partition for now. This is here
	// because we might want to use a different balancer in the future to enforce
	// local ordering.
	CustomBalancer struct{}
)

// NewKafkaGoProducer creates a new Producer
func NewKafkaGoProducer(addr, topic, caCert string, logger log.Logger) (*ProducerImpl, error) {
	var tlsCfg *tls.Config
	if caCert != "" {
		ca, err := os.ReadFile(filepath.Clean(caCert))
		if err != nil {
			return nil, fmt.Errorf("error getting CACert: %w", err)
		}
		pool := x509.NewCertPool()
		pool.AppendCertsFromPEM(ca)
		tlsCfg = &tls.Config{
			MinVersion: tls.VersionTLS12,
			RootCAs:    pool,
		}
	}
	w := kafka.Writer{
		Addr:  kafka.TCP(addr),
		Topic: topic,
		Transport: &kafka.Transport{
			TLS: tlsCfg,
		},
		Balancer:               &CustomBalancer{},
		AllowAutoTopicCreation: true,
		Logger:                 log.Standardize(log.NewNullLogger(), log.InfoLevel),
	}
	return &ProducerImpl{
		kafkaWriter: &w,
		logger:      logger,
	}, nil
}

// Produce sends a message to Kafka
func (p *ProducerImpl) Produce(ctx context.Context, m []byte) error {
	// TODO: retry errors, especially legit Kafka errors.
	if err := p.kafkaWriter.WriteMessages(ctx, kafka.Message{Value: m}); err != nil {
		return fmt.Errorf("error writing message: %w", err)
	}
	return nil
}

// Balance selects a partition randomly
func (m CustomBalancer) Balance(_ kafka.Message, partitions ...int) (partition int) {
	return partitions[rand.Intn(len(partitions))] //nolint:gosec // no need to use crypto/rand
}
