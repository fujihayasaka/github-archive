package notify

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/notify/featureswitches"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

const maxBatchSize = 250

// Handler processes a Notify hydro message
type Handler struct {
	telem              *telemetry.Provider
	statter            stats.Client
	service            Service
	featureFlagsClient featureflags.Client
	batcher            notify.Batcher
}

// NewHandler creates a new Handler
func NewHandler(service Service, featureFlagsClient featureflags.Client, telem *telemetry.Provider, statter stats.Client) *Handler {
	return &Handler{
		service:            service,
		featureFlagsClient: featureFlagsClient,
		telem:              telem,
		statter:            statter,
		batcher:            notify.Batcher{Size: maxBatchSize},
	}
}

// Run handles a single Notify message
func (h *Handler) Run(ctx context.Context, tenant tenancy.Tenant, msg *schema_pb.Notify) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	logger := h.telem.Logger.WithContext(ctx)

	// convert proto message to internal message
	notification := notify.PBToNotification(msg)

	actorID := notification.ActorID
	shouldNotifyActor := featureswitches.IsEnabled(notification.FeatureSwitches, "notify_actor")
	shouldNotifySubscribers := featureswitches.IsEnabled(notification.FeatureSwitches, "notify_subscribers")

	// set up context and logger
	ctx = o11y.CtxSetNotificationID(ctx, notification.ID)
	ctx = o11y.CtxSetActorID(ctx, actorID)
	ctx = o11y.CtxSetSubjectType(ctx, notification.SubjectType)
	ctx = o11y.CtxSetSubjectValue(ctx, notification.SubjectValue)

	logger = logger.WithFields(
		kvp.Bool("gh.notifyd.featureswitch.notify_actor", shouldNotifyActor),
		kvp.Bool("gh.notifyd.featureswitch.notify_subscribers", shouldNotifySubscribers),
	)

	logger.Info("processing Notify message")

	recipients := notification.Recipients
	if shouldNotifySubscribers {
		err := h.service.AddSubscribers(ctx, recipients, notification)
		if err != nil {
			logger.WithError(err).Error("failed to calculate recipients")
			return errors.Wrap(err, "failed to calculate recipients").With(errors.MarkRetriable())
		}
	}

	if len(recipients) == 0 {
		logger.Info("skipped because no subscribers found")
		return nil
	}

	_, actorIsARecipient := recipients[actorID]
	if actorIsARecipient && !shouldNotifyActor {
		delete(recipients, actorID)
		logger.WithFields(kvp.Int64("gh.actor.id", actorID)).
			Info("skipping notification delivery because recipient matches the actor")
		h.statter.Counter("notify", stats.Tags{"status": "skipped", "reason": "actor_equals_recipient"}, 1)
	}

	if len(recipients) == 0 {
		logger.Info("skipped all recipients due to self mentions")
		return nil
	}

	if h.batcher.NumberOfBatches(recipients) > 1 {
		h.service.QueueBatchedRecipients(ctx, tenant, recipients, notification.Original(), h.batcher)
		logger.WithFields(kvp.Int("gh.notifyd.recipient_count", len(recipients))).
			Info("Recipients list has been re-queued in smaller batches")
		return nil
	}

	if err := h.service.RouteRecipients(ctx, tenant, recipients, notification); err != nil {
		return errors.Wrap(err, "error routing recipients")
	}

	return nil
}
