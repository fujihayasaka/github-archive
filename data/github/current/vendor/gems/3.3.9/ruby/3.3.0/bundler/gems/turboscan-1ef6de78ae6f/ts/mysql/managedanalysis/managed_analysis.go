// Package managedanalysis handles interactions with default setup data.
package managedanalysis

import (
	"context"
	"iter"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/go-stats"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"

	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
)

const VITESS_MAX_ROWS_LIMIT = 300000 // matches the Vitess max rows limit for a single query

var ErrTransactionInProgress = errors.New("Another transaction is already in progress")
var ErrScheduleNotFound = errors.New("The codeql schedule was not found")

// Service handles interactions with various tables and publishers used for Managed Analysis.
type Service struct {
	db           *gorm.DB
	runPublisher CodeqlRunPublisher
	inTx         bool
}

type CodeqlRunPublisher interface {
	CodeqlRunEvent(_ context.Context, m *oldtshydro.CodeqlRun) error
}

// NewService returns a new ManagedAnalysis service with the given set of mysql Options
func NewService(db *gorm.DB, runPublisher CodeqlRunPublisher) *Service {
	as := &Service{
		db:           db,
		runPublisher: runPublisher,
	}
	return as
}

// WithTransaction wraps several db calls inside a transaction.
// If fn returns an error all the changes will be rolled back.
func (ma *Service) WithTransaction(fn func(db managedanalyses.CodeqlDB) error) error {
	if ma.inTx {
		return ErrTransactionInProgress
	}
	return ma.db.Transaction(func(tx *gorm.DB) error {
		txService := NewService(tx, ma.runPublisher)
		txService.inTx = true
		err := fn(txService)
		return err
	})
}

func (ma *Service) withTransaction(fn func(tx *gorm.DB) error) error {
	// If called while already inside a transaction, it will reuse it.
	// It will NOT do a nested transaction
	if ma.inTx {
		return fn(ma.db)
	}
	return ma.db.Transaction(func(tx *gorm.DB) error {
		return fn(tx)
	})
}

// CreateCodeqlRepo creates a new CodeqlRepo in the database.
// This method will partially overwrite existing CodeRepo entries, if you want to
// update a CodeqlRepo, use UpdateCodeqlRepo instead.
func (ma *Service) CreateCodeqlRepo(ctx context.Context, codeqlRepo *ts.CodeqlRepo) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if codeqlRepo.RepositoryID == 0 {
		return errors.New("repository id must be specified for creating codeql repo")
	}

	// We do not want to create any config here
	if codeqlRepo.CurrentConfig != nil || codeqlRepo.CurrentConfigID != nil {
		return errors.New("current config must not be specified for creating codeql repo")
	}
	if codeqlRepo.StagedConfig != nil || codeqlRepo.StagedConfigID != nil {
		return errors.New("staged config must not be specified for creating codeql repo")
	}
	if codeqlRepo.FailedConfig != nil || codeqlRepo.FailedConfigID != nil {
		return errors.New("failed config must not be specified for creating codeql repo")
	}

	// We cannot use the `Create` method as the "ON DUPLICATE KEY" pattern is not
	// supported in our current version of gorm.
	// We check if a repo exist and then create/update it.
	// While this can lead to race conditions, we are fine with it because we have
	// a unique constraint on the repository_id column. Moreover, if two requests
	// try to create the same repo at the same time, the second one will fail with
	// a duplicate key error rather than silently overwriting the first one.
	err := ma.withTransaction(func(tx *gorm.DB) error {
		tx = otelgorm.SetSpanToGorm(ctx, tx)

		IDContainer := struct {
			ID ts.CodeqlRepoID
		}{}
		err := tx.Model(&ts.CodeqlRepo{}).
			Where("repository_id = ?", codeqlRepo.RepositoryID).
			Select("id").
			Scan(&IDContainer).Error
		if err != nil && !gorm.IsRecordNotFoundError(err) {
			return errors.Wrap(err, "failed to check if codeql repo exists")
		}

		// Assign ID - might be 0 if it doesn't exist
		codeqlRepo.ID = IDContainer.ID

		// Update enabled_at on re-enabled repos
		codeqlRepo.EnabledAt = sqltime.Now()

		err = tx.Save(codeqlRepo).Error
		if err != nil {
			return errors.Wrap(err, "failed to create codeql repo")
		}
		return nil
	})
	return err
}

