package notifier

import (
	"context"
	"strconv"
	"time"

	"github.com/github/authnd/internal/common/db"
	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/publisher"
	schema "github.com/github/authnd/internal/common/publisher/hydro/schemas/authnd/v0"
	"github.com/github/authnd/internal/common/store"
	"github.com/google/uuid"
	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/go-stats/ps"
)

const (
	revokedNotificationReason = "BackgroundJob"
)

// Unique ID for the life of this job. We can't use the pod ID since there can be multiple container
// restarts in the life of a single pod which would make isolating individual job runs difficult.
// Each new startup/container gets a unique uuid which is appended to the logs and sent through the
// Hydro event pipeline.
var JobID string

func init() {
	JobID = uuid.New().String()
}

// Job defines the Authnd Notifier Job
type Job struct {
	statsDuration time.Duration
	statter       stats.Client

	databaseProvider *db.Provider
	store            store.ProgrammaticAccessTokensStore
	publisher        publisher.PratEventPublisher
	isProxima        bool
}

// NewJob returns a new job for the given configuration.
func NewJob(ctx context.Context, cfg *Config) (*Job, error) {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	// TODO(chriskirkland): only require mysql1 and authnd-production schemas once we've made the store.Store support
	// a subset of schema connections.
	dbProvider, err := db.NewProvider(&cfg.CommonConfig, schemas.All(), logger, statter)
	if err != nil {
		return nil, err
	}

	sinkFn := publisher.WithDefaultSinkFn
	if cfg.KafkaDevelopmentEnv {
		logger.Info("starting kafka sink in development mode", kvp.String("messaging.system", "kafka"), kvp.String("messaging.dev_file", publisher.KafkaDevelopmentFile))
		sinkFn = publisher.WithDevelopmentSinkFn
	}

	eventPublisher, err := publisher.NewPratEventPublisher(ctx, &cfg.CommonConfig, sinkFn)
	if err != nil {
		return nil, err
	}

	var dbStore store.Store
	if cfg.IsProxima {
		dbStore, err = store.NewProximaStore(dbProvider)
		if err != nil {
			return nil, err
		}
	} else {
		dbStore, err = store.NewStore(dbProvider, cfg.IsEnterpriseServer)
		if err != nil {
			return nil, err
		}
	}

	return &Job{
		statsDuration:    cfg.StatsPeriod,
		statter:          statter,
		databaseProvider: dbProvider,
		store:            dbStore,
		publisher:        eventPublisher,
		isProxima:        cfg.IsProxima,
	}, nil
}

type workConfig struct {
	notificationName string
	lookupTokens     func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error)
	eventType        schema.ProgrammaticAccessEventEventType
	eventReason      string
}

// Run runs the service with the given context.
func (j *Job) Run(ctx context.Context) error {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	diagnostics.StartService(ctx)

	go func() {
		logger.Info("starting proc and db stats reporters")
		procStats := &ps.Reporter{Stats: statter}

		tick := time.NewTicker(j.statsDuration)
		defer tick.Stop()

		for {
			select {
			case <-tick.C:
				procStats.Report()
			case <-ctx.Done():
				return
			}
		}
	}()

	jobDone := make(chan bool)
	go func() {
		logger.Info("starting notifier job")

		var failed bool
		start := time.Now()
		defer func() {
			tags := stats.Tags{"success": strconv.FormatBool(!failed)}
			statter.DistributionMs("job.duration", tags, time.Since(start))
			jobDone <- true
		}()

		for _, cfg := range []workConfig{
			{
				notificationName: "revoked_token",
				lookupTokens:     j.store.FindProgrammaticAccessTokensForRevokedNotification,
				eventType:        schema.ProgrammaticAccessEvent_REVOKED,
				eventReason:      revokedNotificationReason,
			},
			{
				notificationName: "issued_token",
				lookupTokens:     j.store.FindProgrammaticAccessTokensForIssuedNotification,
				eventType:        schema.ProgrammaticAccessEvent_ISSUED,
			},
			{
				notificationName: "expired_token",
				lookupTokens:     j.store.FindProgrammaticAccessTokensForExpiredNotification,
				eventType:        schema.ProgrammaticAccessEvent_EXPIRED,
			},
			{
				notificationName: "one_day_expiration_warning",
				lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
					return j.store.FindProgrammaticAccessTokensForExpirationWarningNotification(ctx, 1, lastID, batchSize)
				},
				eventType:   schema.ProgrammaticAccessEvent_EXPIRATION_WARNING,
				eventReason: "1d",
			},
			{
				notificationName: "seven_day_expiration_warning",
				lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
					return j.store.FindProgrammaticAccessTokensForExpirationWarningNotification(ctx, 7, lastID, batchSize)
				},
				eventType:   schema.ProgrammaticAccessEvent_EXPIRATION_WARNING,
				eventReason: "7d",
			},
		} {
			w := newWork(cfg.lookupTokens, cfg.eventType, cfg.eventReason, j.publisher, j.store, j.isProxima)

			// add the notification name to the downstream logs + stats
			wCtx := diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.notifier.name", cfg.notificationName))
			wCtx = diagnostics.WithStatterTags(wCtx, stats.Tags{"notification": cfg.notificationName})

			err := w.Do(wCtx)
			if err != nil {
				logger.WithError(err).Error("Error processing token event work")
				failed = true
				return
			}
		}
		logger.Info("all work completed", kvp.Duration("gh.authnd.notifier.job.duration", time.Since(start)))
	}()

	select {
	case <-ctx.Done():
		logger.Info("shutdown requested")
	case <-jobDone:
		logger.Info("job processing complete")
	}

	// Use a new context with a 5s timeout to shutdown.
	// Shutdown will immediately stop new requests and give existing requests until the provided context terminates to complete.
	// If we give it the context that just terminated, we cancel existing requests immediately!
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	logger.Info("shutting down")
	shutdownErr := j.stop(ctx)

	// Log shutdown errors, but don't report them to Sentry
	if shutdownErr != nil {
		logger.WithError(shutdownErr).Error("shutdown error")
		statter.Counter("service.stop.error", nil, 1)
	}

	// flush statistics
	statter.Stop()
	return nil
}

// stop shutdowns the server and closes all underlying connections (if any)
func (j *Job) stop(ctx context.Context) error {
	var errs diagnostics.MultiError
	statter := diagnostics.Statter(ctx)

	diagnostics.Logger(ctx).Info("shutting down authnd notifier job...")
	statter.Counter("service.stop", nil, 1)

	// close kafka producer connection
	if err := j.publisher.Close(); err != nil {
		errs = append(errs, errors.WithStack(err))
	}

	if err := j.databaseProvider.Close(); err != nil {
		errs = append(errs, errors.WithStack(err))
	}

	return errs.ErrorOrNil()
}
