// Package hydro provides hydro consumer functionality for the Licensify service.
package hydro

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-ctxutil"
	stats "github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"go.opentelemetry.io/otel/trace"
)

const consumerContextCancelDelay = 5 * time.Second

// Consumer provides the Hydro consumer functionality.
type Consumer struct {
	Topics       []string
	Config       *config.Config
	Logger       log.Logger
	Statter      stats.Client
	Tracer       trace.Tracer
	EventHandler *eventhandlers.EventHandler
}

// Run starts the Hydro consumer.
func (c *Consumer) Run(ctx context.Context) error {
	kc, err := NewKafkaConfig(ctx, c.Config)
	if err != nil {
		return fmt.Errorf("creating Kafka config: %w", err)
	}

	src, err := hydro.NewKafkaSource(*kc, c.Config.HydroConsumerGroupID, c.Topics)
	if err != nil {
		return fmt.Errorf("creating Kafka source: %w", err)
	}

	defer func() {
		if err := src.Close(); err != nil {
			c.Logger.WithError(err).Error("failed to close Kafka source")
		}
	}()

	if err := c.consume(ctx, src); err != nil {
		return fmt.Errorf("error while consuming kafka source: %w", err)
	}

	c.Logger.Info("shutting down kafka consumer")
	return nil
}

func (c *Consumer) consume(ctx context.Context, src hydro.Source) error {
	c.Logger.Info("consumer starting")

	if err := src.Consume(ctx, func(innerCtx context.Context, msg hydro.Message) error {
		c.Statter.Counter("hydro_consumer.process_message.start", stats.Tags{"topic": msg.Topic}, 1)

		// passing a new "delayed" context to ProcessJob so that we can wait for the message to be processed.
		// implementation at this scope is necessary to ensure we have control of the loop reading
		// messages from the source, and can delay the context cancellation.
		delayedCtx, cancel := ctxutil.DelayedCancel(innerCtx, consumerContextCancelDelay)
		defer cancel()

		err := c.processMessage(delayedCtx, &msg)
		if err != nil {
			c.Logger.WithError(err).Error("hydro.consume.failed_to_process_message")
		}
		c.Statter.Counter("hydro_consumer.process_message.end", stats.Tags{"topic": msg.Topic}, 1)

		// returning nil will tell kafka that the message the message was processed successfully (commit the offset)
		// returning an error will tell kafka not to commit the message offset as having been processed
		return err
	}); err != nil {
		// shutdown gracefully if the context was canceled
		if errors.Is(err, context.Canceled) {
			return nil
		}

		return fmt.Errorf("error consuming kafka source: %w", err)
	}

	return nil
}

func (c *Consumer) processMessage(ctx context.Context, msg *hydro.Message) (err error) {
	timeNow := time.Now()
	ctx, sp := c.Tracer.Start(ctx, fmt.Sprintf("consumer:%s", msg.Topic))
	defer func() {
		sp.End()
		c.Statter.Timing("hydro_consumer.process_message", stats.Tags{
			"topic":   msg.Topic,
			"success": strconv.FormatBool(err == nil),
		}, time.Since(timeNow))
	}()
	logger := c.Logger.WithContext(ctx).WithFields(kvp.String("gh.hydro.msg.topic", msg.Topic))

	logger.Info("begin processing message")

	return c.EventHandler.HandleRaw(ctx, logger, msg.Value, msg.Topic)
}

// CreateReadinessProbeFile creates a file in /tmp to be used as a readiness probe.
func CreateReadinessProbeFile() error {
	_, err := os.Create("/tmp/consumer_healthy") //nolint:gosec // not using os.CreateTemp because it adds a random string to the filename and the readiness probe won't be able to find it
	if err != nil {
		return fmt.Errorf("creating consumer_healthy file for readiness probe: %w", err)
	}

	return nil
}