// CreateStagedCodeqlConfig saves a STAGED CodeqlConfig into the database.
// At any given point, we may have 0/1 STAGED config, 0/1 CURRENT config, 0/more null (historical) config
func (ma *Service) CreateStagedCodeqlConfig(ctx context.Context, config *ts.CodeqlConfig) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	// Only staged configs can be created
	if !config.IsStaged() {
		return errors.New("can only create a STAGED config")
	}

	// there may be many null tag configs but there should only be at most one CURRENT tag
	configs := []ts.CodeqlConfig{}
	err := db.Where("repository_id = ? AND tag is not null", config.RepositoryID).Order("tag").Find(&configs).Error
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return err
	}

	if len(configs) > 0 {
		if configs[len(configs)-1].IsStaged() {
			return ts.ErrCodeqlConfigConflict
		}
	}

	err = db.Save(config).Error
	if err != nil {
		return errors.Wrap(err, "failed to update managed analysis record")
	}

	out := db.Exec(`UPDATE ts_codeql_repos SET staged_config_id = ? WHERE repository_id = ? AND soft_deleted_at IS NULL`, config.ID, config.RepositoryID)
	err = out.Error
	if err != nil {
		return errors.Wrap(err, "failed to update the codeql_repo entry")
	}
	if out.RowsAffected == 0 {
		appctx.Logger(ctx).Info("missing codeqlRepo in CreateStagedCodeqlConfig", config.RepositoryID.AsKVP())
		appctx.Stats(ctx).Counter("default_setup.codeql_repo.missing", stats.Tags{}, 1)
		return ts.ErrCodeqlRepoNotFound
	}

	return nil
}

// ReplaceCodeqlConfigInplace would replace the CurrentConfig in the CodeqlRepo inplace without
// the need to have a staged config and promoting that config specifically.
// NOTE: This is used for a special case where we did not want to create a
// new validation run and thus should be used with careful consideration.
func (ma *Service) ReplaceCodeqlConfigInplace(ctx context.Context, config *ts.CodeqlConfig) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	// there may be many null tag configs but there should only be at most one CURRENT tag
	var savedConfig ts.CodeqlConfig
	err := db.Where("repository_id = ? AND tag is not null", config.RepositoryID).Order("tag DESC").First(&savedConfig).Error
	if err != nil {
		return err
	}
	if savedConfig.IsStaged() {
		return ts.ErrCodeqlConfigConflict
	}

	config.ValidationRunStatus = savedConfig.ValidationRunStatus
	config.ValidationRun = savedConfig.ValidationRun
	config.TemplateVersion = savedConfig.TemplateVersion

	err = db.Save(config).Error
	if err != nil {
		return errors.Wrap(err, "failed to update managed analysis record")
	}

	return ma.withTransaction(func(tx *gorm.DB) error {
		tx = otelgorm.SetSpanToGorm(ctx, tx)

		codeqlRepo, err := ma.GetCodeqlRepo(ctx, config.RepositoryID)
		if err != nil {
			return err
		}

		currentConfig := codeqlRepo.CurrentConfig

		now := time.Now()
		if currentConfig != nil {
			deprecatedAt := gormext.ConvertTime(&now)
			err := tx.Exec(`UPDATE ts_codeql_configs SET tag = NULL, deprecated_at = ? where tag = 0 AND repository_id = ?`, deprecatedAt, config.RepositoryID).Error
			if err != nil {
				return errors.Wrap(err, "failed to deprecate previous CURRENT config")
			}
		}

		// promote the config
		// we check tag = 1 in case the repo has already been offboarded from managed analyses
		enabledAt := gormext.ConvertTime(&now)
		out := tx.Exec(`UPDATE ts_codeql_configs SET tag = 0, validation_run_status = ?, enabled_at = ? WHERE id = ?`, currentConfig.ValidationRunStatus, enabledAt, config.ID)
		err = out.Error
		if err != nil {
			return errors.Wrap(err, "failed to save new CURRENT config")
		}
		if out.RowsAffected == 0 {
			return ts.ErrCodeqlConfigNotFound
		}

		// Attach validation run to new config.
		// We do this so that the new config has a valid validation run connected.
		out = tx.Exec(`UPDATE ts_codeql_runs SET codeql_config_id = ? WHERE id = ?`, config.ID, currentConfig.ValidationRun.ID)
		err = out.Error
		if err != nil {
			return errors.Wrap(err, "failed to update codeql_config_id in-place")
		}
		if out.RowsAffected == 0 {
			return ts.ErrCodeqlRunNotFound
		}

		// update codeqlrepo
		codeqlRepo.CurrentConfigID = &config.ID
		codeqlRepo.CurrentConfig = config
		codeqlRepo.StagedConfigID = nil
		codeqlRepo.StagedConfig = nil
		codeqlRepo.FailedConfigID = nil
		codeqlRepo.FailedConfig = nil
		codeqlRepo.QuerySuite = config.QuerySuiteType.Root()
		codeqlRepo.ThreatModel = config.ThreatModel
		codeqlRepo.RunnerLabel = config.RunnerLabel
		codeqlRepo.UsingCSRunnerLabel = config.UsingCSRunnerLabel

		err = tx.Save(codeqlRepo).Error
		if err != nil {
			return errors.Wrap(err, "failed to update the codeql_repo entry")
		}

		return nil
	})
}

