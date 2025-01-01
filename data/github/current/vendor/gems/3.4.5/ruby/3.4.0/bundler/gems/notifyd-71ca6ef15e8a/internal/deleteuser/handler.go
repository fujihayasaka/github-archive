package deleteuser

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	ghstats "github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pagination"
	"github.com/github/notifyd/internal/pkg/routing"
	subscriptionspkg "github.com/github/notifyd/internal/pkg/subscriptions"
)

const (
	statsKey       = "maintenance.deleteuser"
	statsTimingKey = "maintenance.deleteuser.time"
)

// Handler is a struct containing dependencies for the handler
type Handler struct {
	clock         clockpkg.Clock
	telem         *telemetry.Provider
	statter       ghstats.Client
	subscriptions subscriptionspkg.Service
	settings      routing.SettingsService
	tokens        devicetokens.Storage
}

// NewHandler creates a new Handler
func NewHandler(
	clock clockpkg.Clock,
	telem *telemetry.Provider,
	statter ghstats.Client,
	subscriptions subscriptionspkg.Service,
	settings routing.SettingsService,
	tokens devicetokens.Storage,
) *Handler {
	return &Handler{
		clock:         clock,
		telem:         telem,
		statter:       statter,
		subscriptions: subscriptions,
		settings:      settings,
		tokens:        tokens,
	}
}

// Run runs the handler
func (h *Handler) Run(ctx context.Context, userID int64) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "deleteuser")
	ctx = o11y.CtxSetMethod(ctx, "run")
	ctx = o11y.CtxSetUserID(ctx, userID)
	logger := h.telem.Logger.WithContext(ctx)
	logger.Info("starting a run")
	t0 := h.clock.Now()

	if err := h.run(ctx, userID); err != nil {
		// all errors from the handler are retriable
		logger.WithError(err).Error("failed to run deleteuser")
		return errors.Wrap(err, "failed to run deleteuser").With(errors.MarkRetriable())
	}

	elapsed := h.clock.Since(t0)
	h.statter.DistributionMs(statsTimingKey, nil, elapsed)
	h.statter.Counter(statsKey, ghstats.Tags{"status": "success"}, 1)
	logger.WithFields(kvp.Duration("gh.duration_ms", elapsed)).Info("finished the run")
	return nil
}

func (h *Handler) run(ctx context.Context, userID int64) error {
	// deal with subscriptions
	subscriptionFields := []subscriptionspkg.CustomField{
		{Name: "watcher_scenario", Value: "true"},
	}
	for {
		subs, p, err := h.subscriptions.GetSubscriptionsForUser(ctx, userID, subscriptionFields, pagination.NewStandardFirstPage())
		if err != nil {
			h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "subscriptions_fetch"}, 1)
			return errors.Wrap(err, "failed to fetch subscriptions")
		}

		for _, sub := range subs {
			if err := h.subscriptions.Delete(ctx, userID, sub.Details.CustomFields); err != nil {
				h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "subscriptions_delete"}, 1)
				return errors.Wrap(err, "failed to delete subscriptions")
			}
		}

		if !p.ReturnNextCursor() {
			break
		}
	}

	// deal with (routing) settings
	routingFields := []routing.CustomField{
		{Name: "watcher_scenario", Value: "true"},
	}
	for {
		settings, p, err := h.settings.GetSettingsForUsers(ctx, []int64{userID}, routingFields, pagination.NewStandardFirstPage())
		if err != nil {
			h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "settings_fetch"}, 1)
			return errors.Wrap(err, "failed to fetch settings")
		}

		for _, setting := range settings {
			if err := h.settings.Delete(ctx, userID, setting.Details.CustomFields); err != nil {
				h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "settings_delete"}, 1)
				return errors.Wrap(err, "failed to delete settings")
			}
		}

		if !p.ReturnNextCursor() {
			break
		}
	}

	if err := h.tokens.DeleteAll(ctx, userID); err != nil {
		h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "tokens_delete"}, 1)
		return errors.Wrap(err, "failed to delete mobile device tokens")
	}

	return nil
}
