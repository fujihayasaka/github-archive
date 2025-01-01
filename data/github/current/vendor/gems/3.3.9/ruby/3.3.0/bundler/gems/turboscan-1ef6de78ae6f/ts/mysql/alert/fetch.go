// Package alert contains functions for querying alert data.
package alert

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/alerts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/transforms"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

// FetchLogicalAlertsForPhysicalAlerts finds all logical alerts for a given set of physical alerts,
// by looking them up with the stable IDs.
func FetchLogicalAlertsForPhysicalAlerts(ctx context.Context, db *gorm.DB, repoID ts.RepositoryEID,
	newAlerts []*ts.PhysicalAlert) (map[alerts.StableAlertIdentifier]*ts.LogicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db = otelgorm.SetSpanToGorm(ctx, db)

	idMap := make(map[alerts.StableAlertIdentifier]*ts.LogicalAlert)

	stableIds := transforms.Map(newAlerts, func(alert *ts.PhysicalAlert) []byte {
		return alert.StableAlertIdentifier
	})

	// Fetch logical alerts in batches of 1000
	chunkSize := 1000
	for i := 0; i < len(stableIds); i += chunkSize {
		end := i + chunkSize
		if end > len(stableIds) {
			end = len(stableIds)
		}
		chunk := stableIds[i:end]
		var logicalAlerts []*ts.LogicalAlert
		err := db.Where("repository_id = ? AND stable_alert_identifier IN (?)", repoID, chunk).
			Preload("DefaultConfiguration", "repository_id = ?", repoID).
			Find(&logicalAlerts).
			Error
		if err != nil {
			return nil, errors.Wrap(err, "fetching sibling alerts has failed")
		}
		for _, la := range logicalAlerts {
			idMap[alerts.FromBytes(la.StableAlertIdentifier)] = la
		}
	}

	return idMap, nil
}