// DisableCodeqlConfigByRepo ensures there are no CURRENT or STAGED codeql configs for the given repository ID.
// It returns an error if there is no CURRENT or STAGED config for it.
func (ma *Service) DisableCodeqlConfigByRepo(ctx context.Context, repoID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	return ma.withTransaction(func(tx *gorm.DB) error {
		tx = otelgorm.SetSpanToGorm(ctx, tx)

		codeqlRepo, err := ma.GetCodeqlRepo(ctx, repoID)
		if err != nil {
			return err
		}

		// deprecate all existing current/staged configs if present
		now := time.Now()
		deprecated_at := gormext.ConvertTime(&now)
		out := tx.Exec(`UPDATE ts_codeql_configs SET tag = NULL, deprecated_at = ? WHERE tag IS NOT NULL AND repository_id = ?`, deprecated_at, repoID)
		err = out.Error
		if err != nil {
			return errors.Wrap(err, "failed to offboard repository from managed analyses")
		}
		if out.RowsAffected == 0 {
			return ts.ErrCodeqlConfigNotFound
		}

		codeqlRepo.CurrentConfigID = nil
		codeqlRepo.CurrentConfig = nil
		codeqlRepo.StagedConfigID = nil
		codeqlRepo.StagedConfig = nil
		codeqlRepo.FailedConfigID = nil
		codeqlRepo.FailedConfig = nil

		err = tx.Save(codeqlRepo).Error
		if err != nil {
			return errors.Wrap(err, "Failed to update codeql repo")
		}

		return nil
	})
}

// PromoteCodeqlConfigToCurrent sets the provided codeql config to current and deprecates
// the previous current config for the same repo, if one existed.
// If a CodeqlRepo entry exists, it update its config values
func (ma *Service) PromoteCodeqlConfigToCurrent(ctx context.Context, config *ts.CodeqlConfig, repoID ts.RepositoryEID, runStatus *ts.CodeqlRunStatus) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	initialOnboarding := false
	err := ma.withTransaction(func(tx *gorm.DB) error {
		tx = otelgorm.SetSpanToGorm(ctx, tx)
		now := time.Now()

		codeqlRepo, err := ma.GetCodeqlRepo(ctx, repoID)
		if err != nil {
			return err
		}
		currentConfig := codeqlRepo.CurrentConfig

		// If there is no current config we are onboarding
		initialOnboarding = (currentConfig == nil)

		// deprecate old current config if present
		if currentConfig != nil {
			deprecatedAt := gormext.ConvertTime(&now)
			err := tx.Exec(`UPDATE ts_codeql_configs SET tag = NULL, deprecated_at = ? where tag = 0 AND repository_id = ?`, deprecatedAt, repoID).Error
			if err != nil {
				return errors.Wrap(err, "failed to deprecate previous CURRENT config")
			}
		}

		// promote the config
		// we check tag = 1 in case the repo has already been offboarded from managed analyses
		enabledAt := gormext.ConvertTime(&now)
		out := tx.Exec(`UPDATE ts_codeql_configs SET tag = 0, validation_run_status = ?, enabled_at = ? WHERE tag = 1 AND id = ?`, runStatus, enabledAt, config.ID)
		err = out.Error
		if err != nil {
			return errors.Wrap(err, "failed to save new CURRENT config")
		}
		if out.RowsAffected == 0 {
			return ts.ErrCodeqlConfigNotFound
		}

		// update codeqlrepo
		codeqlRepo.CurrentConfigID = &config.ID
		codeqlRepo.CurrentConfig = config
		codeqlRepo.StagedConfigID = nil
		codeqlRepo.StagedConfig = nil
		codeqlRepo.FailedConfigID = nil
		codeqlRepo.FailedConfig = nil
		codeqlRepo.QuerySuite = config.QuerySuiteType.Root()
		codeqlRepo.ThreatModel = config.ThreatModel
		codeqlRepo.RunnerLabel = config.RunnerLabel
		codeqlRepo.UsingCSRunnerLabel = config.UsingCSRunnerLabel
		err = tx.Save(codeqlRepo).Error
		if err != nil {
			return errors.Wrap(err, "failed to update the codeql_repo entry")
		}

		return nil
	})
	if err != nil {
		return err
	}

	if initialOnboarding {
		appctx.Logger(ctx).Info("repo onboarded to managed analyses",
			repoID.AsKVP(),
			kvp.Uint64("gh.turboscan.codeql_config_id", uint64(config.ID)),
		)
	} else {
		appctx.Logger(ctx).Info("codeql config updated",
			repoID.AsKVP(),
			kvp.Uint64("gh.turboscan.codeql_config_id", uint64(config.ID)),
		)
	}
	return nil
}

