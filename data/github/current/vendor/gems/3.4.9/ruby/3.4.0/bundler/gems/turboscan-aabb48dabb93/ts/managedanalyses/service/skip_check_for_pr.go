package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/ts"

	"github.com/pkg/errors"
)

// SkipCheckForPR asks gh/gh to mark the Code Scanning check for the given pull request as skipped.
func (ma *ManagedAnalyses) SkipCheckForPR(ctx context.Context, repoID ts.RepositoryEID, pullRequestID uint64) error {
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		if errors.Is(err, ts.ErrCodeqlRepoNotFound) {
			// Repo is not enabled. This is a no-op.
			return nil
		}
		return errors.Wrap(err, "checking for repo config")
	}
	if !codeqlRepo.IsOnboarded() {
		// Repo has been offboarded. This is a no-op.
		return nil
	}
	err = ma.GitHubTwirpApiClient.SkipCheckForPR(ctx, repoID, pullRequestID)
	if errors.Is(err, ts.ErrGHASDisabled) {
		// Offboard the repo because GHAS has been disabled
		appctx.Logger(ctx).Info("Disabling code scanning for repo because GHAS has been disabled", repoID.AsKVP())
		err = ma.OffboardRepo(ctx, repoID)
		if errors.Is(err, ts.ErrNoChangeRequired) {
			return nil
		}
		return errors.Wrap(err, "failed to offboard the repo")
	}
	return err

}
