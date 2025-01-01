// Package repository contains services related to the `ts_repositories` table.
package repository

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/go-stats"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql/batch"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
)

// Service manipulates the `ts_repositories` table.
type Service struct {
	db *gorm.DB
}

// duration is used to track the execution time of the specified method in datadog.
func (r *Service) duration(ctx context.Context, method string) func() {
	start := time.Now()
	return func() {
		if !appctx.IsShuttingDown(ctx) {
			appctx.Stats(ctx).DistributionMs("repository.request", stats.Tags{"method": method}, time.Since(start))
		}
	}
}

// NewService creates a repository service with the given parameters
func NewService(db *gorm.DB) *Service {
	rs := &Service{
		db: db,
	}
	return rs
}

// Update writes the specified repository to the database.
// If there is already a row for the given `repository_id` then
// that row is updated as a single operation.
func (r *Service) Update(ctx context.Context, repository *ts.Repository) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "update")()

	db := otelgorm.SetSpanToGorm(ctx, r.db)

	// We cannot use the `Create` method as the "ON DUPLICATE KEY" pattern is not
	// supported in our current version of gorm
	now := sqltime.Now().UTC()
	sql := `
	INSERT INTO ts_repositories (created_at, updated_at, repository_id, owner_id, code_scanning_enabled, source_updated_at, default_ref, visibility)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	  ON DUPLICATE KEY UPDATE
	    updated_at = VALUES(updated_at),
		owner_id = VALUES(owner_id),
		code_scanning_enabled = VALUES(code_scanning_enabled),
		source_updated_at = VALUES(source_updated_at),
		default_ref = VALUES(default_ref),
		visibility = VALUES(visibility)
	`

	err := db.Exec(sql,
		now, now,
		repository.RepositoryID,
		repository.OwnerID,
		repository.CodeScanningEnabled,
		repository.SourceUpdatedAt,
		repository.DefaultRef,
		repository.Visibility,
	).Error
	if err != nil {
		return errors.Wrap(err, "updating repository has failed")
	}

	return nil
}

// Find returns a repository object for the given repository ID or nil if no
// such repository object exists in the db.
func (r *Service) Find(ctx context.Context, repositoryID ts.RepositoryEID) (*ts.Repository, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "find")()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))

	repository := ts.Repository{}
	err := db.Where("repository_id = ?", repositoryID).First(&repository).Error
	if gorm.IsRecordNotFoundError(err) {
		return nil, nil
	} else if err != nil {
		return nil, errors.Wrap(err, "fetching repository has failed")
	}

	return &repository, nil
}

// FindExisting looks up repository records based on the provided IDs.
func (r *Service) FindExisting(ctx context.Context, repositoryIDs []ts.RepositoryEID) ([]*ts.Repository, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "find-existing")()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))

	repositories := []*ts.Repository{}
	err := db.Where("repository_id IN (?)", repositoryIDs).Find(&repositories).Error
	if err != nil {
		return nil, errors.Wrap(err, "fetching repository has failed")
	}

	return repositories, nil
}

// Delete removes the repository records with the provided IDs from the database.
func (r *Service) Delete(ctx context.Context, repositoryIDs []ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "delete")()

	db := otelgorm.SetSpanToGorm(ctx, r.db)
	query := db.Where("repository_id IN (?)", repositoryIDs)

	err := query.Delete(&ts.Repository{}).Error
	if err != nil {
		return errors.Wrap(err, "deleting repositories has failed")
	}
	return nil
}

// SetLastIndexed updates `last_indexed_at` for the given repositories
func (r *Service) SetLastIndexed(ctx context.Context, repoIDs []ts.RepositoryEID, lastIndexedAt sqltime.Time) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "set-last-indexed")()

	if len(repoIDs) == 0 {
		return nil
	}

	db := otelgorm.SetSpanToGorm(ctx, r.db)
	err := db.Model(&ts.Repository{}).
		Where("repository_id IN (?)", repoIDs).
		Update("last_indexed_at", lastIndexedAt).Error
	if err != nil {
		return errors.Wrap(err, "failed to update last_indexed_at")
	}
	return nil
}

// ReposToIndex returns lists repository IDs in reverse order of their `last_indexed_at` date.
// This is used by the repo-indexer job to make sure we always sync the oldest repos first.
func (r *Service) ReposToIndex(ctx context.Context, cutoff *time.Time, limit uint) ([]*ts.Repository, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "repos-to-index")()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))

	oldestRepos := []*ts.Repository{}
	query := oldestReposQuery(db, cutoff).Order("last_indexed_at ASC").Limit(limit)
	err := query.Find(&oldestRepos).Error
	return oldestRepos, err
}