// DeprecateStagedCodeqlConfig deprecates the provided codeql by setting its Tag to nil
func (ma *Service) DeprecateStagedCodeqlConfig(ctx context.Context, repoID ts.RepositoryEID, configID ts.CodeqlConfigID, runStatus *ts.CodeqlRunStatus) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	return ma.withTransaction(func(tx *gorm.DB) error {
		tx = otelgorm.SetSpanToGorm(ctx, tx)
		// deprecate config if present
		now := time.Now()
		deprecatedAt := gormext.ConvertTime(&now)
		out := tx.Exec(`UPDATE ts_codeql_configs SET tag = NULL, validation_run_status = ?, deprecated_at = ? WHERE id = ? AND tag = ?`, runStatus, deprecatedAt, configID, ts.CodeqlConfigTag_STAGED)
		err := out.Error
		if err != nil {
			return errors.Wrap(err, "failed to deprecate config")
		}
		if out.RowsAffected == 0 {
			return ts.ErrCodeqlConfigNotFound
		}

		// update codeqlrepo
		out = tx.Exec(`UPDATE ts_codeql_repos SET staged_config_id = NULL, failed_config_id = ? WHERE repository_id = ? AND soft_deleted_at IS NULL`, configID, repoID)
		err = out.Error
		if err != nil {
			return errors.Wrap(err, "failed to update the codeql_repo entry")
		}
		if out.RowsAffected == 0 {
			appctx.Logger(ctx).Info("missing codeqlRepo in DeprecateStagedCodeqlConfig", repoID.AsKVP())
			appctx.Stats(ctx).Counter("default_setup.codeql_repo.missing", stats.Tags{}, 1)
			return ts.ErrCodeqlRepoNotFound
		}

		return nil
	})
}

func (ma *Service) CreateCodeqlRun(ctx context.Context, run *ts.CodeqlRun) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	// There is a unique constraint on workflow_run_id, so we need to check that the field was set.
	if run.WorkflowRunID == 0 {
		return errors.New("workflow_run_id must be set")
	}

	// If publishing fails, we don't want to fail the whole thing, just log.
	err := ma.runPublisher.CodeqlRunEvent(ctx, run.ToHydro())
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("Error publishing CodeQL run event on create")
	}

	return db.Create(run).Error
}

func (ma *Service) GetCodeqlRun(ctx context.Context, repoID ts.RepositoryEID, workflowRunID ts.WorkflowRunEID) (*ts.CodeqlRun, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	run := &ts.CodeqlRun{}
	err := db.Model(&ts.CodeqlRun{}).
		Preload("Config").
		Where("repository_id = ? AND workflow_run_id = ?", repoID, workflowRunID).
		First(run).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ts.ErrCodeqlRunNotFound
	}

	return run, err
}

