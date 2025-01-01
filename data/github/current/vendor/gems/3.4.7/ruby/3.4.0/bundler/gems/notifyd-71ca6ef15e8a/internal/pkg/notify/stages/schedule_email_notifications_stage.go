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
	wrappers "google.golang.org/protobuf/types/known/wrapperspb"

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

// EmailPublisher is an aqueduct.Sender that is by default configured to publish into our email
// queue and handles some basic metrics of the process.
type EmailPublisher struct {
	telem   *telemetry.Provider
	client  aqueduct.Sender
	app     string
	metrics *metricspkg.PublisherMetrics
}

// Publish sends a message to the email delivery queue.
func (p *EmailPublisher) Publish(ctx context.Context, tenant tenancy.Tenant, msg *schema_pb.DeliverEmail) error {
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
		return errors.Wrap(err, "error encoding email message")
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
		Queue:   aqueduct.QueueDeliverEmail,
		Payload: payload.Content(),
		Headers: headers.IntoMap(),
	}

	id, err := p.client.Send(ctx, aqueductJob)
	if err == nil {
		fields := headers.ToLog()
		fields = append(fields, kvp.String("gh.aqueduct.job.id", id))
		logger.Info("sent aqueduct job to deliver email", fields...)
	}
	p.metrics.Send(ctx, "deliver_email", err, metricspkg.WithAqueductKey())

	return err
}

// NewEmailPublisher creates a new EmailPublisher.
func NewEmailPublisher(client aqueduct.Sender, app string, telem *telemetry.Provider, metrics *metricspkg.PublisherMetrics) *EmailPublisher {
	return &EmailPublisher{client: client, app: app, telem: telem, metrics: metrics}
}

type emailScheduleStage struct {
	publisher *EmailPublisher
	clock     clockpkg.Clock
	telem     *telemetry.Provider
	statter   stats.Client
}

// NewScheduleEmailNotificationsStage creates a new email schedule stage.
func NewScheduleEmailNotificationsStage(publisher *EmailPublisher, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) NotificationsScheduler {
	return &emailScheduleStage{
		publisher: publisher,
		clock:     clock,
		telem:     telem,
		statter:   statter,
	}
}

// ScheduleNotifications schedules email notifications.
func (s *emailScheduleStage) ScheduleNotifications(ctx context.Context, tenant tenancy.Tenant, recipientToDeliveryMetadata notify.RecipientToDeliveryMetadata, msg *notify.Notification) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetMethod(ctx, "scheduleemailnotifications")
	logger := s.telem.Logger.WithContext(ctx)
	start := s.clock.Now()
	count := 0
	defer func() {
		logger.WithFields(kvp.Int("gh.notifyd.notifications.count", count)).Info("Notifications published")
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "schedule_email_notifications"}, s.clock.Since(start))
	}()

	// In case we don't have an email layout we don't even try to check the email delivery feature flag.
	if !msg.HasEmailLayout() {
		logger.Info("Delivery skipped: no layout found")
		return nil
	}

	for userID, deliveryMetadata := range recipientToDeliveryMetadata {
		if channel, exists := deliveryMetadata.Channels["EMAIL"]; !exists || !channel.Enabled {
			logger.Info("Delivery skipped: channel disabled or non-existent")
			continue
		}

		// NOTE: (@franciscoj 18/08/2023) we consider this the start of the email delivery funnel.
		// Before this point we can't even know if there's intention to deliver an email.
		s.statter.Counter(statsDelivery, stats.Tags{"type": "email", "status": "enqueued"}, 1)
		reasons := make([]*entities_pb.Reason, len(deliveryMetadata.Reasons))
		for i, r := range deliveryMetadata.Reasons {
			reasons[i] = &entities_pb.Reason{Name: r}
		}

		deliverEmail := schema_pb.DeliverEmail{
			NotificationId: msg.ID,
			//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
			UserId:         int32(userID),
			Reasons:        reasons,
			SubjectType:    msg.SubjectType,
			LayoutData:     msg.EmailLayout(),
			Tracking:       msg.TrackingPB(),
			OrganizationId: getOrgIDFromMsg(msg),
			MatchData:      msg.MatchData(),
		}

		if err := s.publisher.Publish(ctx, tenant, &deliverEmail); err != nil {
			s.statter.Counter(statsDelivery, stats.Tags{"type": "email", "status": "failed", "reason": "unable_to_publish"}, 1)
			s.statter.Counter(statsScheduleErrorsKey, stats.Tags{"channel": "email"}, 1)
			return errors.Wrap(err, "unable to publish the event")
		}

		count++
	}

	return nil
}

func getOrgIDFromMsg(msg *notify.Notification) *wrappers.Int64Value {
	var orgID *wrappers.Int64Value
	if msg.Context.OwnerType == notify.OwnerTypeOrg {
		orgID = wrappers.Int64(msg.Context.OwnerID)
	}
	return orgID
}
