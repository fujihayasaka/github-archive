package stages

import (
	"context"
	"strconv"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	schema_pb_v1 "github.com/github/notifyd/hydro/schemas/notifyd/v1"
	schema_pb_v1_entities "github.com/github/notifyd/hydro/schemas/notifyd/v1/entities"

	"github.com/github/notifyd/internal/pkg/errors"
	metricspkg "github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

const topic = "notifyd.v1.DeliverWeb"

// WebPublisher represents a web publisher.
type WebPublisher struct {
	metrics   *metricspkg.PublisherMetrics
	publisher *hydro.Publisher
}

// NewWebPublisher creates a new web publisher.
func NewWebPublisher(publisher *hydro.Publisher, metrics *metricspkg.PublisherMetrics) WebPublisher {
	return WebPublisher{
		publisher: publisher,
		metrics:   metrics,
	}
}

// Publish sends a message to the web delivery queue.
func (p WebPublisher) Publish(ctx context.Context, tenant tenancy.Tenant, msg *schema_pb_v1.DeliverWeb) error {
	headers := make(map[string]string)
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(headers))
	tenancy.Inject(tenant, headers)
	err := p.publisher.Publish(msg, hydro.WithTopic(topic), hydro.WithCustomHeaders(headers))
	p.metrics.Send(ctx, "deliver_web", err, metricspkg.WithHydroKey())
	return err
}

type webScheduler struct {
	publisher WebPublisher
	clock     clockpkg.Clock
	telem     *telemetry.Provider
	statter   stats.Client
}

// NewWebScheduler creates a new web scheduler.
func NewWebScheduler(publisher WebPublisher, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) NotificationsScheduler {
	return &webScheduler{
		publisher: publisher,
		clock:     clock,
		telem:     telem,
		statter:   statter,
	}
}

// ScheduleNotifications schedules notifications.
func (s webScheduler) ScheduleNotifications(ctx context.Context, tenant tenancy.Tenant, recipients notify.RecipientToDeliveryMetadata, msg *notify.Notification) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetMethod(ctx, "schedulewebnotifications")
	if tracking := msg.TrackingPB(); tracking != nil && tracking.SubjectMetadata != nil {
		ctx = o11y.CtxSetListID(ctx, tracking.SubjectMetadata.ListId)
		ctx = o11y.CtxSetListType(ctx, tracking.SubjectMetadata.ListType)
		ctx = o11y.CtxSetThreadID(ctx, tracking.SubjectMetadata.ThreadId)
		ctx = o11y.CtxSetThreadType(ctx, tracking.SubjectMetadata.ThreadType)
		ctx = o11y.CtxSetCommentID(ctx, tracking.SubjectMetadata.CommentId)
		ctx = o11y.CtxSetCommentType(ctx, tracking.SubjectMetadata.CommentType)
	}
	t0 := s.clock.Now()
	calculatedRecipients := make([]*schema_pb_v1_entities.Recipient, 0, len(recipients))
	defer func() {
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "schedule_web_notifications"}, s.clock.Since(t0))
		s.telem.Logger.WithContext(ctx).
			WithFields(kvp.Int("gh.notifyd.notifications.count", len(calculatedRecipients))).
			Info("Notifications published")
	}()

	for userID, data := range recipients {
		userCtx := o11y.CtxSetUserID(ctx, userID)

		if channel, exists := data.Channels["WEB"]; !exists || !channel.Enabled {
			s.telem.Logger.WithContext(userCtx).Info("Delivery skipped: channel disabled or non-existent")
			continue
		}

		calculatedRecipients = append(calculatedRecipients, &schema_pb_v1_entities.Recipient{
			UserId:  userID,
			Reasons: data.Reasons,
		})
	}

	if len(calculatedRecipients) == 0 {
		return nil
	}

	// Subject is not available in all notifications: mobile auth requests don't include them.
	// Therefore subjectID should only be extracted after there's some recipient for web notifications,
	// in order to avoid raising an error when there's none.
	subjectID, err := strconv.ParseInt(msg.SubjectValue, 10, 64)
	if err != nil {
		return errors.Wrap(err, "Unable to convert subject value to integer")
	}

	deliverWeb := schema_pb_v1.DeliverWeb{
		SubjectType:    msg.SubjectType,
		SubjectId:      subjectID,
		Recipients:     calculatedRecipients,
		NotificationId: msg.ID,
		Tracking:       msg.TrackingPB(),
	}

	if err := s.publisher.Publish(ctx, tenant, &deliverWeb); err != nil {
		s.statter.Counter(statsScheduleErrorsKey, stats.Tags{"channel": "web"}, int64(len(calculatedRecipients)))
		return errors.Wrap(err, "unable to publish the event")
	}
	s.telem.Logger.WithContext(ctx).Info("Hydro job published")

	return nil
}
