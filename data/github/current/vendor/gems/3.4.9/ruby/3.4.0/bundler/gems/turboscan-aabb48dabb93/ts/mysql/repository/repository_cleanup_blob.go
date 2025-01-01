// this file adds additional functions on RepositoryCleanupService
// to handle deletion of blob storage data for a repository.

package repository

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/pkg/errors"
	"gocloud.dev/gcerrors"
)

const blobCleanupBatchSize = 1000 // Number of analyses to process in one batch

// BlobData deletes all blob data for the specified repository, it'll update the deleted repository table while it is running
// and return an error if it encounters a problem. If no errors are returned the deletion can be viewed as successful.
func (s *RepositoryCleanupService) BlobData(ctx context.Context, repositoryID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	var err error
	startTime := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("repo_cleanup.blob_data", nil, time.Since(startTime))
		appctx.Logger(ctx).WithError(err).Info("BlobData request",
			kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
			repositoryID.AsKVP(),
		)
	}()

	for !s.DeadlineExceeded() {
		analyses, err := s.FindAnalysesForSARIFDeletion(ctx, repositoryID, blobCleanupBatchSize)
		if err != nil {
			return err
		}
		if len(analyses) == 0 {
			return nil
		}
		var totalDeleted int64
		for _, a := range analyses {
			if s.DeadlineExceeded() {
				appctx.Logger(ctx).Info("Deadline exceeded - stopping execution")
				return ErrCleanupStopped
			}
			deleted, err := s.DeleteSARIF(ctx, a)
			if err != nil {
				// Technically some SARIFS might have been deleted,
				// but we are ok with being a bit imprecise here
				return err
			}
			totalDeleted += deleted
		}
		if s.dr != nil {
			err = s.dr.DeleteProgressBlobs(ctx, repositoryID, uint64(totalDeleted))
			if err != nil {
				return err
			}
		}
	}
	appctx.Logger(ctx).Info("Deadline exceeded - stopping execution")
	return ErrCleanupStopped
}

// FindAnalysesForSARIFDeletion fetches the analyses which are associated to the provided repository and that have uncleaned blob storage files.
func (s *RepositoryCleanupService) FindAnalysesForSARIFDeletion(ctx context.Context, repositoryID ts.RepositoryEID, limit int) ([]ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	analyses := []ts.Analysis{}
	err := db.
		Where("repository_id = ?", repositoryID).
		Where("sarif_url != ?", "").
		Where("sarif_id != ?", "").
		Limit(limit).
		Find(&analyses).Error

	if err != nil {
		return nil, errors.Wrap(err, "fetching analyses for deleted repository has failed")
	}
	return analyses, nil
}

// DeleteSARIF permanently deletes from Azure blob storage the SARIF file that is associated with the analysis,
// and makes updates to the database about this deletion.
func (s *RepositoryCleanupService) DeleteSARIF(ctx context.Context, analysis ts.Analysis) (int64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// Delete both SARIF files
	sarifsDeleted := int64(0)
	baseSarifDeleted, err := s.deleteFromBucket(ctx, analysis.RepositoryID, analysis.SarifURL)
	if err != nil {
		return sarifsDeleted, err
	}
	sarifsDeleted += baseSarifDeleted
	archivalSarifDeleted, err := s.deleteFromBucket(ctx, analysis.RepositoryID, analysis.ArchivalDataUrl)
	if err != nil {
		return sarifsDeleted, err
	}
	sarifsDeleted += archivalSarifDeleted

	// Update the analysis so we know it is cleaned
	err = s.db.Model(&ts.Analysis{}).Where(&ts.Analysis{ID: analysis.ID}).Update(map[string]interface{}{"sarif_url": "", "sarif_id": ""}).Error
	if err != nil {
		return sarifsDeleted, errors.Wrap(err, "Updating cleaned status of analysis failed.")
	}

	return sarifsDeleted, nil
}

// deleteFromBucket deletes the file for the specified url from the bucket if it exists. It returns 0 or 1 depending
// on whether there was a deleted object.
func (s *RepositoryCleanupService) deleteFromBucket(ctx context.Context, repositoryID ts.RepositoryEID, url string) (int64, error) {
	if url == "" {
		return 0, nil
	}
	err := s.sarifStore.Delete(ctx, url)
	if err != nil {
		// Not found errors are fine, we just move on, other errors are fatal
		if gcerrors.Code(err) != gcerrors.NotFound {
			return 0, err
		}
		return 0, nil
	}
	appctx.Logger(ctx).Info("Deleted blob.",
		repositoryID.AsKVP(),
		kvp.String("gh.turboscan.sarif_path", url))
	appctx.Stats(ctx).Counter("repo_cleanup.deleted", stats.Tags{"source": "blob"}, 1)
	return 1, nil
}
