package managedanalyses

import (
	"context"
	"time"

	"github.com/SamuelTissot/sqltime"

	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"

	ma_ "github.com/github/turboscan/ts/managedanalyses"
	"github.com/pkg/errors"
)

func (ma *ManagedAnalyses) RunOnSchedule(ctx context.Context, repoDB RepositoryDB) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("RunOnSchedule is starting...")
	bot, err := ma.GetBotActor(ctx)
	if err != nil {
		return errors.Wrap(err, "could not get bot actor")
	}

	schedules, err := ma.DataService.GetRunnableCodeqlSchedules(ctx)
	if err != nil {
		return errors.Wrap(err, "could not read pending codeql schedules")
	}

	appctx.Stats(ctx).Counter("run_on_schedule.runnableSchedules", stats.Tags{}, int64(len(schedules)))

	repoIDs := make([]ts.RepositoryEID, 0, len(schedules))
	for _, schedule := range schedules {
		repoIDs = append(repoIDs, schedule.RepositoryID)
	}

	isActive, err := ma.areReposActive(ctx, repoIDs)
	if err != nil {
		return errors.Wrap(err, "failed to check which repos are active")
	}

	for _, schedule := range schedules {
		start := time.Now()
		if ctx.Err() != nil {
			return ctx.Err()
		}

		ctx := appctx.With(ctx, schedule.RepositoryID.AsKVP())

		wrapErrorWithRepoID := func(err error, msg string) error {
			return o11y.AnnotateError(errors.Wrap(err, msg), schedule.RepositoryID.AsKVP())
		}

		if !isActive[schedule.RepositoryID] {
			appctx.Logger(ctx).Info("Skipping schedule for dormant repository")
			appctx.Stats(ctx).Counter("run_on_schedule.dormant_repo", stats.Tags{}, 1)
			err = bumpNextRunAt(ctx, ma.DataService, schedule)
			if err != nil {
				return wrapErrorWithRepoID(err, "failed to update the codeql schedule")
			}
			continue
		}

		repo, err := repoDB.Find(ctx, schedule.RepositoryID)
		if err != nil {
			return wrapErrorWithRepoID(err, "failed to find repository")
		}
		if repo == nil {
			appctx.Logger(ctx).Error("repository not found")
			continue
		}

		config, tenant, codeqlPacks, err := ma.RequireRunnableCodeqlConfig(ctx, schedule.RepositoryID)
		if err != nil {
			switch {
			case errors.Is(err, ts.ErrCodeqlRepoNotFound):
				appctx.Logger(ctx).Info("Managed analyses disabled for repository")
				continue
			case errors.Is(err, ts.ErrNotOnboarded):
				appctx.Logger(ctx).Info("Managed analyses is not enabled for this repository")
				continue
			case errors.Is(err, ErrRequiredServicesNotEnabled):
				appctx.Logger(ctx).Info("Required services are not enabled")
				err = bumpNextRunAt(ctx, ma.DataService, schedule)
				if err != nil {
					return wrapErrorWithRepoID(err, "failed to update the codeql schedule")
				}
				continue
			case errors.Is(err, ts.ErrRepoNotFound):
				appctx.Logger(ctx).Info("Repository was not found on gh/gh. Disabling managed analyses for this repository")
				err = ma.DisableRepo(ctx, schedule.RepositoryID)
				if err != nil {
					return wrapErrorWithRepoID(err, "failed to disable the repository")
				}
				continue
			default:
				return wrapErrorWithRepoID(err, "failed to get runnable codeql config")
			}
		}
		// Inject the tenant info into the context so that the LaunchApiClient can use it
		if tenant != nil {
			ctx = appctx.WithTenant(ctx, tenant)
		}

		appctx.Stats(ctx).DistributionMs("run_on_schedule.lag", stats.Tags{}, time.Since(schedule.NextRunAt.Time))

		// We do not know the SHA here, so we pass the EmptySHA and will let launch resolve it
		run, err := config.NewRun(bot, repo.DefaultRef, ts.EmptySha, ts.CodeqlRunTriggeringEvent_SCHEDULED, true, repo.OwnerID, codeqlPacks, gormext.ConvertTime(&start))
		if err != nil {
			return wrapErrorWithRepoID(err, "failed to build new run")
		}

		err = ma.LaunchApiClient.RunDynamicWorkflow(ctx, run)
		if err != nil {
			appctx.Logger(ctx).Error("failed to submit dynamic workflow")

			if errors.Is(err, ts.ErrCouldNotResolveRef) {
				// no need to retry this failure
				appctx.Logger(ctx).Info("failed to resolve ref ", run.Ref.AsKVP())
				appctx.Stats(ctx).Counter("run_on_schedule.failed_to_resolve_ref", stats.Tags{}, 1)

				err = bumpNextRunAt(ctx, ma.DataService, schedule)
				if err != nil {
					return wrapErrorWithRepoID(err, "failed to update the codeql schedule")
				}
				continue
			}

			// This should never happen because the actor is the github-advanced-security
			// bot. But it makes sense to be consistently conservative in our error-handling.
			if errors.Is(err, ts.ErrSpammyUser) {
				// no need to retry this failure
				err = bumpNextRunAt(ctx, ma.DataService, schedule)
				if err != nil {
					return wrapErrorWithRepoID(err, "failed to update the codeql schedule")
				}
				continue
			}

			return wrapErrorWithRepoID(err, "failed to submit dynamic workflow")
		}
		ma_.DynamicWorkflowRunLogAndStats(ctx, config, run)

		err = ma.DataService.CreateCodeqlRun(ctx, run)
		if err != nil {
			// We do not act on this error since everything else should still work and we do not want to retry the run
			// and spend customer's Actions minutes on a rerun.
			appctx.Logger(ctx).Info("failed to create an entry for ts_codeql_run after submitting dynamic workflow")
		}

		err = bumpNextRunAt(ctx, ma.DataService, schedule)
		if err != nil {
			return wrapErrorWithRepoID(err, "failed to update the codeql schedule")
		}

		appctx.Stats(ctx).Counter("run_on_schedule.repo_processed", stats.Tags{}, 1)
		appctx.Stats(ctx).DistributionMs("run_on_schedule.processing_time", nil, time.Since(start))
	}

	return nil
}

func bumpNextRunAt(ctx context.Context, db ma_.CodeqlDB, schedule ts.CodeqlSchedule) error {
	schedule.NextRunAt = sqltime.Time{Time: ma_.GetNextScheduleTime(schedule.NextRunAt.Time)}
	return db.UpdateCodeqlSchedule(ctx, schedule)
}

type RepositoryDB interface {
	Find(ctx context.Context, repositoryID ts.RepositoryEID) (*ts.Repository, error)
}
