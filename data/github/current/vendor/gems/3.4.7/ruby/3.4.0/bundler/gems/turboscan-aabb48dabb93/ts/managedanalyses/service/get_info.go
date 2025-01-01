package managedanalyses

import (
	"context"
	"time"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/o11y"
	"github.com/pkg/errors"
)

// GetInfo returns information about a repository's Managed Analysis status.
// This includes both the Latest and Stable CodeqlConfigs for the repository.
func (ma *ManagedAnalyses) GetInfo(ctx context.Context, repoID ts.RepositoryEID) (*ts.CodeqlRepo, *time.Time, bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return nil, nil, false, errors.Wrap(err, "failed to fetch configuration")
	}

	if codeqlRepo.CurrentConfig != nil {
		run, err := ma.DataService.GetMostRecentCodeqlRun(ctx, repoID, codeqlRepo.CurrentConfig)
		if err != nil {
			return nil, nil, false, errors.Wrap(err, "failed to fetch latest run")
		}
		codeqlRepo.CurrentConfig.LatestRun = run
	}

	if codeqlRepo.DebuggableConfig() != nil {
		run, err := ma.DataService.GetMostRecentCodeqlRun(ctx, repoID, codeqlRepo.DebuggableConfig())
		if err != nil {
			return nil, nil, false, errors.Wrap(err, "failed to fetch latest run")
		}
		codeqlRepo.DebuggableConfig().LatestRun = run
	}

	var nextRunAt *time.Time
	isRepoActive := false
	if codeqlRepo.IsOnboarded() {
		nra, err := ma.DataService.GetNextScheduledRunTime(ctx, repoID)
		if errors.Is(err, managedanalysis.ErrScheduleNotFound) {
			// Once the FF is on, there should always be an schedule, if not we should error
			// As we cannot check the FF because we don't have an orgID in scope, we cannot error yet
			// TODO: error here when the on:schedule FF is removed
			return codeqlRepo, nil, false, nil
		} else if err != nil {
			return nil, nil, false, errors.Wrap(err, "failed to fetch the schedule")
		}
		nextRunAt = &nra

		repoIDs := []ts.RepositoryEID{repoID}
		areReposActive, err := ma.areReposActive(ctx, repoIDs)
		if err != nil {
			return nil, nil, false, errors.Wrap(err, "failed to check which repos are active")
		}
		isRepoActive = areReposActive[repoID]
	}

	return codeqlRepo, nextRunAt, isRepoActive, nil
}
