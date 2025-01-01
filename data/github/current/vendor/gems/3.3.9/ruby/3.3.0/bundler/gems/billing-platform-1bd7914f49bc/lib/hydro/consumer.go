package hydro

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/hydro/handlers"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	schemas "github.com/github/hydro-client-go/v5/generated/hydro/schemas/hydro/v1"
	"github.com/github/hydro-client-go/v5/pkg/hydro"
	"github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/trace"
)

const (
	RepositoryVisibilityChangedTypeURL string = "hydro-schemas.github.net/hydro.schemas.github.repositories.v1.VisibilityChanged"
	RepositoryVisibilityChangedTopic   string = "github.repositories.v1.VisibilityChanged"
)

type EnvelopeHandler interface {
	HandleEnvelope(context.Context, log.Logger, *schemas.Envelope) error
}

type Consumer struct {
	EnvelopeHandlers map[string]EnvelopeHandler
	Config           *config.Config
	Topics           []string
	Logger           log.Logger
	Statter          stats.Client
	Tracer           trace.Tracer
}

func (c *Consumer) Run(ctx context.Context) error {
	kc, err := NewKafkaConfig(ctx, c.Config)
	if err != nil {
		return errors.Wrap(err, "creating Kafka config")
	}

	src, err := hydro.NewKafkaSource(*kc, c.Config.HydroConsumerGroupID, c.Topics)
	if err != nil {
		return errors.Wrap(err, "creating Kafka source")
	}

	defer func() {
		if err := src.Close(); err != nil {
			c.Logger.WithError(err).Error("failed to close Kafka source")
		}
	}()

	if c.Config.RunLimited {
		if err := c.consumeForTesting(ctx, src); err != nil {
			return errors.Wrap(err, "error while consuming kafka source")
		}
	} else {
		if err := c.consume(ctx, src); err != nil {
			return errors.Wrap(err, "error while consuming kafka source")
		}
	}

	c.Logger.Info("shutting down kafka consumer")

	return nil
}

func (c *Consumer) consumeForTesting(ctx context.Context, consumer hydro.Consumer) error {
	c.Logger.Info("consume for testing starting")

	num := c.Config.NumberOfLimitedMessagesToProcess
	c.Logger.Info(fmt.Sprintf("running limited for %d messages", num))

	for i := 0; i < num; i++ {
		msg, err := consumer.ReadMessage(ctx)
		if err != nil {
			c.Logger.WithError(err).Error("error reading a message")
			return errors.Wrap(err, "error reading a message")
		}

		err = c.processMessage(ctx, &msg)
		if err != nil {
			c.Logger.Error("hydro.consume.failed_to_process_message")
		}

		_ = consumer.MarkMessage(msg)

		c.Logger.Info(fmt.Sprintf("processed job for message %d", i+1))
	}
	return nil
}

func (c *Consumer) consume(ctx context.Context, src hydro.Source) error {
	c.Logger.Info("consume starting")

	if err := src.Consume(ctx, func(innerCtx context.Context, msg hydro.Message) error {
		c.Statter.Counter("hydro_consumer.process_message.start", stats.Tags{"topic": msg.Topic}, 1)
		err := c.processMessage(innerCtx, &msg)
		if err != nil {
			c.Logger.Error("hydro.consume.failed_to_process_message")
		}
		c.Statter.Counter("hydro_consumer.process_message.end", stats.Tags{"topic": msg.Topic}, 1)
		return nil
	}); err != nil {
		return errors.Wrap(err, "error consuming kafka source")
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
	var envelope schemas.Envelope

	if err := proto.Unmarshal(msg.Value, &envelope); err != nil {
		logger.Error("unmarshalling hydro envelope failed")
		return errors.Wrap(err, "unmarshalling hydro envelope failed")
	}

	foundHandler := c.EnvelopeHandlers[envelope.TypeUrl]
	if foundHandler == nil {
		errMsg := fmt.Sprintf("unsupported topic %s", msg.Topic)
		logger.WithError(err).Error(errMsg)
		return errors.Wrap(err, errMsg)
	}

	err = foundHandler.HandleEnvelope(ctx, logger, &envelope)
	if err != nil {
		logger.WithError(err).Error("handler error")
		return err
	}

	return nil
}

func BuildHandlers(cfg *config.Config, logger log.Logger, statter stats.Client, tracer trace.Tracer) map[string]EnvelopeHandler {
	readWriteDB := db.NewDatabase(cfg, logger, statter, tracer)
	return map[string]EnvelopeHandler{
		RepositoryVisibilityChangedTypeURL: &handlers.RepositoryVisibilityChangedHandler{
			DB: readWriteDB,
		},
	}
}

func BuildTopics(cfg *config.Config) []string {
	return []string{
		RepositoryVisibilityChangedTopic,
	}
}
