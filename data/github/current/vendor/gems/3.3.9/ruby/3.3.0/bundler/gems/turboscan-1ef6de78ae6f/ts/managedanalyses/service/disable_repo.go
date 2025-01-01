package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/pkg/errors"
)

func (ma *ManagedAnalyses) DisableRepo(ctx context.Context, repoID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		if errors.Is(err, ts.ErrCodeqlRepoNotFound) {
			appctx.Logger(ctx).Info("repo is already disabled", repoID.AsKVP())
			return ts.ErrNoChangeRequired
		}
		return errors.Wrap(err, "failed to get CodeqlRepo")
	}

	if codeqlRepo.IsOnboarded() || codeqlRepo.IsOnboarding() {
		err := ma.OffboardRepo(ctx, repoID)
		if err != nil {
			return errors.Wrap(err, "failed to offboard repo")
		}
	}

	err = ma.DataService.DeleteCodeqlRepo(ctx, codeqlRepo.RepositoryID)
	if err != nil {
		return errors.Wrap(err, "failed to disable managed analysis")
	}

	fls := false
	ma.EnabledStatusService.PublishStatusIfChanged(ctx, repoID, ts.EnablementReason_DISABLE_DEFAULT_SETUP, nil, &fls)

	return nil
}
