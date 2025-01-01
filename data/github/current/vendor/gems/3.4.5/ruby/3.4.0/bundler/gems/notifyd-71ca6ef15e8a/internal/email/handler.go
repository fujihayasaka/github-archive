package email

import (
	"context"
	"strings"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	ghstats "github.com/github/go-stats"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	messages "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	emaildatastructures "github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/layout"
	layoutconfig "github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/pkg/deliverytracking"
	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/stats"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

const statsTimingKey = "deliveremail.stages.time"

const (
	failed    string = "failed"
	skipped   string = "skipped"
	succeeded string = "succeeded"
)

// result contains the outcome of a delivery attempt. It is used mainly to transform it into
// telemetry information.
type result struct {
	status string
	reason string
}

// tags transforms a deliveryResult in a set of telemetry tags that we can use to know the full
// picture of the email delivery funnel.
func (r *result) tags(extra ghstats.Tags) ghstats.Tags {
	var tags ghstats.Tags
	switch r.status {
	case failed:
		tags = ghstats.Tags{"status": failed, "reason": r.reason}
	case skipped:
		tags = ghstats.Tags{"status": skipped, "reason": r.reason}
	case succeeded:
		tags = ghstats.Tags{"status": succeeded}
	default:
		tags = ghstats.Tags{"status": "unknown"}
	}
	return tags.Merge(extra)
}

// Handler represents a hydro handler for email delivery
type Handler struct {
	checker         policy.Checker
	emailer         Sender
	deliveryTracker deliverytracking.DeliveryTracker
	clock           clockpkg.Clock
	telem           *telemetry.Provider
	statter         ghstats.Client
	cfg             layoutconfig.Config
	processor       pipeline.PostProcessor
}

// NewHandler creates a new email delivery handler
func NewHandler(
	checker policy.Checker,
	emailer Sender,
	deliveryTracker deliverytracking.DeliveryTracker,
	clock clockpkg.Clock,
	telem *telemetry.Provider,
	statter ghstats.Client,
	cfg layoutconfig.Config,
	processor pipeline.PostProcessor,
) *Handler {
	return &Handler{
		checker:         checker,
		emailer:         emailer,
		deliveryTracker: deliveryTracker,
		clock:           clock,
		telem:           telem,
		statter:         statter.WithTags(ghstats.Tags{"type": "email"}),
		cfg:             cfg,
		processor:       processor,
	}
}

// Run receives a DeliverEmail message that it handles by:
// - Rendering its content into an email.Notification
// - Checking whether the notification can be delivered and to which email address
// - Delivers the notification with an email sender
func (h *Handler) Run(ctx context.Context, tenant tenancy.Tenant, msg *messages.DeliverEmail) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	emailMsg := emaildatastructures.EmailFromV0(msg)
	ctx = enrichContext(ctx, emailMsg)
	result, err := h.sendNotification(ctx, tenant, emailMsg)
	h.statter.Counter("delivery", result.tags(ghstats.Tags{"subject_type": msg.GetSubjectType()}), 1)
	return err
}

func (h *Handler) sendNotification(ctx context.Context, tenant tenancy.Tenant, msg *emaildatastructures.Email) (result, error) {
	logger := h.telem.Logger.WithContext(ctx)

	logger.Info("can deliver email notification check")
	canDeliverEmailCheckStartTime := h.clock.Now()

	request, err := createEmailDeliveryRequest(msg)
	if err != nil {
		// we will not retry the error
		return result{status: failed, reason: "faulty_data"}, errors.Wrap(err, "failed to create email delivery request")
	}

	// use the monolith checker to get the data we need to deliver the email
	res, err := h.checker.GetDeliverEmailData(ctx, tenant, request)
	if err != nil {
		return result{status: failed, reason: "policy_check"}, errors.Wrap(err, "performing monolith-twirp check").With(errors.MarkRetriable())
	}
	h.statter.DistributionMs(statsTimingKey, ghstats.Tags{"stage": "can_deliver_email_check"}, h.clock.Since(canDeliverEmailCheckStartTime))

	if !res.IsDeliverable {
		logger.Info("notification was not deliverable")

		return result{status: skipped, reason: res.NotDeliverableReason}, nil
	}

	logger.
		WithFields(
			kvp.Any("gh.notifyd.layout", msg.LayoutData.GetTypeUrl()),
		).
		Info("processing layout")
	processingLayoutStartTime := h.clock.Now()
	processor, err := layout.BuildProcessor(h.cfg, h.telem, h.statter, h.processor, msg.LayoutData.GetTypeUrl())
	if err != nil {
		return result{status: failed, reason: "processor_failure"}, errors.Wrap(err, "building email processor")
	}

	email, err := processor.Process(ctx, tenant, res, msg)
	if err != nil {
		return result{status: failed, reason: "rendering_template"}, errors.Wrap(err, "processing email")
	}
	h.statter.DistributionMs(statsTimingKey, ghstats.Tags{"stage": "processing_layout"}, h.clock.Since(processingLayoutStartTime))

	logger.Info("sending email")
	sendEmailStartTime := h.clock.Now()
	if err := h.emailer.Send(ctx, email); err != nil {
		return result{status: failed, reason: "sending_email"}, errors.Wrap(err, "sending email")
	}
	h.statter.DistributionMs(statsTimingKey, ghstats.Tags{"stage": "sending_email"}, h.clock.Since(sendEmailStartTime))

	logger.Info("notification delivered")

	h.logCompletion(logger, msg.Tracking)

	updateDeliveryTrackerStartTime := h.clock.Now()
	// This error is handled by the delivery tracker and reported when needed, we don't want to fail
	// this message because we couldn't send stats for it.
	_ = h.deliveryTracker.Track(ctx, &messages.DeliveredNotification{
		NotificationId: msg.NotificationID,
		//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
		UserId:   int32(msg.UserID),
		Reasons:  reasonsToPB(msg.Reasons),
		Channel:  entities.Channel_EMAIL,
		Tracking: convertTracking(msg.Tracking),
	})
	h.statter.DistributionMs(statsTimingKey, ghstats.Tags{"stage": "update_delivery_tracker"}, h.clock.Since(updateDeliveryTrackerStartTime))

	return result{status: succeeded}, nil
}

