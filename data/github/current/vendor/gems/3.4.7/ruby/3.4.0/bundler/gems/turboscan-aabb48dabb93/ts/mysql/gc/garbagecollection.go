// Package gc contains a service for deleting old analyses.
package gc

import (
	"context"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
	"gocloud.dev/blob"
	"gocloud.dev/gcerrors"
)

type Service struct {
	db        *gorm.DB
	bucket    *blob.Bucket
	batchSize int
}

// NewService creates a garbage collection service with the given parameters
func NewService(db *gorm.DB, bucket *blob.Bucket, alertBatchSize int) *Service {
	s := &Service{
		db:        db,
		bucket:    bucket,
		batchSize: alertBatchSize,
	}
	return s
}

// FetchGarbageCollectableAnalyses gets a list of analyses that could potentially be cleaned.
func (s *Service) FetchGarbageCollectableAnalyses(ctx context.Context, age int, limit int, repoID int) ([]ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	var analysesToClean []ts.Analysis
	query := db.Select("ts_analyses.updated_at, ts_analyses.*")
	if repoID > 0 {
		query = query.Where("ts_analyses.repository_id = ?", repoID)
	}
	query = query.
		Where("ts_analyses.cleaned = 0").
		Where("ts_analyses.most_recent = 0").
		Where("ts_analyses.updated_at < NOW() - INTERVAL ? DAY", age).
		Order("ts_analyses.updated_at").
		Limit(limit)

	err := query.Find(&analysesToClean).Error
	if err != nil {
		return nil, errors.Wrap(err, "Finding analyses to clean failed.")
	}
	return analysesToClean, nil
}

// UpdateGarbageCollectionStatus sets the cleaned flag for the specific type
func (s *Service) UpdateGarbageCollectionStatus(ctx context.Context, analysis ts.Analysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	changes := &ts.Analysis{
		Cleaned: true,
	}
	if !analysis.AnalysisComplete {
		changes.AnalysisComplete = true
		changes.Failed = true
	}
	err := db.Model(&ts.Analysis{}).Where(&ts.Analysis{ID: analysis.ID}).Update(&changes).Error
	if err != nil {
		return errors.Wrap(err, "Writing analysis failed.")
	}
	return nil
}

// HardDeleteFixedAlerts permanently deletes the physical alerts from the specified analysis.
// If onlyFixes is true then only alerts that represent fixes are deleted.
func (s *Service) HardDeleteFixedAlerts(ctx context.Context, analysis ts.Analysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// Add some KVP values to the logger to distinguish various operations
	logger := appctx.Logger(ctx).WithFields(
		kvp.Int64("gh.turboscan.analysis_id", int64(analysis.ID)),
		analysis.RepositoryID.AsKVP(),
		kvp.String("gh.turboscan.model", "PhysicalAlerts"),
	)

	// Defensive check
	if analysis.MostRecent {
		return errors.New("cannot delete items from most recent analysis")
	}

	// Query for all alerts in the analysis
	idsQuery := db.Model(&ts.PhysicalAlert{}).
		Where("repository_id = ? ", analysis.RepositoryID).
		Where("analysis_id = ?", analysis.ID).
		Where("is_fixed = TRUE").
		Select("id")

	// Function for deletion. Must return the number of deleted entries.
	deleteFn := func(db *gorm.DB, ids []uint64) (int64, error) {
		// TODO: delete any orphaned code flows

		// Delete all related locations for the alerts in the batch.
		// Note: This is potentially unbounded as well, so chunking might make sense.
		//       However these do not accumulate in the same ways as fixes so we decided
		// 		 to not chunk unless we see a problem
		rlDelete := db.Delete(
			&ts.RelatedLocation{},
			"repository_id = ? AND physical_alert_id IN (?)",
			analysis.RepositoryID, ids,
		)
		if err := rlDelete.Error; err != nil {
			return 0, err
		}

		// Keeping the `relatedlocations.hard_deleted` metric for backwards compatibility (remove in 2023)
		appctx.Stats(ctx).Counter("relatedlocations.hard_deleted", stats.Tags{}, rlDelete.RowsAffected)
		appctx.Stats(ctx).Counter("gc_hard_deleted", stats.Tags{"table": "ts_related_locations"}, rlDelete.RowsAffected)

		// Delete the alerts
		deletes := db.Delete(&ts.PhysicalAlert{},
			"repository_id = ? AND id IN (?)",
			analysis.RepositoryID, ids,
		)
		if err := deletes.Error; err != nil {
			return 0, err
		}
		// Keeping the `physicalalerts.hard_deleted` for backwards compatibility (remove in 2023)
		appctx.Stats(ctx).Counter("physicalalerts.hard_deleted", stats.Tags{}, deletes.RowsAffected)
		appctx.Stats(ctx).Counter("gc_hard_deleted", stats.Tags{"table": "ts_physical_alerts"}, deletes.RowsAffected)

		return deletes.RowsAffected, nil
	}

	_, err := gormext.BatchDelete(logger, db, s.batchSize, idsQuery, deleteFn)
	return errors.Wrap(err, "Deleting Alerts failed.")
}

