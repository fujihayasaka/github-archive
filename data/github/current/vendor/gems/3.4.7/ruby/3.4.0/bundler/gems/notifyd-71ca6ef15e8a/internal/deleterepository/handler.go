package deleterepository

import (
	"context"
	"strconv"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	ghstats "github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pagination"
	"github.com/github/notifyd/internal/pkg/routing"
	subscriptionspkg "github.com/github/notifyd/internal/pkg/subscriptions"
)

const (
	statsKey       = "maintenance.deleterepository"
	statsTimingKey = "maintenance.deleterepository.time"
)

// Handler is a struct containing dependencies for the handler
type Handler struct {
	clock         clockpkg.Clock
	telem         *telemetry.Provider
	statter       ghstats.Client
	subscriptions subscriptionspkg.Service
	settings      routing.SettingsService
}

// NewHandler creates a new Handler
func NewHandler(
	clock clockpkg.Clock,
	telem *telemetry.Provider,
	statter ghstats.Client,
	subscriptions subscriptionspkg.Service,
	settings routing.SettingsService) *Handler {
	return &Handler{
		clock:         clock,
		telem:         telem,
		statter:       statter,
		subscriptions: subscriptions,
		settings:      settings,
	}
}

// Run runs the handler
func (h *Handler) Run(ctx context.Context, repoID int64) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	startTime := h.clock.Now()
	ctx = o11y.CtxSetPackage(ctx, "deleterepository")
	ctx = o11y.CtxSetMethod(ctx, "run")
	logger := h.telem.Logger.WithContext(ctx).WithFields(kvp.Int64("gh.repo.id", repoID))
	logger.Info("starting a run")

	repositoryID := strconv.FormatInt(repoID, 10)

	// deal with subscriptions
	subscriptionFields := []subscriptionspkg.CustomField{
		{Name: "repository_id", Value: repositoryID},
		{Name: "watcher_scenario", Value: "true"},
	}
	for {
		subs, p, err := h.subscriptions.GetSubscriptions(ctx, subscriptionFields, pagination.NewStandardFirstPage())
		if err != nil {
			h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "subscriptions_fetch"}, 1)
			logger.WithError(err).Error("failed to fetch subscriptions")
			return errors.Wrap(err, "failed to fetch subscriptions").With(errors.MarkRetriable())
		}

		for _, sub := range subs {
			if err := h.subscriptions.Delete(ctx, sub.UserID, subscriptionFields); err != nil {
				h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "subscriptions_replace"}, 1)
				logger.WithError(err).Error("failed to delete subscriptions")
				return errors.Wrap(err, "failed to delete subscriptions").With(errors.MarkRetriable())
			}
		}

		if !p.ReturnNextCursor() {
			break
		}
	}

	// deal with (routing) settings
	routingFields := []routing.CustomField{
		{Name: "repository_id", Value: repositoryID},
		{Name: "watcher_scenario", Value: "true"},
	}
	for {
		settings, p, err := h.settings.GetSettings(ctx, routingFields, pagination.NewStandardFirstPage())
		if err != nil {
			h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "settings_fetch"}, 1)
			logger.WithError(err).Error("failed to fetch settings")
			return errors.Wrap(err, "failed to fetch settings").With(errors.MarkRetriable())
		}

		for _, setting := range settings {
			if err := h.settings.Delete(ctx, setting.UserID, routingFields); err != nil {
				h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "settings_replace"}, 1)
				logger.WithError(err).Error("failed to delete settings")
				return errors.Wrap(err, "failed to delete settings").With(errors.MarkRetriable())
			}
		}

		if !p.ReturnNextCursor() {
			break
		}
	}

	elapsed := h.clock.Since(startTime)
	h.statter.DistributionMs(statsTimingKey, nil, elapsed)
	h.statter.Counter(statsKey, ghstats.Tags{"status": "success"}, 1)
	logger.WithFields(kvp.Duration("gh.duration_ms", elapsed)).Info("finished the run")
	return nil
}
