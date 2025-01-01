// Package kafka contains a kafka consumer and kafka producer using the segmentio/kafka-go library
package kafka

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/segmentio/kafka-go"
)

type (
	// Consumer is an interface that defines the methods for Kafka consumers.
	Consumer interface {
		Consume(ctx context.Context, f func(ctx context.Context, msg []byte) error) error
	}

	// ConsumerImpl is a Kafka consumer that uses the segmentio/kafka-go library
	ConsumerImpl struct {
		addr        string
		topic       string
		groupID     string
		maxInFlight int
		caCert      string
		logger      log.Logger
	}
)

const (
	// EventTopic is the topic for events
	EventTopic = "events"

	// FailedEventTopic is the topic for failed events
	FailedEventTopic = "failed-events"

	// ResourceTopic is the topic for resources
	ResourceTopic = "resources"

	// FailedTopic is the topic for failed resources
	FailedTopic = "failed-resources"
)

// NewKafkaGoConsumer creates a new ConsumerImpl
func NewKafkaGoConsumer(addr, topic, groupID, caCert string, maxInFlight int, logger log.Logger) *ConsumerImpl {
	return &ConsumerImpl{
		addr:        addr,
		topic:       topic,
		groupID:     groupID,
		maxInFlight: maxInFlight,
		caCert:      caCert,
		logger:      logger,
	}
}

// Consume reads messages from a Kafka topic and calls the provided function with the message values
func (c *ConsumerImpl) Consume(ctx context.Context, f func(context.Context, []byte) error) error {
	cfg, err := c.buildKafkaConfig()
	if err != nil {
		return fmt.Errorf("error building kafka config: %w", err)
	}

	r := kafka.NewReader(*cfg)

	// channel to signal there was an error fetching messages from Kafka
	fetchErrC := make(chan error, 1)
	// channel to signal there was an error processing messages
	processErrC := make(chan error, c.maxInFlight)
	// channel to write messages to be processed
	msgC := make(chan *kafka.Message, c.maxInFlight*2+1)
	// stopC is a channel that is used to signal the processing goroutines to stop
	// because there's an error fetching or processing messages.
	stopC := make(chan struct{})

	offsetCommiter := newOffsetCommiter(c.topic, c.logger)

	// start a goroutine to read messages from Kafka and write them to the msgC channel
	go func() {
		defer close(msgC)
		for ctx.Err() == nil {
			m, err := r.FetchMessage(ctx)
			if err != nil {
				fetchErrC <- fmt.Errorf("error fetching message: %w", err)
				return
			}
			c.logger.Info("message read", kvp.Int("partition", m.Partition), kvp.Int64("offset", m.Offset))
			offsetCommiter.seen(&m)
			select {
			case msgC <- &m:
			case <-ctx.Done():
				return
			}
		}
	}()

	// start goroutines to process messages
	// read messages from the msgC channel and process them
	var wg sync.WaitGroup
	for range c.maxInFlight {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				select {
				case m, ok := <-msgC:
					if !ok {
						return
					}
					if err := f(ctx, m.Value); err != nil {
						processErrC <- fmt.Errorf("error processing message: %w", err)
						return
					}
					if err := offsetCommiter.processed(ctx, r.CommitMessages, m); err != nil {
						processErrC <- fmt.Errorf("error committing message: %w", err)
						return
					}
				case <-stopC:
					return
				}
			}
		}()
	}

	// wait for the context to be canceled or for an error to be returned from the fetch or process goroutines
	select {
	case <-ctx.Done():
	case err = <-fetchErrC:
	case err = <-processErrC:
		// drain the processErrC channel
		errs := errors.Join(err)
		drained := false
		for !drained {
			select {
			case err = <-processErrC:
				errs = errors.Join(errs, err)
			default:
				drained = true
			}
		}
	}

	// close the stopC channel to signal the processing goroutines to stop
	c.logger.Info("waiting for consume goroutines to exit")
	close(stopC)
	wg.Wait()
	c.logger.Info("consume goroutines have exited")

	return err
}

// buildSaramaConfig builds a sarama config
func (c *ConsumerImpl) buildKafkaConfig() (*kafka.ReaderConfig, error) {
	var tlsCfg *tls.Config

	if c.caCert != "" {
		ca, err := os.ReadFile(filepath.Clean(c.caCert))
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

	// if CACert is not specified return the default dialer
	d := &kafka.Dialer{
		Timeout:   10 * time.Second,
		DualStack: true,
		TLS:       tlsCfg,
	}

	return &kafka.ReaderConfig{
		Dialer:  d,
		Brokers: []string{c.addr},
		GroupID: c.groupID,
		Topic:   c.topic,
		Logger:  log.Standardize(log.NewNullLogger(), log.InfoLevel),
	}, nil
}
