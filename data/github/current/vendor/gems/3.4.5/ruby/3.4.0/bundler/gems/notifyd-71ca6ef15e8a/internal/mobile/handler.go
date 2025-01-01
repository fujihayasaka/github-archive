package mobile

import (
	"context"
	"time"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	ghstats "github.com/github/go-stats"

	schemas "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/mobile/clients"
	"github.com/github/notifyd/internal/mobile/layout"
	"github.com/github/notifyd/internal/pkg/deliverytracking"
	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/o11y/stats"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Handler implements the handling of the deliver mobile push messages.
type Handler struct {
	clock           clockpkg.Clock
	statter         ghstats.Client
	mobileClient    clients.MobileClient
	tokens          devicetokens.Storage
	policyChecker   policy.Checker
	telem           *telemetry.Provider
	deliveryTracker deliverytracking.DeliveryTracker
}

const statsTimingKey = "delivermobilepush.stages.time"

// NewHandler configures a new mobile push handler
func NewHandler(
	clock clockpkg.Clock,
	telem *telemetry.Provider,
	statter ghstats.Client,
	mobileClient clients.MobileClient,
	tokens devicetokens.Storage,
	policyChecker policy.Checker,
	deliveryTracker deliverytracking.DeliveryTracker,
) *Handler {
	return &Handler{
		clock:           clock,
		statter:         statter.WithTags(ghstats.Tags{"type": "mobile"}),
		mobileClient:    mobileClient,
		tokens:          tokens,
		policyChecker:   policyChecker,
		deliveryTracker: deliveryTracker,
		telem:           telem,
	}
}

// Run takes a `schemas.DeliverMobilePush` message and uses it to:
//   - Get all the tokens for the recipient user
//   - Filter them according to things like SAML auth
//   - Build the actual notification to send
//   - Make the actual request to deliver the push notification.
//   - Use the response from the push to log how many tokens were successfully
//     delivered and how many failed.
//   - Use the response from the push to record on the DB the deliveries we've
//     made and their status.
func (h *Handler) Run(ctx context.Context, tenant tenancy.Tenant, mobilePushMsg *schemas.DeliverMobilePush) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	msg := layout.Message{DeliverMobilePush: mobilePushMsg}
	userID := int64(msg.GetUserId())
	ctx = enrichContext(ctx, &msg)
	logger := h.telem.Logger.WithContext(ctx)

	logger.Info("processing DeliverMobilePush message")
	reason, notificationType := msg.GetReasonAndType()
	if reason == "" {
		logger.Info("no valid reason")
		return nil
	}

	tokens, err := h.tokens.Get(ctx, userID)
	if err != nil {
		logger.WithError(err).Error("error fetching device tokens")
		h.statter.Counter("delivery", ghstats.Tags{"status": "failed", "error_type": "fetching_tokens"}, 1)
		return errors.Wrap(err, "error fetching device tokens").With(errors.MarkRetriable())
	}
	if len(tokens) == 0 {
		logger.Info("no device tokens")
		return nil
	}

	t0 := h.clock.Now()
	tokens, username := h.authorized(ctx, tenant, msg, reason, tokens)
	h.statter.DistributionMs(statsTimingKey, ghstats.Tags{"stage": "authorize_tokens"}, h.clock.Since(t0))
	if len(tokens) == 0 {
		logger.Info("no valid device tokens after checking mobile push policy")
		return nil
	}

	notification, err := msg.BuildNotification(username, notificationType)
	if err != nil {
		logger.WithError(err).Error("couldn't build notification")
		h.statter.Counter("delivery", ghstats.Tags{"status": "failed", "error_type": "building_notification"}, int64(len(tokens)))
		return errors.Wrap(err, "error building notification")
	}

	t0 = h.clock.Now()
	resp, err := h.mobileClient.SendNotification(ctx, *notification, tokens)
	h.statter.DistributionMs(statsTimingKey, ghstats.Tags{"stage": "send_notification"}, h.clock.Since(t0))
	if err != nil {
		h.statter.Counter("delivery", ghstats.Tags{"status": "failed", "error_type": "fcm_request_failed"}, int64(resp.FailedCount))
		return errors.Wrap(err, "error sending fcm notification").With(errors.MarkTransient())
	}
	if resp.FailedCount != 0 {
		h.statter.Counter("delivery", ghstats.Tags{"status": "skipped", "reason": "invalid_token"}, int64(resp.FailedCount))
	}

	h.statter.Counter("delivery", ghstats.Tags{"status": "succeeded"}, int64(resp.DeliveredCount))
	logger.
		WithFields(
			kvp.Int("gh.notifyd.tokens.delivered", resp.DeliveredCount),
			kvp.Int("gh.notifyd.tokens.failed", resp.FailedCount)).
		Info("notification delivered")

	h.logCompletion(logger, msg.GetTriggeredAtTime())

	t0 = h.clock.Now()
	for _, token := range resp.Delivered {
		// This error is handled by the delivery tracker already, we don't want to fail the whole
		// message because of it.
		_ = h.deliveryTracker.Track(ctx, &schemas.DeliveredNotification{
			NotificationId: msg.GetNotificationId(),
			//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
			UserId:   int32(userID),
			Reasons:  []*entities.Reason{{Name: reason}},
			Channel:  entities.Channel_MOBILE_PUSH,
			Token:    token.DeviceToken,
			Tracking: msg.GetTracking(),
		})
	}
	h.statter.DistributionMs(statsTimingKey, ghstats.Tags{"stage": "update_delivery_tracker"}, h.clock.Since(t0))

	h.unregister(ctx, userID, resp.Unregistered)

	return nil
}

