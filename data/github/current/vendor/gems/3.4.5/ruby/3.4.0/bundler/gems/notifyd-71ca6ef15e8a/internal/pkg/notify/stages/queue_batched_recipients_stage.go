package stages

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	ghaqueduct "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/compress"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// BatchQueuePublisher represents a batch queue publisher.
type BatchQueuePublisher struct {
	telem  *telemetry.Provider
	client aqueduct.Sender
	app    string
}

// Publish sends a message to the notify queue.
func (p *BatchQueuePublisher) Publish(ctx context.Context, tenant tenancy.Tenant, msg *schema_pb.Notify) error {
	logger := p.telem.Logger.WithContext(ctx)

	payload, err := aqueduct.NewPayloadFromProtobuf(msg, aqueduct.WithCompressedPayload(compress.Deflate, logger))
	if err != nil {
		return errors.Wrap(err, "error encoding message")
	}

	otelHeaders := make(map[string]string)
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(otelHeaders))

	headers := job.NewHeaders(
		job.WithDefaultSenderHeaders(ctx),
		job.WithContentLengthHeader(payload.Len()),
		job.WithContentEncodingHeader(payload.Encoding()),
		job.WithTenantHeaders(tenant),
		job.WithHeadersFromMap(otelHeaders),
	)

	aqueductJob := ghaqueduct.Job{
		App:     p.app,
		Queue:   aqueduct.QueueNotify,
		Payload: payload.Content(),
		Headers: headers.IntoMap(),
	}

	id, err := p.client.Send(ctx, aqueductJob)
	if err != nil {
		return err
	}
	fields := headers.ToLog()
	fields = append(fields, kvp.String("gh.aqueduct.job.id", id))
	logger.Info("queued aqueduct job to notify queue", fields...)
	return nil
}

// NewBatchQueuePublisher creates a new batch queue publisher.
func NewBatchQueuePublisher(client aqueduct.Sender, app string, telem *telemetry.Provider) *BatchQueuePublisher {
	return &BatchQueuePublisher{client: client, app: app, telem: telem}
}

type queueBatchedRecipientsStage struct {
	publisher *BatchQueuePublisher
	clock     clockpkg.Clock
	telem     *telemetry.Provider
	statter   stats.Client
}

// NewQueueBatchedRecipientsStage creates a new queue batched recipients stage.
func NewQueueBatchedRecipientsStage(publisher *BatchQueuePublisher, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) IQueueBatchedRecipientsStage {
	return &queueBatchedRecipientsStage{
		publisher: publisher,
		clock:     clock,
		telem:     telem,
		statter:   statter,
	}
}

// QueueBatchedRecipients queues recipients.
func (s *queueBatchedRecipientsStage) QueueBatchedRecipients(ctx context.Context, tenant tenancy.Tenant, recipients notify.RecipientIDToReasons, msg *schema_pb.Notify, batcher notify.Batcher) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	start := s.clock.Now()
	defer func() {
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "requeue_batched_recipients", "bucket": recipientCountBucket(len(recipients))}, s.clock.Since(start))
	}()

	batchGroups := batcher.Split(recipients)

	for _, batchGroup := range batchGroups {
		if err := s.publishMessage(ctx, tenant, batchGroup.ToPB(), msg); err != nil {
			continue
		}
	}

	s.telem.Logger.WithContext(ctx).WithFields(kvp.Int("gh.notifyd.notifications.count", len(recipients))).
		Info("re-queued recipients")
}

// publishMessage adds the notify_subscribers flag to the message and a batched set of explicit recipients.
// The notify_subscribers flag is required to prevent the messages from re-collecting recipients and causing an infinite loop.
// The explicit recipients are a batch of calculated recipients
func (s *queueBatchedRecipientsStage) publishMessage(ctx context.Context, tenant tenancy.Tenant, notifyRecipientGroups []*schema_pb.Notify_RecipientGroup, msg *schema_pb.Notify) error {
	msg.ExplicitRecipients = notifyRecipientGroups

	if msg.GetFeatureSwiches() == nil {
		msg.FeatureSwiches = make(map[string]bool)
	}

	msg.FeatureSwiches["notify_subscribers"] = false

	return s.publisher.Publish(ctx, tenant, msg)
}

func recipientCountBucket(number int) string {
	switch {
	case number <= 500:
		return "0-500"
	case number <= 1000:
		return "500-1000"
	case number <= 2000:
		return "1000-2000"
	case number <= 5000:
		return "2000-5000"
	case number <= 10000:
		return "5000-10000"
	case number <= 20000:
		return "10000-20000"
	default:
		return "20000plus"
	}
}