// GetMostRecentCodeqlRun returns the most recent codeql run for the given repo and config
// unless the config is deprecated, in which case the config is ignored.
func (ma *Service) GetMostRecentCodeqlRun(ctx context.Context, repoID ts.RepositoryEID, config *ts.CodeqlConfig) (*ts.CodeqlRun, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	run := &ts.CodeqlRun{}
	query := db.Where("repository_id = ?", repoID)
	if !config.IsDeprecated() {
		query = query.Where("codeql_config_id = ?", config.ID)
	}
	err := query.Order("created_at DESC").First(run).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ts.ErrCodeqlRunNotFound
	}

	return run, err
}

// GetPendingRunsForRef returns a limited set of at most 20 uncompleted runs for the given ref that are older than  `olderThan`.
func (ma *Service) GetPendingRunsForRef(ctx context.Context, repoID ts.RepositoryEID, ref ts.Ref, olderThan time.Time) ([]ts.CodeqlRun, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	// TODO We need an index on the table

	// We want to cancel older runs for the same ref that meet some criteria below.
	query := db.Model(ts.CodeqlRun{}).Where("repository_id = ? AND ref_bytes = ? AND created_at < ? AND status = ? ", repoID, []byte(ref), sqltime.Time{Time: olderThan}, ts.CodeqlRunStatus_INPROGRESS)

	// Order ascending so if we hit the limit we cancel the older runs
	query = query.Order("created_at ASC")
	query = query.Limit(20)

	var runs []ts.CodeqlRun
	err := query.Find(&runs).Error
	if err != nil {
		return nil, err
	}

	return runs, nil
}

func (ma *Service) GetCodeqlRunBySha(ctx context.Context, repoID ts.RepositoryEID, sha ts.Sha) (*ts.CodeqlRun, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	run := &ts.CodeqlRun{}
	err := db.Where("repository_id = ? AND sha = ?", repoID, sha).First(run).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ts.ErrCodeqlRunNotFound
	}

	return run, err
}

// GetStaleValidationRuns retrieves a list of CodeQL validation runs that are in progress, but have not been updated since the given timeout.
func (ma *Service) GetStaleValidationRuns(ctx context.Context, repoID *ts.RepositoryEID, timeout time.Duration, limit uint) ([]ts.CodeqlRun, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	runs := []ts.CodeqlRun{}
	lastUpdatedAt := sqltime.Time{Time: time.Now().Add(-timeout)}
	query := db.Where("run_type=?", ts.CodeqlRunType_VALIDATION).
		Where("status IN (?)", []ts.CodeqlRunStatus{ts.CodeqlRunStatus_PENDING, ts.CodeqlRunStatus_INPROGRESS}).
		Where("updated_at < ?", lastUpdatedAt).Limit(limit)
	if repoID != nil {
		query = query.Where("repository_id = ?", repoID)
	}
	err := query.Find(&runs).Error
	return runs, err
}

// PreviousRunExists checks if a worklow run has been triggered for the given sha, i.e. there is a record in ts_codeql_run for the same SHA
func (ma *Service) PreviousRunExists(ctx context.Context, repoID ts.RepositoryEID, sha ts.Sha) (bool, error) {
	previousRun, err := ma.GetCodeqlRunBySha(ctx, repoID, sha)
	if err != nil && !errors.Is(err, ts.ErrCodeqlRunNotFound) {
		return false, err
	}

	return previousRun != nil, nil
}

// UpdateCodeqlRun saves the entry to the DB.
// It is an error to call this method if the record does not exist in the DB.
func (ma *Service) UpdateCodeqlRun(ctx context.Context, run *ts.CodeqlRun) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	if run.ID == 0 {
		return errors.New("object does not specify a valid ID")
	}

	// If publishing fails, we don't want to fail the whole thing, just log.
	err := ma.runPublisher.CodeqlRunEvent(ctx, run.ToHydro())
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("Error publishing CodeQL run event on update")
	}

	// we include Omit("Config") here to avoid persisting any
	// accidental changes to the run's config when it's been preloaded
	return db.Omit("Config").Save(run).Error
}

// AdjustCodeqlConfigLanguages saves the entry to the DB
// It is an error to call this method if the record does not exist in the DB.
func (ma *Service) AdjustCodeqlConfigLanguages(ctx context.Context, configID ts.CodeqlConfigID, newLanguages ts.Languages, newWorkflow string) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	if configID == 0 {
		return errors.New("object does not specify a valid ID")
	}

	out := db.Exec(`UPDATE ts_codeql_configs SET languages = ?, workflow = ? WHERE id = ? AND tag = ?`, newLanguages, newWorkflow, configID, ts.CodeqlConfigTag_STAGED)
	err := out.Error
	if err != nil {
		return errors.Wrap(err, "failed to adjust the codeql config")
	}
	if out.RowsAffected == 0 {
		return ts.ErrCodeqlConfigNotFound
	}

	return err
}

