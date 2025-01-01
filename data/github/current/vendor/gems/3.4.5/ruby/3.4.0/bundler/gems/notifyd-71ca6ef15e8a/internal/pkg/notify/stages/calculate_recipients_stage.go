package stages

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

type calculateRecipientsStage struct {
	subscriptionsService subscriptions.Service
	clock                clockpkg.Clock
	telem                *telemetry.Provider
	statter              stats.Client
	featureFlagsClient   featureflags.Client
}

// NewCalculateRecipientsStage creates a new calculate recipients stage.
func NewCalculateRecipientsStage(
	subscriptionsService subscriptions.Service,
	clock clockpkg.Clock,
	telem *telemetry.Provider,
	statter stats.Client,
	featureFlagsClient featureflags.Client) ICalculateRecipientsStage {
	return &calculateRecipientsStage{
		subscriptionsService: subscriptionsService,
		clock:                clock,
		telem:                telem,
		statter:              statter,
		featureFlagsClient:   featureFlagsClient,
	}
}

// AddSubscribers adds subscribers.
func (s *calculateRecipientsStage) AddSubscribers(ctx context.Context, recipientIDsToReasons notify.RecipientIDToReasons, msg *notify.Notification) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	start := s.clock.Now()
	defer func() {
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "calculate_recipients"}, s.clock.Since(start))
	}()

	subscriberIDsToReasons, err := s.appendSubscribers(ctx, msg, recipientIDsToReasons)
	if err != nil {
		return errors.Wrap(err, "appending subscribers to recipients")
	}
	s.telem.Logger.WithContext(ctx).WithFields(kvp.Int("gh.notifyd.subscribers_count", len(subscriberIDsToReasons))).Info("read subscribers")
	return nil
}

func (s *calculateRecipientsStage) appendSubscribers(ctx context.Context, msg *notify.Notification, recipientIDsToReasons notify.RecipientIDToReasons) (notify.RecipientIDToReasons, error) {
	if err := msg.Matchable(); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Info("data from the message wasn't valid to match subscriptions")
		// fail gracefully and return empty subscriptions set if needed fields are not provided
		return notify.RecipientIDToReasons{}, nil
	}

	subscriberIDsToReasons, err := s.subscriptionsService.GetRecipientsWithReasons(ctx, msg.MessageMatchFields)
	if err != nil {
		return nil, errors.Wrap(err, "fetching subscribers").With(errors.MarkRetriable())
	}

	for subscriberID, reasons := range subscriberIDsToReasons {
		if subscriberID == msg.ActorID {
			s.telem.Logger.WithContext(ctx).WithFields(kvp.Int64("gh.user.id", subscriberID)).
				Info("skipping notification delivery because subscriber matches the actor")
			s.statter.Counter("notify", stats.Tags{"status": "skipped", "reason": "actor_equals_recipient"}, 1)
			continue
		}
		recipientIDsToReasons[subscriberID] = append(recipientIDsToReasons[subscriberID], reasons...)
	}

	return subscriberIDsToReasons, nil
}
