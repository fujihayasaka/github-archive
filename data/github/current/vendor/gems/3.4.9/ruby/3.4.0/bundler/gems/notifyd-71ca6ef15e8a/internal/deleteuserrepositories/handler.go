package deleteuserrepositories

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
	"github.com/github/notifyd/internal/pkg/routing"
	subscriptionspkg "github.com/github/notifyd/internal/pkg/subscriptions"
)

const (
	statsKey              = "maintenance.deleteuserrepositories"
	statsTimingKey        = "maintenance.deleteuserrepositories.time"
	statsRepoIDsLengthKey = "maintenance.deleteuserrepositories.repository_ids.length"
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
	settings routing.SettingsService,
) *Handler {
	return &Handler{
		clock:         clock,
		telem:         telem,
		statter:       statter,
		subscriptions: subscriptions,
		settings:      settings,
	}
}

// Run runs the handler
func (h *Handler) Run(ctx context.Context, userID int64, repoIDs []int64) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	if err := h.run(ctx, userID, repoIDs); err != nil {
		// all errors from the handler are retriable
		return errors.Wrap(err, "failed to run deleteuserrepositories").With(errors.MarkRetriable())
	}
	return nil
}

func (h *Handler) run(ctx context.Context, userID int64, repoIDs []int64) error {
	startTime := h.clock.Now()
	repoIDsLength := len(repoIDs)
	ctx = o11y.CtxSetPackage(ctx, "deleteuserrepositories")
	ctx = o11y.CtxSetMethod(ctx, "run")
	logger := h.telem.Logger.WithContext(ctx).WithFields(
		kvp.Int64("gh.user.id", userID),
		kvp.Int("gh.notifyd.repo.ids.count", repoIDsLength),
		kvp.Any("gh.notifyd.repo.ids", repoIDs))
	logger.Info("starting a run")
	h.statter.Distribution(statsRepoIDsLengthKey, ghstats.Tags{}, float64(repoIDsLength))

	// loop through all repos
	for _, repoID := range repoIDs {
		repoIDString := strconv.FormatInt(repoID, 10)

		// deal with subscriptions
		subscriptionFields := []subscriptionspkg.CustomField{
			{Name: "repository_id", Value: repoIDString},
			{Name: "watcher_scenario", Value: "true"},
		}
		if err := h.subscriptions.Delete(ctx, userID, subscriptionFields); err != nil {
			h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "subscriptions_replace"}, 1)
			logger.WithError(err).Error("failed to delete subscriptions")
			return err
		}

		// deal with (routing) settings
		routingFields := []routing.CustomField{
			{Name: "repository_id", Value: repoIDString},
			{Name: "watcher_scenario", Value: "true"},
		}
		if err := h.settings.Delete(ctx, userID, routingFields); err != nil {
			h.statter.Counter(statsKey, ghstats.Tags{"status": "failed", "error_type": "settings_replace"}, 1)
			logger.WithError(err).Error("failed to delete settings")
			return err
		}
	}

	elapsed := h.clock.Since(startTime)
	h.statter.DistributionMs(statsTimingKey, nil, elapsed)
	h.statter.Counter(statsKey, ghstats.Tags{"status": "success"}, 1)
	logger.WithFields(kvp.Duration("gh.duration_ms", elapsed)).Info("finished the run")
	return nil
}