// UpdateCodeqlRepo saves the entry to the DB
// It is an error to call this method if the record does not exist in the DB.
func (ma *Service) UpdateCodeqlRepo(ctx context.Context, codeqlRepo *ts.CodeqlRepo) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	if codeqlRepo.ID == 0 {
		return errors.New("object does not specify a valid ID")
	}

	return db.Save(codeqlRepo).Error
}

//	GetPotentiallyOnboardedRepositoryIDs  returns the set of repos that are either enabled or enabling.
//
// If `since` is provided, only repos with and updated_at since the timestamp will be returned.
// Returns a timestamp that can be passed to `since` in successive calls, even if no repository is returned.
func (ma *Service) GetPotentiallyOnboardedRepositoryIDs(ctx context.Context, since *time.Time) ([]ts.RepositoryEID, *time.Time, error) {
	// We are fetching 64bits per row. There is a limit in how much data we can transfer,
	// so if we increase the amount of information here, we might need to reduce the
	// page size.

	return ma.getPotentiallyOnboardedRepositoryIDs(ctx, since, VITESS_MAX_ROWS_LIMIT)
}

func (ma *Service) getPotentiallyOnboardedRepositoryIDs(ctx context.Context, since *time.Time, pageSize int) ([]ts.RepositoryEID, *time.Time, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	// Fetch the last update time first
	var res []sqltime.Time
	err := db.Model(ts.CodeqlConfig{}).
		Where("tag is not null").
		Order("updated_at DESC").
		Limit(1).
		Pluck("updated_at", &res).
		Error
	if err != nil {
		return nil, nil, err
	}
	var lastUpdatedAt *time.Time
	if len(res) > 0 {
		lastUpdatedAt = &(res[0].Time)
	}

	// Now Fetch all records.
	// Note: We might get a record with an update time higher than lastUpdatedAt.
	//       This is ok and allows us to keep the logic simple and efficient.
	query := db.Model(ts.CodeqlConfig{}).Where("tag is not null")

	if since != nil {
		query = query.Where("updated_at >= (?)", since)
	}

	// Force an order to allow for pagination
	query = query.Order("updated_at, tag, repository_id")

	var out, tmp []ts.RepositoryEID
	for offset := 0; ; offset += pageSize {
		err = query.
			Limit(pageSize).
			Offset(offset).
			Pluck("repository_id", &tmp).Error
		if err != nil {
			return nil, nil, err
		}
		out = append(out, tmp...)

		if len(tmp) < pageSize {
			return out, lastUpdatedAt, nil
		}
	}
}

func (ma *Service) CreateCodeqlSchedule(ctx context.Context, repoID ts.RepositoryEID, nextRunAt time.Time) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	// We cannot use the `Create` method as the "ON DUPLICATE KEY" pattern is not
	// supported in our current version of gorm
	now := sqltime.Now().UTC()
	sql := `
	INSERT INTO ts_codeql_schedules (created_at, updated_at, repository_id, next_run_at)
	VALUES (?, ?, ?, ?)
	  ON DUPLICATE KEY UPDATE
	    updated_at = VALUES(updated_at),
		next_run_at = VALUES(next_run_at)
	`

	err := db.Exec(sql,
		now, now,
		repoID,
		nextRunAt,
	).Error

	return err
}

const max_schedules_to_fetch = 1500

func (ma *Service) GetRunnableCodeqlSchedules(ctx context.Context) ([]ts.CodeqlSchedule, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	var out []ts.CodeqlSchedule

	err := db.Table("ts_codeql_schedules").
		Joins("INNER JOIN ts_codeql_configs ON ts_codeql_schedules.repository_id = ts_codeql_configs.repository_id").
		Where("ts_codeql_configs.tag = ?", ts.CodeqlConfigTag_CURRENT).
		Where("ts_codeql_schedules.next_run_at < ?", time.Now()).
		Order("ts_codeql_schedules.next_run_at").
		Limit(max_schedules_to_fetch).
		Find(&out).Error

	if err != nil {
		return nil, errors.Wrap(err, "failed to fetch runnable schedules")
	}

	return out, nil
}

