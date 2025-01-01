package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/pkg/errors"
)

// UpdateRepoMetadataFn is a function that updates the repository metadata in the database.
type UpdateRepoMetadataFn func(ctx context.Context, repoID ts.RepositoryEID) error

type repoDB interface {
	Update(ctx context.Context, repo *ts.Repository) error
}

// NewRepoMetaUpdater returns an UpdateRepoMetadataFn function.
func NewRepoMetaUpdater(db repoDB, repoAPI ghgh.RepositoryAPI) UpdateRepoMetadataFn {
	return func(ctx context.Context, repoID ts.RepositoryEID) error {
		repos, err := repoAPI.GetRepositories(ctx, []ts.RepositoryEID{repoID})
		if err != nil {
			return errors.Wrap(err, "could not fetch repository metadata")
		}
		if len(repos) == 0 {
			return errors.Errorf("repository %d not found", repoID)
		}
		repo := repos[0]

		// update the ts_repositories table
		err = db.Update(ctx, repo)
		if err != nil {
			return errors.Wrap(err, "could not update repository metadata")
		}

		return nil
	}
}