func (h *Handler) logCompletion(logger log.Logger, tracking *emaildatastructures.Tracking) {
	if tracking == nil {
		logger.Error("Missing tracking information")
		return
	}

	err := stats.TrackTimeToSent(h.clock, h.statter, tracking.TriggeredAt)
	if err != nil {
		logger.Error(err.Error())
	}
}

func enrichContext(ctx context.Context, msg *emaildatastructures.Email) context.Context {
	ctx = o11y.CtxSetChannel(ctx, "email")
	ctx = o11y.CtxSetNotificationID(ctx, msg.NotificationID)
	ctx = o11y.CtxSetUserID(ctx, msg.UserID)
	if tracking := msg.Tracking; tracking != nil && tracking.SubjectMetadata != nil {
		ctx = o11y.CtxSetListID(ctx, tracking.SubjectMetadata.ListID)
		ctx = o11y.CtxSetListType(ctx, tracking.SubjectMetadata.ListType)
		ctx = o11y.CtxSetThreadID(ctx, tracking.SubjectMetadata.ThreadID)
		ctx = o11y.CtxSetThreadType(ctx, tracking.SubjectMetadata.ThreadType)
		ctx = o11y.CtxSetCommentID(ctx, tracking.SubjectMetadata.CommentID)
		ctx = o11y.CtxSetCommentType(ctx, tracking.SubjectMetadata.CommentType)
	}
	ctx = o11y.CtxSetReasons(ctx, strings.Join(msg.Reasons, ", "))
	return ctx
}

func createEmailDeliveryRequest(msg *emaildatastructures.Email) (*policy.EmailDeliveryRequest, error) {
	notificationID, err := structpb.NewStruct(map[string]interface{}{
		"notification_id": msg.NotificationID,
	})
	if err != nil {
		return nil, errors.Wrap(err, "failed to create notification id string value")
	}

	return &policy.EmailDeliveryRequest{
			UserID:         msg.UserID,
			OrganizationID: msg.OrganizationID,
			NotificationID: notificationID,
			MatchData:      msg.MatchData},
		nil
}

// reasonsToPB turns our internal reasons into entities Reason
func reasonsToPB(reasons []string) []*entities.Reason {
	var r []*entities.Reason
	for _, reason := range reasons {
		r = append(r, &entities.Reason{Name: reason})
	}

	return r
}

// convertTracking converts *emaildatastructures.Tracking to *entities.Tracking
func convertTracking(tracking *emaildatastructures.Tracking) *entities.Tracking {
	if tracking == nil {
		return nil
	}
	trackingEntity := &entities.Tracking{
		TriggeredAt: timestamppb.New(tracking.TriggeredAt),
	}

	if tracking.SubjectMetadata != nil {
		trackingEntity.SubjectMetadata = &entities.Tracking_SubjectMetadata{
			ListType:    tracking.SubjectMetadata.ListType,
			ListId:      tracking.SubjectMetadata.ListID,
			ThreadType:  tracking.SubjectMetadata.ThreadType,
			ThreadId:    tracking.SubjectMetadata.ThreadID,
			CommentType: tracking.SubjectMetadata.CommentType,
			CommentId:   tracking.SubjectMetadata.CommentID,
		}
	}

	return trackingEntity
}