func (ma *Service) HadNonScheduledRunsAfter(ctx context.Context, repoIDs []ts.RepositoryEID, after time.Time) (map[ts.RepositoryEID]bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	var out []ts.RepositoryEID
	err := db.Table("ts_codeql_runs").
		Where("repository_id in (?)", repoIDs).
		Where("triggering_event <> ?", ts.CodeqlRunTriggeringEvent_SCHEDULED).
		Where("created_at >= ?", after).
		Pluck("DISTINCT repository_id", &out).Error
	if err != nil {
		return nil, err
	}

	res := make(map[ts.RepositoryEID]bool)
	for _, repoID := range out {
		res[repoID] = true
	}

	return res, nil
}

func (ma *Service) UpdateCodeqlSchedule(ctx context.Context, schedule ts.CodeqlSchedule) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	return db.Save(&schedule).Error
}

// CanAttemptJITValidation returns whether the specified repository is allowed to do a JIT validation run
// for the specified workflow template version, based on the overallLimit on the total number of validation
// attempts that are allowed for a repo+version combination, and on the recencyWindow that sets a minimum
// waiting time before re-attempting the validation.
// Since in practice we only ever create (at most) one validation run for each config,
// fetching configs with validation_run_status null or CodeqlRunStatus_FAILED
// is a good representation of how many times we have tried to adopt a config
// based on a certain version of the template workflow
func (ma *Service) CanAttemptJITValidation(ctx context.Context, repoID ts.RepositoryEID, templateVersion string, overallLimit int, recencyWindow time.Duration) (bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	// Check that we are not already running another configuration change
	var count int
	err := db.Model(ts.CodeqlConfig{}).
		Where("repository_id = ? AND tag = ?", repoID, ts.CodeqlConfigTag_STAGED).
		Count(&count).Error
	if err != nil {
		return false, err
	}

	// If there is a staged config, return false
	if count > 0 {
		return false, nil
	}

	timestamp := time.Now().Add(-1 * recencyWindow)
	var out []ts.RepositoryEID
	err = db.Select("repository_id").
		Table("ts_codeql_configs").
		Where("template_version = ? AND repository_id = ?", templateVersion, repoID).
		Where("validation_run_status = ? OR validation_run_status IS NULL", ts.CodeqlRunStatus_FAILED).
		Group("repository_id").
		Having("count(IF(created_at > ?, 1, NULL)) >= ? OR count(*) >= ?", timestamp, 1, overallLimit).
		Find(&out).Error

	if err != nil {
		return false, err
	}

	return len(out) == 0, nil
}

func (ma *Service) iterCodeqlRepos(ctx context.Context, batchSize int, filter ...func(*gorm.DB) *gorm.DB) iter.Seq2[[]*ts.CodeqlRepo, error] {

	return func(yield func([]*ts.CodeqlRepo, error) bool) {
		ctx, span := o11y.StartSpan(ctx)
		defer span.End()
		db := otelgorm.SetSpanToGorm(ctx, ma.db)

		var startID ts.CodeqlRepoID
		for {
			var repoIds []*ts.CodeqlRepo
			err := db.Model(&ts.CodeqlRepo{}).Scopes(filter...).
				Where("id > ?", startID).Order("id ASC").Limit(batchSize).
				Find(&repoIds).Error
			if err != nil {
				yield(nil, errors.Wrap(err, "failed to fetch next codeql repos"))
				return
			}
			if len(repoIds) == 0 {
				return
			}

			startID = repoIds[len(repoIds)-1].ID
			if !yield(repoIds, nil) {
				return
			}
		}
	}
}

func (ma *Service) IterReposRunningDefaultSetup(ctx context.Context, batchSize int) iter.Seq2[[]*ts.CodeqlRepo, error] {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	return ma.iterCodeqlRepos(ctx, batchSize, func(db *gorm.DB) *gorm.DB {
		return db.Where("current_config_id IS NOT NULL AND soft_deleted_at IS NULL")
	})
}

