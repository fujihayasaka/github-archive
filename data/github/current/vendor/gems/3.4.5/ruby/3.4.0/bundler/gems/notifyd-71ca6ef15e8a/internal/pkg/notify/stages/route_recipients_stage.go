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
	"github.com/github/notifyd/internal/pkg/tenancy"
)

type routeRecipientsStage struct {
	authorizeRecipientsStage             IAuthorizeRecipientsStage
	routeRecipientsToChannelsStage       IRouteRecipientsToChannelsStage
	schedulePushNotificationsStage       NotificationsScheduler
	scheduleEmailNotificationsStage      NotificationsScheduler
	scheduleWebNotificationsStage        NotificationsScheduler
	validateDotcomRecipientPoliciesStage IValidateDotcomRecipientPoliciesStage
	clock                                clockpkg.Clock
	telem                                *telemetry.Provider
	statter                              stats.Client
	featureFlagsClient                   featureflags.Client
}

// NewRouteRecipientsStage creates a new route recipients stage.
func NewRouteRecipientsStage(
	authorizeRecipientsStage IAuthorizeRecipientsStage,
	routeRecipientsToChannelsStage IRouteRecipientsToChannelsStage,
	schedulePushNotificationsStage,
	scheduleEmailNotificationsStage,
	scheduleWebNotificationsStage NotificationsScheduler,
	validateDotcomRecipientPoliciesStage IValidateDotcomRecipientPoliciesStage,
	clock clockpkg.Clock,
	telem *telemetry.Provider,
	statter stats.Client,
	featureFlagsClient featureflags.Client,
) IRouteRecipientsStage {
	return &routeRecipientsStage{
		authorizeRecipientsStage:             authorizeRecipientsStage,
		routeRecipientsToChannelsStage:       routeRecipientsToChannelsStage,
		schedulePushNotificationsStage:       schedulePushNotificationsStage,
		scheduleEmailNotificationsStage:      scheduleEmailNotificationsStage,
		scheduleWebNotificationsStage:        scheduleWebNotificationsStage,
		validateDotcomRecipientPoliciesStage: validateDotcomRecipientPoliciesStage,
		clock:                                clock,
		telem:                                telem,
		statter:                              statter,
		featureFlagsClient:                   featureFlagsClient,
	}
}

// RouteRecipients routes recipients.
func (s *routeRecipientsStage) RouteRecipients(ctx context.Context, tenant tenancy.Tenant, recipients notify.RecipientIDToReasons, msg *notify.Notification) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	logger := s.telem.Logger.WithContext(ctx)

	var validatedRecipients notify.RecipientIDToReasons
	logger = logger.WithFields(kvp.Int("gh.notifyd.policies.version", 2))
	authorized, err := s.authorizeRecipientsStage.AuthorizeRecipients(ctx, tenant, recipients, msg)
	if err != nil {
		s.statter.Counter("delivery", stats.Tags{"type": "notify", "status": "failed", "reason": "checking_policies_v2"}, 1)
		logger.WithError(err).Error("failed to authorize recipients")
		return errors.Wrap(err, "authorizing recipients").With(errors.MarkRetriable())
	}

	if len(authorized) == 0 {
		s.statter.Counter("delivery", stats.Tags{"type": "notify", "status": "skipped", "reason": "authorization"}, 1)
		logger.Info("skipped all recipients due to authorization")
		return nil
	}

	validated, err := s.validateDotcomRecipientPoliciesStage.ValidateIgnoredRepository(ctx, tenant, authorized, msg)
	if err != nil {
		s.statter.Counter("delivery", stats.Tags{"type": "notify", "status": "failed", "reason": "checking_repository_ignore"}, 1)
		logger.WithError(err).Error("failed to validate ignored repository")
		return errors.Wrap(err, "error checking ignored repository")
	}

	if len(validated) == 0 {
		s.statter.Counter("delivery", stats.Tags{"type": "notify", "status": "skipped", "reason": "ignored_repository"}, 1)
		logger.Info("skipped all recipients due to ignored repository")
		return nil
	}

	validatedRecipients = validated

	// collect required channels per recipient
	recipientsWithDeliveryMetadata := s.routeRecipientsToChannelsStage.RouteRecipientsToChannels(ctx, validatedRecipients, msg)

	logger.WithFields(kvp.Int("gh.notifyd.notifications.ready_count", len(recipientsWithDeliveryMetadata))).
		Info("publishing deliver events")

	// schedule all notifications
	if err := s.scheduleWebNotificationsStage.ScheduleNotifications(ctx, tenant, recipientsWithDeliveryMetadata, msg); err != nil {
		logger.WithError(err).Error("Could not schedule web notifications")
		return errors.Wrap(err, "error scheduling web notifications")
	}
	if err := s.scheduleEmailNotificationsStage.ScheduleNotifications(ctx, tenant, recipientsWithDeliveryMetadata, msg); err != nil {
		logger.WithError(err).Error("Could not schedule email notifications")
		return errors.Wrap(err, "error scheduling email notifications")
	}
	if err := s.schedulePushNotificationsStage.ScheduleNotifications(ctx, tenant, recipientsWithDeliveryMetadata, msg); err != nil {
		logger.WithError(err).Error("Could not schedule push notifications")
		return errors.Wrap(err, "error scheduling push notifications")
	}
	logger.Info("successfully published notification events")
	s.statter.Counter("delivery", stats.Tags{"type": "notify", "status": "succeeded"}, 1)

	return nil
}
