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
	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/compress"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/job"
	metricspkg "github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// PushPublisher is an aqueduct.Sender that is by default configured to publish into our email
// queue and handles some basic metrics of the process.
//
// PushPublisher is an alias type. We use it so that both the schedule push and
// email stages can receive a different publisher as wire has a limitation that avoids injecting
// more than one object of the same type.
//
// The alias type avoids that limitation.
type PushPublisher struct {
	client  aqueduct.Sender
	app     string
	metrics *metricspkg.PublisherMetrics
	telem   *telemetry.Provider
}

// Publish sends a message to the mobile push notifications delivery queue.
func (p *PushPublisher) Publish(ctx context.Context, tenant tenancy.Tenant, msg *schema_pb.DeliverMobilePush) error {
	ctx = o11y.CtxSetUserID(ctx, int64(msg.GetUserId()))
	if tracking := msg.GetTracking(); tracking != nil && tracking.SubjectMetadata != nil {
		ctx = o11y.CtxSetListID(ctx, tracking.SubjectMetadata.ListId)
		ctx = o11y.CtxSetListType(ctx, tracking.SubjectMetadata.ListType)
		ctx = o11y.CtxSetThreadID(ctx, tracking.SubjectMetadata.ThreadId)
		ctx = o11y.CtxSetThreadType(ctx, tracking.SubjectMetadata.ThreadType)
		ctx = o11y.CtxSetCommentID(ctx, tracking.SubjectMetadata.CommentId)
		ctx = o11y.CtxSetCommentType(ctx, tracking.SubjectMetadata.CommentType)
	}
	logger := p.telem.Logger.WithContext(ctx)

	payload, err := aqueduct.NewPayloadFromProtobuf(msg, aqueduct.WithCompressedPayload(compress.Deflate, logger))
	if err != nil {
		return errors.Wrap(err, "error encoding mobile push message")
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
		Queue:   aqueduct.QueueDeliverMobilePush,
		Payload: payload.Content(),
		Headers: headers.IntoMap(),
	}

	id, err := p.client.Send(ctx, aqueductJob)
	if err == nil {
		fields := headers.ToLog()
		fields = append(fields, kvp.String("gh.aqueduct.job.id", id))
		logger.Info("sent aqueduct job to deliver mobile push notification", fields...)
	}
	p.metrics.Send(ctx, "deliver_mobile_push", err, metricspkg.WithAqueductKey())

	return err
}

// NewPushPublisher creates a new PushPublisher.
func NewPushPublisher(client aqueduct.Sender, app string, telem *telemetry.Provider, metrics *metricspkg.PublisherMetrics) *PushPublisher {
	return &PushPublisher{client: client, app: app, metrics: metrics, telem: telem}
}

// PushConfig represents the configuration for the push stage.
type PushConfig struct {
	// Enabled determines whether push notifications should be scheduled at all.
	// When this is set to false the scheduler does nothing.
	Enabled bool `config:"true,env=MOBILE_PUSH_NOTIFICATIONS_ENABLED"`
}

type schedulePushNotificationsStage struct {
	enabled   bool
	publisher *PushPublisher
	clock     clockpkg.Clock
	telem     *telemetry.Provider
	statter   stats.Client
}

// NewSchedulePushNotificationsStage creates a new schedule push notifications stage.
func NewSchedulePushNotificationsStage(cfg PushConfig, publisher *PushPublisher, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) NotificationsScheduler {
	return &schedulePushNotificationsStage{
		enabled:   cfg.Enabled,
		publisher: publisher,
		clock:     clock,
		telem:     telem,
		statter:   statter,
	}
}

// ScheduleNotifications schedules push notifications.
func (s *schedulePushNotificationsStage) ScheduleNotifications(ctx context.Context, tenant tenancy.Tenant, recipientToDeliveryMetadata notify.RecipientToDeliveryMetadata, msg *notify.Notification) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetMethod(ctx, "schedulepushnotifications")
	start := s.clock.Now()
	count := 0
	defer func() {
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "schedule_push_notifications"}, s.clock.Since(start))
		s.telem.Logger.WithContext(ctx).WithFields(kvp.Int("gh.notifyd.notifications.count", count)).Info("Notifications published")
	}()

	if !msg.HasMobileLayout() {
		s.telem.Logger.WithContext(ctx).Info("Delivery skipped: no layout found")
		return nil
	}

	if !s.enabled {
		s.telem.Logger.WithContext(ctx).Info("Delivery skipped: mobile push notifications disabled")
		return nil
	}

	for recipientID, deliveryMetadata := range recipientToDeliveryMetadata {
		channel, exists := deliveryMetadata.Channels["PUSH"]
		if !exists || !channel.Enabled {
			s.telem.Logger.WithContext(ctx).Info("Delivery skipped: channel disabled or non-existent")
			continue
		}

		reasons := make([]*entities_pb.Reason, len(deliveryMetadata.Reasons))
		for i, r := range deliveryMetadata.Reasons {
			reasons[i] = &entities_pb.Reason{Name: r}
		}

		deliverMobilePush := schema_pb.DeliverMobilePush{
			NotificationId: msg.ID,
			//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
			UserId:          int32(recipientID),
			Reasons:         reasons,
			LayoutData:      msg.MobileLayout(),
			SamlEnforcement: msg.SamlEnforcement(),
			Tracking:        msg.TrackingPB(),
		}
		if err := s.publisher.Publish(ctx, tenant, &deliverMobilePush); err != nil {
			s.statter.Counter(statsScheduleErrorsKey, stats.Tags{"channel": "push"}, 1)
			return errors.Wrap(err, "unable to publish the event")
		}

		count++
	}
	return nil
}