// HardDeleteDelivery permanently deletes the delivery with the given ID.
func (s *Service) HardDeleteDelivery(ctx context.Context, id ts.DeliveryID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	err := db.Delete(&ts.Delivery{}, "id = ?", id).Error

	if err != nil {
		return err
	}

	appctx.Stats(ctx).Counter("gc_hard_deleted", stats.Tags{"table": "ts_deliveries"}, 1)

	return nil
}

func (s *Service) HardDeleteExtractedFiles(ctx context.Context, analysis ts.Analysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// Defensive check
	if analysis.MostRecent {
		return errors.New("cannot delete items from most recent analysis")
	}

	deletes := db.Delete(&ts.AnalysisExtractedFiles{}, "repository_id = ? AND analysis_id = ?", analysis.RepositoryID, analysis.ID)
	if deletes.Error != nil {
		return deletes.Error
	}
	appctx.Stats(ctx).Counter("gc_hard_deleted", stats.Tags{"table": "ts_analysis_extracted_files"}, deletes.RowsAffected)

	deletes = db.Delete(&ts.AnalysisExtractedFilesMessages{}, "repository_id = ? AND analysis_id = ?", analysis.RepositoryID, analysis.ID)
	if deletes.Error != nil {
		return deletes.Error
	}
	appctx.Stats(ctx).Counter("gc_hard_deleted", stats.Tags{"table": "ts_analysis_extracted_files_messages"}, deletes.RowsAffected)

	return nil
}

// cleanSARIFAndUpdateDB performs the cleaning of the specified cleaning type and updates the analysis' cleanup status in the DB accordingly.
func (s *Service) cleanSARIFAndUpdateDB(ctx context.Context, clTypes []ts.CleaningType, analysis ts.Analysis) error {
	// Perform cleaning
	var err error
	for _, clType := range clTypes {
		switch clType {
		case ts.CleaningTypeSARIF:
			err = s.cleanSARIF(ctx, analysis)
		case ts.CleaningTypeAnalysisAssociations:
			err = s.cleanAnalysisAssociations(ctx, analysis)
		case ts.CleaningTypeIncomplete:
			// This is done when UpdateGarbageCollectionStatus calls MarkAsCleaned
		}
	}
	if err == nil {
		// Update the cleaning state in the db if cleaning was successful
		err = s.UpdateGarbageCollectionStatus(ctx, analysis)
	}

	if err != nil {
		appctx.Report(ctx, err, nil)
	}
	return err
}

// CleanAnalyses applies the specified cleaning type to the specified analyses.
// Cleaning is attempted on all analyses. Errors are logged and reported to
// Datadog, but not returned.
func (s *Service) CleanAnalyses(ctx context.Context, clTypes []ts.CleaningType, garbageCollectableAnalyses []ts.Analysis) {
	for _, analysis := range garbageCollectableAnalyses {
		if analysis.Cleaned {
			appctx.Stats(ctx).Counter("gc_analysis.skipped", stats.Tags{}, 1)
			continue
		}

		err := s.cleanSARIFAndUpdateDB(ctx, clTypes, analysis)

		key := "gc_analysis.succeeded"

		if err != nil {
			key = "gc_analysis.failed"
		}

		appctx.Stats(ctx).Counter(key, stats.Tags{}, 1)
	}
}

// cleanSARIF deletes the SARIF file from storage
func (s *Service) cleanSARIF(ctx context.Context, analysis ts.Analysis) error {
	appctx.Logger(ctx).Info("Removing SARIF file for analysis...", kvp.Int64("gh.turboscan.analysis_id", int64(analysis.ID)))
	err := s.bucket.Delete(ctx, analysis.SarifURL)
	if err != nil {
		if gcerrors.Code(err) != gcerrors.NotFound {
			appctx.Logger(ctx).WithError(err).Error("Removing SARIF file failed...", kvp.String("gh.turboscan.sarif_path", analysis.SarifURL))
		}
	}
	return err
}

// cleanAnalysisAssociations permanently deletes deliveries and fixed alerts for an analysis, returning true if cleaning succeeded
func (s *Service) cleanAnalysisAssociations(ctx context.Context, analysis ts.Analysis) error {
	logger := appctx.Logger(ctx).WithFields(
		kvp.Int64("gh.turboscan.analysis_id", int64(analysis.ID)),
		kvp.Int64("gh.turboscan.delivery_id", int64(analysis.DeliveryID)),
	)

	logger.Info("Removing fixed alerts for analysis...")
	err := s.HardDeleteFixedAlerts(ctx, analysis)
	if err != nil {
		logger.WithError(err).Error("Removing fixed alerts failed...")
	}

	logger.Info("Removing the delivery for analysis...")
	err = s.HardDeleteDelivery(ctx, analysis.DeliveryID)
	if err != nil {
		logger.WithError(err).Error("Removing delivery failed...")
	}

	err = s.HardDeleteExtractedFiles(ctx, analysis)
	if err != nil {
		logger.WithError(err).Error("Removing extracted files failed...")
	}

	return err
}
