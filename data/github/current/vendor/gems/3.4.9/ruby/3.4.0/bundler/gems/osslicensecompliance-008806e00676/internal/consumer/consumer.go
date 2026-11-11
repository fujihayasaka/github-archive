// Package consumer provides Hydro Kafka consumer utilities and setup.
package consumer

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	hydro_base "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/repocheck"
	"github.com/github/osslicensecompliance/internal/semconv"
)

const snapshotProcessedTopic = "github.dependencygraph.v1.SnapshotProcessed"

var snapshotProcessedTopics = []string{snapshotProcessedTopic}

// Consumer wraps a Kafka consumer source with configuration.
type Consumer struct {
	source  *hydro.KafkaSource
	app     *application.Application
	metrics stats.Client
}

// New creates and configures a new Kafka consumer.
func New(cfg *config.Config, statter stats.Client, app *application.Application) (*Consumer, error) {
	source, err := newKafkaSource(cfg, app.Logger, statter, snapshotProcessedTopics)
	if err != nil {
		return nil, err
	}

	return &Consumer{
		source:  source,
		app:     app,
		metrics: statter,
	}, nil
}

// Consume starts consuming messages and processes snapshot-processed messages.
func (c *Consumer) Consume(ctx context.Context) error {
	return c.source.Consume(ctx, func(_ context.Context, m hydro.Message) error {
		var env hydro_base.Envelope
		if err := proto.Unmarshal(m.Value, &env); err != nil {
			c.app.Logger.WithError(err).Error("failed to decode envelope")
			return err
		}

		tags := stats.Tags{
			"topic":     m.Topic,
			"partition": strconv.FormatInt(int64(m.Partition), 10),
		}
		c.metrics.DistributionMs("hydro.consumer.latency", tags, time.Since(env.Timestamp.AsTime()))

		c.app.Logger = c.app.Logger.WithFields([]kvp.Field{
			semconv.MessagingMessageID(env.Id),
			semconv.MessagingDestinationName(m.Topic),
			semconv.MessagingDestinationPartitionID(m.Partition),
			semconv.MessagingKafkaMessageOffset(m.Offset),
			tenant.GetTenantField(ctx),
			tenant.GetTenantIDField(ctx),
		}...)
		c.app.Logger.Info("message received")

		execStartTime := time.Now()
		var err error
		switch m.Topic {
		case snapshotProcessedTopic:
			err = c.HandleSnapshotProcessed(ctx, m)
		default:
			c.app.Logger.Error("Message not in consumed topic")
			err = nil
		}

		execDuration := time.Since(execStartTime)
		c.metrics.DistributionMs("hydro.consumer.execution", tags.Merge(stats.Tags{
			"completed_with_error": strconv.FormatBool(err != nil),
		}), execDuration)

		return err
	})
}

// HandleSnapshotProcessed processes a snapshot processed event from Kafka.
// This method is called for each message received on the github.dependencygraph.v1.SnapshotProcessed topic.
// When a snapshot is processed, we check if there's an existing check job for that repository and commit,
// and if so, we attempt to run the repository check to see if all snapshots are now ready.
func (c *Consumer) HandleSnapshotProcessed(ctx context.Context, m hydro.Message) error {
	var env hydro_base.Envelope
	if err := proto.Unmarshal(m.Value, &env); err != nil {
		c.app.Logger.WithError(err).Error("failed to decode envelope")
		return nil // Don't return error to avoid retrying malformed messages
	}

	var snapshotProcessed dependencygraphv1.SnapshotProcessed
	if err := proto.Unmarshal(env.Message, &snapshotProcessed); err != nil {
		c.app.Logger.WithError(err).Error("failed to unmarshal SnapshotProcessed message")
		return nil
	}

	repoID := snapshotProcessed.GetRepositoryId()
	if repoID < 0 {
		c.app.Logger.Error("invalid repository ID: negative value")
		return nil
	}
	// #nosec G115 -- we've validated that repoID >= 0 above
	repositoryID := uint64(repoID)
	commitSHA := snapshotProcessed.GetSha()

	logger := c.app.Logger.WithFields(
		kvp.Uint64("repository_id", repositoryID),
		kvp.String("commit_sha", commitSHA),
		kvp.String("detector_name", snapshotProcessed.GetDetectorName()),
	)

	logger.Info("snapshot processed event received")

	if err := repocheck.SnapshotReceived(ctx, c.app, repositoryID, commitSHA); err != nil {
		var validationErr *repocheck.ValidationError
		switch {
		case errors.As(err, &validationErr):
			logger.Error("validation error in check request", kvp.Any("missing_fields", validationErr.MissingFields))
			return nil // Don't return error to avoid retrying malformed messages
		default:
			logger.WithError(err).Error("repository check failed")
			return err
		}
	}

	return nil
}

// newKafkaSource creates and configures a new Kafka consumer source using the application config.
func newKafkaSource(cfg *config.Config, logger log.Logger, statter stats.Client, topics []string) (*hydro.KafkaSource, error) {
	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return nil, err
	}

	consumerOpts := []hydro.KafkaConfigOption{
		hydro.WithSaramaConfig(
			func(scfg *sarama.Config) {
				// Only read new messages at first startup: no backfill, allow old
				// messages to be skipped.
				scfg.Consumer.Offsets.Initial = sarama.OffsetNewest
			}),
	}

	for _, opt := range consumerOpts {
		if err := opt(kc); err != nil {
			return nil, fmt.Errorf("apply consumer config option: %w", err)
		}
	}

	// clientID is being passed as the kafka groupName here
	src, err := hydro.NewKafkaSource(*kc, cfg.KafkaClientID, topics)
	if err != nil {
		return nil, fmt.Errorf("new kafka source: %w", err)
	}

	return src, nil
}
