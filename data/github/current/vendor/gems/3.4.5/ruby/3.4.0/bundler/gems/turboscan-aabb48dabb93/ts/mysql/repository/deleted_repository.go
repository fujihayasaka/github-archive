package repository

import (
	"context"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/ghapi"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

type DeletedRepositoryService struct {
	db *gorm.DB

	reposAuditsAPI ghapi.ReposAuditsGetter
}

// NewDeletedRepositoryService creates a deleted repository service with the given parameters
func NewDeletedRepositoryService(db *gorm.DB, reposAuditsAPI ghapi.ReposAuditsGetter) *DeletedRepositoryService {
	return &DeletedRepositoryService{
		db:             db,
		reposAuditsAPI: reposAuditsAPI,
	}
}

// InsertRepositoryForDeletion adds an entry to the ts_deleted_repositories table which will signify that the specified repository no longer exists in the monolith.
// This will cause the scheduled job to eventually delete all turboscan data related to it.
func (s *DeletedRepositoryService) InsertRepositoryForDeletion(ctx context.Context, repositoryID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// We cannot use the `Create` method as a unique constraint violation is thrown,
	// and `FirstOrCreate` makes two queries.
	sql := `
	INSERT INTO ts_deleted_repositories (created_at, updated_at, repository_id)
	VALUES (?, ?, ?)
	  ON DUPLICATE KEY UPDATE
	    repository_id = repository_id
	`
	now := sqltime.Now().UTC()
	return db.Exec(sql, now, now, repositoryID).Error
}

// DeleteProgressBlobs updates the delete state for the repository, by recording that `blobs` blobs have been deleted.
func (s *DeletedRepositoryService) DeleteProgressBlobs(ctx context.Context, repositoryID ts.RepositoryEID, blobs uint64) error {
	return s.updateDeleteProgress(ctx, repositoryID, 0, 0, blobs, false)
}

// DeleteProgressMysql updates the deletion state for the repository, by adding in the DB the number of `dbRows` that have been deleted.
func (s *DeletedRepositoryService) DeleteProgressMysql(ctx context.Context, repositoryID ts.RepositoryEID, dbRows uint64) error {
	return s.updateDeleteProgress(ctx, repositoryID, dbRows, 0, 0, false)
}

// DeleteProgressES updates the deletion state for the repository, by adding in the DB the number of `esDocs` that have been deleted.
func (s *DeletedRepositoryService) DeleteProgressES(ctx context.Context, repositoryID ts.RepositoryEID, esDocs uint64) error {
	return s.updateDeleteProgress(ctx, repositoryID, 0, esDocs, 0, false)
}

// CompleteDeleteProgress updates the delete state for the repository, by recording that deletetion has finished.
func (s *DeletedRepositoryService) CompleteDeleteProgress(ctx context.Context, repositoryID ts.RepositoryEID) error {
	return s.updateDeleteProgress(ctx, repositoryID, 0, 0, 0, true)
}

// FindRepositoriesForDeletion fetches repositories that have been deleted (from the monolith) for which data in turboscan
// should be deleted. If repoID is non-zero, filters the results based on that ID (in which case the list will contains only one item).
func (s *DeletedRepositoryService) FindRepositoriesForDeletion(ctx context.Context, repoID ts.RepositoryEID, limit int) ([]*ts.DeletedRepository, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	query := otelgorm.SetSpanToGorm(ctx, s.db)
	if repoID > 0 {
		query = query.Where("repository_id = ?", repoID)
	}

	deletedRepos := []*ts.DeletedRepository{}
	err := query.Where("delete_finished_at IS NULL").Limit(limit).Find(&deletedRepos).Error
	if err != nil {
		return nil, errors.Wrap(err, "fetching deleted repositories has failed")
	}
	return deletedRepos, nil
}

// updateDeleteProgress updates the delete state of the specified repository.
func (s *DeletedRepositoryService) updateDeleteProgress(ctx context.Context, repositoryID ts.RepositoryEID,
	dbRows, esDocs, blobs uint64, deleteFinished bool) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	updates := map[string]interface{}{}
	updates["db_rows_deleted"] = gorm.Expr("db_rows_deleted + ?", dbRows)
	updates["es_docs_deleted"] = gorm.Expr("es_docs_deleted + ?", esDocs)
	updates["blobs_deleted"] = gorm.Expr("blobs_deleted + ?", blobs)
	if deleteFinished {
		updates["delete_finished_at"] = sqltime.Now().UTC()
	}

	return db.Model(ts.DeletedRepository{}).Where("repository_id = ?", repositoryID).Update(updates).Error
}

// DeletedRepositoriesOnDotcom calls the gh/gh internal API /repositories/audits endpoint for the given repoIDs and
// returns a list of the repoIDs which have the 'not_found' result, indicating that the repository is likely to be deleted.
func (s *DeletedRepositoryService) DeletedRepositoriesOnDotcom(ctx context.Context, repoIDs []ts.RepositoryEID) (notFoundRepoIDs []ts.RepositoryEID, err error) {
	reposAudits, err := s.reposAuditsAPI.GetReposAudits(ctx, ghapi.RepoAuditsRequest{RepositoryIDs: repoIDs})
	if err != nil {
		return notFoundRepoIDs, errors.Wrap(err, "could not fetch repos' audits from GH internal API")
	}

	resultCounts := map[string]int64{}
	for _, repo := range reposAudits.Results {
		resultCounts[repo.Result]++
		if repo.Result == ghapi.RepoNotFound {
			notFoundRepoIDs = append(notFoundRepoIDs, repo.RepositoryID)
		}
	}
	for result, count := range resultCounts {
		appctx.Stats(ctx).Counter("deleted_repository.audit_result", stats.Tags{"result": result}, count)
	}

	return notFoundRepoIDs, nil
}
