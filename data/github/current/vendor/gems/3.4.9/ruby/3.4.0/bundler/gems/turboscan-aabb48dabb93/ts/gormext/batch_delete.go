package gormext

import (
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

// BatchDelete batches calls for deleting entities,
// returning the total number of deleted entities.
func BatchDelete(
	logger log.Logger,
	db *gorm.DB,
	batchSize int,
	idsQuery *gorm.DB,
	deleteFn func(*gorm.DB, []uint64) (int64, error),
) (int64, error) {

	// Count total number of entries to delete
	var total int64
	err := idsQuery.Count(&total).Error
	if err != nil {
		return 0, errors.Wrap(err, "Failed to count IDs to delete.")
	}
	logger.Info("Count of entries to delete...", kvp.Int64("gh.turboscan.entries", total))

	// Early exit if nothing to do
	if total <= 0 {
		return 0, nil
	}

	// Only fetch batch size items at a time
	idsQuery = idsQuery.Limit(batchSize)

	var ids []uint64
	err = idsQuery.Pluck("id", &ids).Error
	if err != nil {
		return 0, errors.Wrap(err, "Fetching IDs to delete failed.")
	}

	// Keep track of the number of deletedTot entries to guard against running forever
	deletedTot := int64(0)
	for len(ids) > 0 {
		deletedCount, err := deleteFn(db, ids)
		deletedTot += deletedCount
		if err != nil {
			return deletedTot, errors.Wrap(err, "Failed to delete batch")
		}

		// If we have deleted 0 entries or more entries than initially found
		// then something odd has happened, and we risk running forever.
		if deletedCount == 0 || deletedTot > total {
			return deletedTot, errors.Errorf("Deleted %d (%d total) entries but initial total was %d", deletedCount, deletedTot, total)
		}

		// Fetch another batch of entities to delete
		err = idsQuery.Pluck("id", &ids).Error
		if err != nil {
			return deletedTot, errors.Wrap(err, "Fetching IDs to delete failed.")
		}
	}
	return deletedTot, nil
}