// GetCodeqlRepo returns the CodeQL repository configuration for the given repository ID.
// It will preload the validation runs for each config.
func (ma *Service) GetCodeqlRepo(ctx context.Context, repoID ts.RepositoryEID) (*ts.CodeqlRepo, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	validationRunPreload := func(db *gorm.DB) *gorm.DB {
		return db.Model(ts.CodeqlRun{}).
			Where("repository_id = ?", repoID).
			Where("run_type = ?", ts.CodeqlRunType_VALIDATION).
			Order("created_at DESC").Limit(1)
	}

	codeqlRepo := &ts.CodeqlRepo{}
	err := db.Where("repository_id = ?", repoID).Where("soft_deleted_at is null").
		Preload("CurrentConfig").
		Preload("StagedConfig").
		Preload("FailedConfig").
		Preload("CurrentConfig.ValidationRun", validationRunPreload).
		Preload("StagedConfig.ValidationRun", validationRunPreload).
		Preload("FailedConfig.ValidationRun", validationRunPreload).
		First(&codeqlRepo).Error
	if err != nil {
		if gorm.IsRecordNotFoundError(err) {
			return nil, ts.ErrCodeqlRepoNotFound
		}
		return nil, err
	}

	// Check that all validation runs have been loaded correctly
	if codeqlRepo.CurrentConfig != nil && codeqlRepo.CurrentConfig.ValidationRun == nil {
		return nil, errors.Wrap(ts.ErrCodeqlRunNotFound, "current config has no validation run")
	}
	if codeqlRepo.StagedConfig != nil && codeqlRepo.StagedConfig.ValidationRun == nil {
		return nil, errors.Wrap(ts.ErrCodeqlRunNotFound, "staged config has no validation run")
	}
	if codeqlRepo.FailedConfig != nil && codeqlRepo.FailedConfig.ValidationRun == nil {
		return nil, errors.Wrap(ts.ErrCodeqlRunNotFound, "failed config has no validation run")
	}

	return codeqlRepo, nil
}

func (ma *Service) DeleteCodeqlRepo(ctx context.Context, repoID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	now := time.Now()
	softDeletedAt := gormext.ConvertTime(&now)
	out := db.Exec(`UPDATE ts_codeql_repos SET soft_deleted_at = ? WHERE repository_id = ?`, softDeletedAt, repoID)
	err := out.Error
	if err != nil {
		return errors.Wrap(err, "failed to disable managed analyses")
	}

	if out.RowsAffected == 0 {
		return ts.ErrCodeqlRepoNotFound
	}

	return nil

}

func (ma *Service) GetNextScheduledRunTime(ctx context.Context, repoID ts.RepositoryEID) (time.Time, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	schedule := &ts.CodeqlSchedule{}
	err := db.Where("repository_id = ?", repoID).First(&schedule).Error
	if gorm.IsRecordNotFoundError(err) {
		return time.Time{}, ErrScheduleNotFound
	} else if err != nil {
		return time.Time{}, err
	}

	return schedule.NextRunAt.Time, nil
}

func (ma *Service) IsEnabled(ctx context.Context, repoID ts.RepositoryEID) (bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	var count int
	err := db.Model(ts.CodeqlRepo{}).
		Where("repository_id = ? AND soft_deleted_at IS NULL", repoID).
		Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

// GetDisabledTime returns the time at which default setup was disabled on the repo
// returns nil if it is enabled
// returns nil if it was never enabled
func (ma *Service) GetDisabledTime(ctx context.Context, repoID ts.RepositoryEID) (*time.Time, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, ma.db)

	codeqlRepo := &ts.CodeqlRepo{}
	err := db.Where("repository_id = ? AND soft_deleted_at IS NOT NULL", repoID).
		First(&codeqlRepo).Error
	if err != nil {
		if gorm.IsRecordNotFoundError(err) {
			return nil, nil // codeqlRepo not exists or is still enabled
		} else {
			return nil, err
		}
	}
	return &codeqlRepo.SoftDeletedAt.Time, nil
}

func (ma *Service) GetRepositoriesDisabledBetween(ctx context.Context, t1 time.Time, t2 time.Time) ([]ts.DisabledCodeqlRepo, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, ma.db))

	out := make([]ts.DisabledCodeqlRepo, 0)
	err := db.Table("ts_codeql_repos").
		Where("soft_deleted_at IS NOT NULL AND soft_deleted_at BETWEEN ? AND ?", t1, t2).
		Order("soft_deleted_at").
		Limit(1000).
		Find(&out).Error

	return out, err
}
