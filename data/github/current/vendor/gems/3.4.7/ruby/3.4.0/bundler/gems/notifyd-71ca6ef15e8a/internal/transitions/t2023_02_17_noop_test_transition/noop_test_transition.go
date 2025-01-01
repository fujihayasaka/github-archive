package t2023_02_17_noop_test_transition //nolint:revive,stylecheck // allow underscores

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/pagination"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

// NoopTestTransition implements a simple test transition
type NoopTestTransition struct {
	telem              *telemetry.Provider
	routingSettingsSvc routing.SettingsService
	subscriptionsSvc   subscriptions.Service
}

// NewNoopTestTransition returns a NoopTestTransition
func NewNoopTestTransition(
	telem *telemetry.Provider,
	routingSettingsSvc routing.SettingsService,
	subscriptionsSvc subscriptions.Service,
) *NoopTestTransition {
	return &NoopTestTransition{
		telem:              telem,
		routingSettingsSvc: routingSettingsSvc,
		subscriptionsSvc:   subscriptionsSvc}
}

// Run implements the transition interface
func (t *NoopTestTransition) Run(ctx context.Context, isDryRun bool) error {
	logger := t.telem.Logger.WithContext(ctx)
	logger.Info("starting transition")

	settings, _, err := t.routingSettingsSvc.GetSettingsForUsers(ctx, userIDs, nil, pagination.NewStandardFirstPage())
	if err != nil {
		return err
	}
	logger.WithFields(
		kvp.Int("gh.notifyd.routing_settings.count", len(settings)),
	).Info("retrieved routing settings")
	for _, userID := range userIDs {
		subs, _, err := t.subscriptionsSvc.GetSubscriptionsForUser(ctx, userID, []subscriptions.CustomField{}, pagination.NewStandardFirstPage())
		if err != nil {
			return err
		}
		logger.WithFields(
			kvp.Int("gh.notifyd.subscriptions.count", len(subs)),
			kvp.Int64("gh.user.id", userID),
		).Info("retrieved subscriptions")
	}

	// TODO: we could introduced something here that is also test writing to a
	// table when `dryRun` is false. But we'd need a safe table to write to
	// first.

	logger.Info("successfully ran noop transition")
	return nil
}