// CountReposToIndex counts the number of repos that have not been indexed since the specified cutoff.
// It is used by the repo-indexer job to determine how many more repositories it needs to sync.
func (r *Service) CountReposToIndex(ctx context.Context, cutoff *time.Time) (uint, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "count-repos-to-index")()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))
	var count uint

	err := oldestReposQuery(db, cutoff).Count(&count).Error
	return count, err
}

func oldestReposQuery(db *gorm.DB, cutoff *time.Time) *gorm.DB {
	query := db.Model(ts.Repository{})
	if cutoff != nil {
		query = query.Where("last_indexed_at <= ? OR last_indexed_at IS NULL", cutoff)
	}
	return query
}

// ActiveRepos returns the list of repository IDs that have had updates to their alerts since the specified cutoff.
func (r *Service) ActiveRepos(ctx context.Context, cutoff *time.Time, offset ts.RepositoryEID, limit uint) ([]ts.RepositoryEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "active-repos")()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))

	activeRepos := []ts.RepositoryEID{}
	activeReposQuery := db.Table("ts_logical_alerts USE INDEX (index_logical_alerts_on_repository_id_updated_at)").Select("DISTINCT repository_id")
	if cutoff != nil {
		activeReposQuery = activeReposQuery.Where("updated_at >= ?", cutoff)
	}
	err := activeReposQuery.Where("repository_id > ?", offset).
		Order("repository_id ASC").
		Limit(limit).
		Pluck("DISTINCT repository_id", &activeRepos).Error
	return activeRepos, err
}

// DisabledReposBatch calls the given function with batches of at most `step` repository IDs that have not had any metadata updates since the specified cutoff.
func (r *Service) DisabledReposBatch(ctx context.Context, cutoff *time.Time, step uint64, fn func(ctx context.Context, repositoryIDs []ts.RepositoryEID) error) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "disabled-repos-batch")()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))

	return batch.SparseTable(ctx, db, "ts_repositories", "repository_id", step, func(ctx context.Context, db *gorm.DB, start, end ts.RepositoryEID) error {
		disabledRepos, err := r.DisabledRepos(ctx, cutoff, start, end)
		if err != nil {
			return err
		}

		// If no rows are returned, there's no use in calling the function.
		if len(disabledRepos) == 0 {
			return nil
		}

		return fn(ctx, disabledRepos)
	})
}

// DisabledRepos returns the list of repository IDs that don't have any analyses and have not had any metadata updates since the specified cutoff for
// which the repository ID is between start and end (inclusive).
func (r *Service) DisabledRepos(ctx context.Context, cutoff *time.Time, start, end ts.RepositoryEID) ([]ts.RepositoryEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "disabled-repos")()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))

	disabledRepos := []ts.RepositoryEID{}
	query := db.Model(ts.Repository{}).
		Joins("LEFT JOIN ts_analyses ON ts_analyses.repository_id=ts_repositories.repository_id").
		Where("ts_repositories.repository_id BETWEEN ? AND ?", start, end).
		Where("ts_analyses.repository_id IS NULL")
	if cutoff != nil {
		query = query.Where("ts_repositories.created_at < ?", cutoff)
	}
	err := query.Pluck("ts_repositories.repository_id", &disabledRepos).Error
	return disabledRepos, err
}

// DeletedReposBatch calls the given function with batches of at most `step` deleted repository IDs from `ts_deleted_repositories` since the specified cutoff.
func (r *Service) DeletedReposBatch(ctx context.Context, cutoff *time.Time, step uint64, fn func(ctx context.Context, repositoryIDs []ts.RepositoryEID) error) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "deleted-repos-batch")()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))

	return batch.SparseTable(ctx, db, "ts_deleted_repositories", "repository_id", step, func(ctx context.Context, db *gorm.DB, start, end ts.RepositoryEID) error {
		deletedRepos, err := r.DeletedRepos(ctx, cutoff, start, end)
		if err != nil {
			return err
		}

		// If no rows are returned, there's no use in calling the function.
		if len(deletedRepos) == 0 {
			return nil
		}

		return fn(ctx, deletedRepos)
	})
}

// DeletedRepos returns the list of deleted repository IDs from `ts_deleted_repositories` since the specified cutoff for
// which the repository ID is between start and end (inclusive).
func (r *Service) DeletedRepos(ctx context.Context, cutoff *time.Time, start, end ts.RepositoryEID) ([]ts.RepositoryEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer r.duration(ctx, "deleted-repos")()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, r.db))

	deletedRepos := []ts.RepositoryEID{}
	query := db.Model(ts.DeletedRepository{}).Where("ts_deleted_repositories.repository_id BETWEEN ? AND ?", start, end)
	if cutoff != nil {
		query = query.Where("ts_deleted_repositories.delete_finished_at < ?", cutoff)
	}
	err := query.Pluck("ts_deleted_repositories.repository_id", &deletedRepos).Error
	return deletedRepos, err
}
