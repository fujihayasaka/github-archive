package t2023_31_12_cleanup_list_subscription_users //nolint:revive,stylecheck // allow underscores

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/api/newsiesservice"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

// CleanupListSubscriptions represents a transition that cleans up subscriptions.
type CleanupListSubscriptions struct {
	telem              *telemetry.Provider
	routingSettingsSvc routing.SettingsService
	subscriptionsSvc   subscriptions.Service
}

// NewCleanupListSubscriptions creates a new instance of the transition.
func NewCleanupListSubscriptions(
	telem *telemetry.Provider,
	routingSettingsSvc routing.SettingsService,
	subscriptionsSvc subscriptions.Service,
) *CleanupListSubscriptions {
	return &CleanupListSubscriptions{telem: telem, routingSettingsSvc: routingSettingsSvc, subscriptionsSvc: subscriptionsSvc}
}

// Run runs the transition.
func (t *CleanupListSubscriptions) Run(ctx context.Context, isDryRun bool) error {
	logger := t.telem.Logger.WithContext(ctx)
	logger.Info("starting transition")

	for _, userID := range staffUsersToCleanup {
		logger = logger.WithFields(kvp.Int64("gh.user.id", userID))

		logger.Info("cleaning subscriptions up")
		_, err := t.subscriptionsSvc.BatchReplace(ctx, userID, []*subscriptions.MetaSubscription{}, []subscriptions.CustomField{
			{Name: newsiesservice.WatcherScenarioName, Value: "true"},
		})

		if err != nil {
			logger.WithError(err).Error("error cleaning up user")
			return err
		}
		logger.Info("cleaning up success - subscriptions")

		logger.Info("cleaning up routing settings")

		_, err = t.routingSettingsSvc.BatchReplace(ctx, userID, []*routing.MetaSetting{}, []routing.CustomField{
			{Name: newsiesservice.WatcherScenarioName, Value: "true"},
		})

		if err != nil {
			logger.WithError(err).Error("error cleaning up")
			return err
		}
		logger.Info("cleaning up success - routing settings")
	}

	return nil
}