func (h *Handler) logCompletion(logger log.Logger, eventTriggeredAtTime time.Time) {
	err := stats.TrackTimeToSent(h.clock, h.statter, eventTriggeredAtTime)
	if err != nil {
		logger.WithError(err)
	}
}

func (h *Handler) authorized(ctx context.Context, tenant tenancy.Tenant, msg layout.Message, reason string, tokens devicetokens.Tokens) (devicetokens.Tokens, string) {
	var authorized devicetokens.Tokens
	skip := msg.GetSkipSAMLEnforcement()
	userID := int64(msg.GetUserId())
	orgID := int64(msg.GetSAMLOrganizationID())
	reasons := []string{reason}
	logger := h.telem.Logger.WithContext(ctx)

	username := ""
	for _, token := range tokens {
		oauthID := token.OauthAccessID
		result, err := h.policyChecker.CanDeliverPushNotification(ctx, tenant, userID, skip, orgID, oauthID, reasons)
		if err != nil {
			logger.WithError(err).Error("couldn't check policy")
			h.statter.Counter("delivery", ghstats.Tags{"status": "failed", "error_type": "policy_check"}, 1)
			continue
		}
		if username == "" {
			username = result.Login
		}
		if !result.IsDeliverable {
			logger.
				WithFields(
					kvp.String("gh.notifyd.reason", result.NotDeliverableReason),
					kvp.String("gh.notifyd.device_token", logs.Obfuscate(token.DeviceToken))).
				Info(
					"skipping notification delivery because not passed mobile push policy")
			h.statter.Counter("delivery", ghstats.Tags{"status": "skipped", "reason": result.NotDeliverableReason}, 1)
			continue
		}
		authorized = append(authorized, token)
	}
	return authorized, username
}

// Try to delete any unregistered tokens as described in
// https://firebase.google.com/docs/cloud-messaging/manage-tokens#detect-invalid-token-responses-from-the-fcm-backend
// It's ok if this fails.
func (h *Handler) unregister(ctx context.Context, userID int64, tokens devicetokens.Tokens) {
	if len(tokens) == 0 {
		return
	}

	success := "true"
	ts := make([]string, len(tokens))
	for i, token := range tokens {
		ts[i] = token.DeviceToken
	}
	if err := h.tokens.Delete(ctx, userID, ts...); err != nil {
		h.telem.Logger.WithContext(ctx).WithError(err).Error("error deleting unregistered device tokens")
		success = "false"
	}
	h.statter.Counter("mobile.unregister.count", ghstats.Tags{"success": success}, int64(len(ts)))
}

func enrichContext(ctx context.Context, msg *layout.Message) context.Context {
	ctx = o11y.CtxSetChannel(ctx, "mobile_push")
	ctx = o11y.CtxSetNotificationID(ctx, msg.NotificationId)
	ctx = o11y.CtxSetUserID(ctx, int64(msg.UserId))
	if tracking := msg.GetTracking(); tracking != nil && tracking.SubjectMetadata != nil {
		ctx = o11y.CtxSetListID(ctx, tracking.SubjectMetadata.ListId)
		ctx = o11y.CtxSetListType(ctx, tracking.SubjectMetadata.ListType)
		ctx = o11y.CtxSetThreadID(ctx, tracking.SubjectMetadata.ThreadId)
		ctx = o11y.CtxSetThreadType(ctx, tracking.SubjectMetadata.ThreadType)
		ctx = o11y.CtxSetCommentID(ctx, tracking.SubjectMetadata.CommentId)
		ctx = o11y.CtxSetCommentType(ctx, tracking.SubjectMetadata.CommentType)
	}
	reason, _ := msg.GetReasonAndType()
	ctx = o11y.CtxSetReasons(ctx, reason)
	return ctx
}
