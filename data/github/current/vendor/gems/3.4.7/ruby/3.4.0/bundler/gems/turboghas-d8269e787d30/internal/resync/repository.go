package resync

import (
	"context"
	"math"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/internal/fromctx"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
)

func (p *Sync) Repository(ctx context.Context, repoID uint64) (bool, error) {
	resp, err := p.githubAPI.GetRepositories(ctx, &twirpTurboghas.GetRepositoriesRequest{
		RepositoryIds: []uint64{repoID},
	})
	if err != nil {
		return false, errors.Wrap(err, "failed to get repository information")
	}

	return syncRepository(ctx, p.db, repoID, resp.GetRepositories())
}

// ignoreRepo returns true if the repository is not billable and should be ignored to improve index performance
func ignoreRepo(ctx context.Context, repository *twirpTurboghas.GetRepositoriesResponse_Repository) bool {
	return repository.IsArchived || (repository.IsPublic && !fromctx.Env.Value(ctx).IsEnterprise())
}

func syncRepository(ctx context.Context, db *data.Data, repoID uint64, repositories map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository) (found bool, err error) {
	defer func() {
		err = fields.Error(err, kvp.Uint64("gh.repo.id", repoID))
	}()

	repository, ok := repositories[repoID]
	if !ok {
		return false, errors.Wrap(db.DeleteRepository(ctx, data.RepositoryID(repoID)), "failed to delete repository information")
	}

	if repository.Entity == nil {
		return false, errors.New("repository response returned nil entity")
	}
	if repository.Owner == nil {
		return false, errors.New("repository response returned nil owner")
	}

	defer func() {
		err = fields.Error(err,
			kvp.Uint64("gh.turboghas.owner_id", repository.OwnerId),
			kvp.Uint64("gh.turboghas.billable_entity_id", repository.Entity.Id),
			kvp.String("gh.turboghas.billable_entity_type", repository.Entity.Type.String()),
		)
	}()

	if upsertErr := db.UpsertPurchaser(ctx, data.UpsertPurchaserArgs{
		OwnerID:    data.UserID(repository.OwnerId),
		EntityType: repository.Entity.Type,
		EntityID:   repository.Entity.Id,
	}); upsertErr != nil {
		return false, errors.Wrap(upsertErr, "failed to update purchaser")
	}

	if upsertErr := db.UpsertUser(ctx, data.UpsertUserArgs{
		UserID: data.UserID(repository.OwnerId),
		Login:  repository.Owner.Login,
		Type:   repository.Owner.Type,
	}); upsertErr != nil {
		return false, errors.Wrap(upsertErr, "failed to update repository")
	}

	if ignoreRepo(ctx, repository) {
		fromctx.Logger.Value(ctx).Debug("ignoring repository as archived or !ghes+public", kvp.Uint64("gh.repo.id", repoID))
		return false, errors.Wrap(db.DeleteRepository(ctx, data.RepositoryID(repoID)), "failed to delete repository")
	}

	if repository.AdvancedSecurityEnabled > math.MaxInt8 {
		return false, errors.Errorf("attempted to toggle a feature (%d) that could not be stored in the database", repository.AdvancedSecurityEnabled)
	}

	return true, errors.Wrap(db.UpsertRepository(ctx, data.UpsertRepositoryArgs{
		RepositoryID: data.RepositoryID(repoID),
		OwnerID:      data.UserID(repository.OwnerId),
		Name:         repository.Name,
		Enabled:      data.Feature(repository.AdvancedSecurityEnabled),
	}), "failed to update repository")
}

func (p *Sync) Repositories(ctx context.Context, repoIDs []uint64) (err error) {
	if len(repoIDs) == 0 {
		return nil
	}

	defer func() {
		if err != nil {
			err = fields.Error(err,
				kvp.Uint64s("gh.turboghas.repo_ids", repoIDs),
			)
		}
	}()

	resp, err := p.githubAPI.GetRepositories(ctx, &twirpTurboghas.GetRepositoriesRequest{
		RepositoryIds: repoIDs,
	})
	if err != nil {
		return err
	}

	repositories := resp.GetRepositories()

	for _, repoID := range repoIDs {
		if _, err := syncRepository(ctx, p.db, repoID, repositories); err != nil {
			return errors.Wrap(err, "failed to sync repository")
		}
	}
	return nil
}
