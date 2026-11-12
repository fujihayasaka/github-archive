package hydro

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydroclient "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"
)

// EnvelopeHandler processes the Envelope portion of a hydro message
type EnvelopeHandler interface {
	HandleEnvelope(ctx context.Context, msg *hydroclient.Envelope) error
}

// Consumer implements a hydro consumer that reads from a specific topic
// and delegates to an EnvelopeHandler to handle each message.
type Consumer struct {
	envelopeHandlers map[string]EnvelopeHandler
	kafkaSource      *hydro.KafkaSource
	logger           log.Logger
	statter          stats.Client
}

// NewConsumer creates a new Hydro consumer.
// It refuses to create a consumer in GHES (enterprise) environments.
func NewConsumer(cfg *config.Config, logger log.Logger, statter stats.Client, handlers map[string]EnvelopeHandler) (*Consumer, error) {
	if cfg.Enterprise {
		return nil, fmt.Errorf("hydro consumer is not supported in GHES")
	}

	kafkaCfg, err := NewKafkaConsumerConfig(cfg, logger, statter)
	if err != nil {
		return nil, err
	}

	topics := make([]string, 0, len(handlers))
	for handler := range handlers {
		topics = append(topics, handler)
	}
	logger.Info(
		"creating kafka consumer...",
		kvp.Int("hydro.consumer.topic.count", len(topics)),
		kvp.Strings("hydro.consumer.topic.names", topics),
		kvp.String("hydro.consumer.group", cfg.KafkaConsumerGroup))
	kafkaSrc, err := hydro.NewKafkaSource(*kafkaCfg, cfg.KafkaConsumerGroup, topics)
	if err != nil {
		return nil, err
	}

	out := &Consumer{
		envelopeHandlers: handlers,
		kafkaSource:      kafkaSrc,
		logger:           logger,
		statter:          statter,
	}

	return out, nil
}

// Run starts the consumer to begin processing messages
func (c *Consumer) Run(ctx context.Context) error {
	defer func() {
		if err := c.kafkaSource.Close(); err != nil {
			c.logger.WithError(err).Error("error closing hydro kafka source")
		}
	}()

	c.logger.Info("starting kafka source...")
	if err := c.consume(ctx); err != nil {
		return errors.Wrap(err, "error when consuming hydro messages")
	}

	c.logger.Info("shutting down hydro consumer")
	return nil
}

// consume starts consuming messages from the Kafka source
func (c *Consumer) consume(ctx context.Context) error {
	return c.kafkaSource.Consume(ctx, func(ctx context.Context, m hydro.Message) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}

		ctx, coords := NewKafkaEventCoords(ctx, &m)

		ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "HandleMessage", m.Topic, coords.Fields()...)
		defer ender()

		execStartTime := time.Now()
		err := c.handleMessage(ctx, &m)
		execDuration := time.Since(execStartTime)

		c.statter.DistributionMs("hydro.consumer.elapsed_ms", stats.Tags{
			"topic":                m.Topic,
			"partition":            strconv.FormatInt(int64(m.Partition), 10),
			"completed_with_error": strconv.FormatBool(err != nil),
		}, execDuration)

		if err != nil {
			c.logger.WithError(err).Error("Hydro consumer execution error",
				append(coords.Fields(), semconv.HydroExecutionTimeMs(execDuration.Milliseconds()))...)
		} else {
			c.logger.Info("Hydro consumer execution success",
				append(coords.Fields(), semconv.HydroExecutionTimeMs(execDuration.Milliseconds()))...)
		}

		return err
	})
}

// handleMessage processes a single hydro message
func (c *Consumer) handleMessage(ctx context.Context, hm *hydro.Message) (err error) {
	handler := c.envelopeHandlers[hm.Topic]
	if handler == nil {
		return errors.New("no handler found for topic")
	}

	// Unmarshal the envelope from the hydro message
	var envelope hydroclient.Envelope
	if err := proto.Unmarshal(hm.Value, &envelope); err != nil {
		return errors.Wrap(err, "unmarshalling envelope from kafka message")
	}

	// Update context and event coordinates with event ID from envelope
	ctx, coords := KafkaEventCoordsWithEventID(ctx, &envelope)

	tags := stats.Tags{
		"topic":     hm.Topic,
		"partition": strconv.FormatInt(int64(hm.Partition), 10),
	}

	// record latency from envelope timestamp to processing time
	c.statter.DistributionMs("hydro.consumer.latency", tags, time.Since(envelope.Timestamp.AsTime()))

	defer func() {
		if recovered := recover(); recovered != nil {
			err = errFromPanic(recovered)
			c.statter.Counter("hydro.consumer.panic", tags, 1)
			c.logger.Error(
				"PANIC in Hydro Consumer",
				append(coords.Fields(), kvp.String("hydro.consumer.panic.msg", fmt.Sprintf("%v", recovered)))...,
			)
		}
	}()

	return handler.HandleEnvelope(ctx, &envelope)
}

// errFromPanic converts a recovered panic value into an error
func errFromPanic(p interface{}) error {
	if err, ok := p.(error); ok {
		return errors.Wrap(err, "hydro consumer panic handling message")
	}
	return fmt.Errorf("hydro consumer panic handling message: %v", p)
}
