// Package consumer provides Hydro Kafka consumer utilities and setup.
package consumer

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-server/cache/requestcache"
	"github.com/github/go-server/runtime/telemetry/customfields"
	"github.com/github/go-server/runtime/telemetry/reporter"
	"github.com/github/go-stats"
	hydro_base "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/repocheck"
	"github.com/github/osslicensecompliance/internal/semconv"
	"github.com/github/osslicensecompliance/internal/storage"
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

// NewForTest creates a Consumer without a Kafka source, for unit testing handlers directly.
func NewForTest(app *application.Application, metrics stats.Client) *Consumer {
	return &Consumer{
		app:     app,
		metrics: metrics,
	}
}

// Consume starts consuming messages and processes snapshot-processed messages.
func (c *Consumer) Consume(ctx context.Context) error {
	return c.source.Consume(ctx, func(msgCtx context.Context, m hydro.Message) error {
		return c.processMessage(msgCtx, m)
	})
}

// processMessage decodes the Hydro envelope, builds a per-message logger, and
// dispatches to the appropriate handler based on topic.
func (c *Consumer) processMessage(ctx context.Context, m hydro.Message) error {
	// Install the exception reporter and a per-message customfields cache so
	// downstream code can attach IDs to error reports the same way the Twirp
	// CustomFieldsInterceptor does for HTTP requests.
	ctx = requestcache.WithEmptyCache(ctx)
	ctx = reporter.WithReporter(ctx, c.app.Reporter)

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

	logger := c.app.Logger.WithFields(
		semconv.MessagingMessageID(env.Id),
		semconv.MessagingDestinationName(m.Topic),
		semconv.MessagingDestinationPartitionID(m.Partition),
		semconv.MessagingKafkaMessageOffset(m.Offset),
		tenant.GetTenantField(ctx),
		tenant.GetTenantIDField(ctx),
	)
	logger.Info("message received")

	execStartTime := time.Now()
	var err error
	switch m.Topic {
	case snapshotProcessedTopic:
		err = c.HandleSnapshotProcessed(ctx, logger, &env)
	default:
		logger.Error("Message not in consumed topic")
		err = nil
	}

	execDuration := time.Since(execStartTime)
	c.metrics.DistributionMs("hydro.consumer.execution", tags.Merge(stats.Tags{
		"completed_with_error": strconv.FormatBool(err != nil),
	}), execDuration)

	if err != nil {
		if reportErr := reporter.ReportWithValues(ctx, err, map[string]string{"topic": m.Topic}); reportErr != nil {
			logger.WithError(reportErr).Error("failed to report error to Sentry")
		}
	}

	return err
}

// DependabotDetectorName is the detector name used by dependabot snapshots in ds-api.
const DependabotDetectorName = "dependabot"

// HandleSnapshotProcessed processes a snapshot processed event from Kafka.
// This method is called for each message received on the github.dependencygraph.v1.SnapshotProcessed topic.
// When a snapshot is processed, we look up waiting check jobs by commit SHA and by head ref
// (for dependabot_pending rows), deduplicate, and wake each one.
func (c *Consumer) HandleSnapshotProcessed(ctx context.Context, logger log.Logger, env *hydro_base.Envelope) error {
	var snapshotProcessed dependencygraphv1.SnapshotProcessed
	if err := proto.Unmarshal(env.Message, &snapshotProcessed); err != nil {
		logger.WithError(err).Error("failed to unmarshal SnapshotProcessed message")
		return nil
	}

	repoID := snapshotProcessed.GetRepositoryId()
	if repoID < 0 {
		logger.Error("invalid repository ID: negative value", kvp.Int64("repository_id", repoID))
		return nil
	}
	// #nosec G115 -- we've validated that repoID >= 0 above
	repositoryID := uint64(repoID)
	commitSHA := snapshotProcessed.GetSha()

	logger = logger.WithFields(
		kvp.Uint64("repository_id", repositoryID),
		kvp.String("commit_sha", commitSHA),
		kvp.String("detector_name", snapshotProcessed.GetDetectorName()),
	)

	customfields.AddTag(ctx, "repository_id", strconv.FormatUint(repositoryID, 10))
	customfields.AddField(ctx, "commit_sha", commitSHA)
	customfields.AddField(ctx, "detector_name", snapshotProcessed.GetDetectorName())

	logger.Info("snapshot processed event received")

	// SHA-based lookup
	shaJob, shaErr := c.app.Subsystems.Storage.GetCheckJobByCommit(ctx, repositoryID, commitSHA)
	if shaErr != nil {
		logger.WithError(shaErr).Error("SHA-based check job lookup failed")
	}

	// Ref-based lookup (only for dependabot snapshots targeting dependabot_pending + Waiting rows)
	var refJobs []*models.CheckJob
	var refErr error
	if snapshotProcessed.GetDetectorName() == DependabotDetectorName {
		normalizedRef := storage.NormalizeHeadRef(string(snapshotProcessed.GetRef()))
		if normalizedRef != "" {
			refJobs, refErr = c.app.Subsystems.Storage.GetWaitingDependabotPendingCheckJobsByRef(ctx, repositoryID, normalizedRef)
			if refErr != nil {
				logger.WithError(refErr).Error("ref-based check job lookup failed")
			}
		}
	}

	// Deduplicate by CheckJob.ID
	wakeSet := make(map[uint64]*models.CheckJob)
	if shaJob != nil {
		wakeSet[shaJob.ID] = shaJob
	}
	for _, job := range refJobs {
		if _, exists := wakeSet[job.ID]; !exists {
			wakeSet[job.ID] = job
		}
	}

	// Emit match result counter
	shaMatched := shaJob != nil
	refMatched := len(refJobs) > 0
	matchMode := "none"
	switch {
	case shaMatched && refMatched:
		matchMode = "both"
	case shaMatched:
		matchMode = "sha"
	case refMatched:
		matchMode = "ref"
	default:
		// matchMode remains "none"
	}
	hasDependabotPending := false
	for _, job := range wakeSet {
		if job.DependabotPending {
			hasDependabotPending = true
			break
		}
	}
	c.metrics.Counter("consumer.snapshot_processed.match_result", stats.Tags{
		"match_mode":         matchMode,
		"dependabot_pending": strconv.FormatBool(hasDependabotPending),
	}, 1)

	// Wake each job
	var firstWakeErr error
	for _, job := range wakeSet {
		if err := repocheck.WakeCheckJob(ctx, c.app, job); err != nil {
			logger.WithError(err).Error("repository check failed")
			if firstWakeErr == nil {
				firstWakeErr = err
			}
		}
	}

	// Return first retryable error: lookup errors take priority, then wake errors
	if shaErr != nil {
		return shaErr
	}
	if refErr != nil {
		return refErr
	}
	return firstWakeErr
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
