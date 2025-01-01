package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"

	"github.com/pkg/errors"
)

// OffboardRepo offboards a repository from Managed Analyses.
func (ma *ManagedAnalyses) OffboardRepo(ctx context.Context, repoID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	err := ma.DataService.DisableCodeqlConfigByRepo(ctx, repoID)
	if err != nil {
		if errors.Is(err, ts.ErrCodeqlConfigNotFound) || errors.Is(err, ts.ErrCodeqlRepoNotFound) {
			return ts.ErrNoChangeRequired
		}
		return errors.Wrap(err, "failed to offboard the repo")
	}

	return nil
}
