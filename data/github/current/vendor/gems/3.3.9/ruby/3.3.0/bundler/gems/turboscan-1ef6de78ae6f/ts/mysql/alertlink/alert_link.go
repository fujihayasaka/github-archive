// Package alertlink handles interactions with alert link data. This package is for internal use only,
// you should probably use the alertlinks package instead.
package alertlink

import (
	"context"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql/gormbulk"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/transforms"
)

// Service handles interactions with tables used for alert links.
type Service struct {
	db *gorm.DB
}

// NewService returns a new AlertLink service with the given set of mysql Options
func NewService(db *gorm.DB) *Service {
	as := &Service{
		db: db,
	}
	return as
}

func (al *Service) AlertLinks(ctx context.Context, repoID ts.RepositoryEID, logicalAlerts []*ts.LogicalAlert) ([]*ts.AlertLink, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, al.db))

	alertIDs := make([]ts.LogicalAlertID, len(logicalAlerts))
	alertNumbersByID := make(map[ts.LogicalAlertID]uint32)
	for i, la := range logicalAlerts {
		alertIDs[i] = la.ID
		alertNumbersByID[la.ID] = la.Number
	}

	var links []*ts.AlertLink
	err := db.Table("ts_alert_links").
		Where("repository_id = ? and logical_alert_id in (?)", repoID, alertIDs).
		Find(&links).Error
	if err != nil {
		return nil, errors.Wrap(err, "fetching alert links has failed")
	}

	for _, link := range links {
		link.AlertNumber = alertNumbersByID[link.LogicalAlertID]
	}

	return links, nil
}

func (al *Service) CreateAlertLinks(ctx context.Context, repoID ts.RepositoryEID, logicalAlertIDs []ts.LogicalAlertID, pullRequestId ts.PullRequestEID, refNameBytes []byte) ([]*ts.AlertLink, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// We manually need to set the created_at and updated_at fields, as the gormbulk package does not support
	// setting and retrieving these fields.
	now := sqltime.Now()

	links := make([]*ts.AlertLink, len(logicalAlertIDs))
	for i, la := range logicalAlertIDs {
		links[i] = &ts.AlertLink{
			BaseModel: ts.BaseModel{
				CreatedAt: now,
				UpdatedAt: now,
			},
			RepositoryID:   repoID,
			LogicalAlertID: la,
			PullRequestID:  pullRequestId,
			Ref:            refNameBytes,
		}
	}

	// This should only set the IDs
	if err := gormbulk.Insert(ctx, &gormbulk.InsertOptions[ts.AlertLink]{
		DB:        al.db,
		Objects:   links,
		ChunkSize: 100,
	}); err != nil {
		return nil, errors.Wrap(err, "failed to insert alert links")
	}

	return links, nil
}

// CountAlertLinkByRef finds the counts of the alert links by the given repository and ref.
func (al *Service) CountAlertLinkByRef(ctx context.Context, repositoryID ts.RepositoryEID, ref ts.Ref) (uint64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, al.db))

	var count uint64
	err := db.Model(ts.AlertLink{}).Where("repository_id = ? AND ref = ?", repositoryID, []byte(ref)).Count(&count).Error
	if err != nil {
		return 0, errors.Wrap(err, "failed to count alert links")
	}

	return count, nil
}

// UpdatePRFromRef updates the alert links associated with the given ref to link to the given pull request instead.
// It returns a list of the the alert links that have been updated.
func (al *Service) UpdatePRFromRef(ctx context.Context, repositoryID ts.RepositoryEID, ref ts.Ref, pullRequestID ts.PullRequestEID) ([]*ts.AlertLink, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, al.db)

	links := []*ts.AlertLink{}
	err := db.Model(ts.AlertLink{}).
		Where("repository_id = ? AND ref = ?", repositoryID, []byte(ref)).
		Find(&links).
		Error
	if err != nil {
		return nil, errors.Wrap(err, "failed to update the alert link")
	}

	linkIDs := transforms.Map(links, func(l *ts.AlertLink) ts.AlertLinkID { return l.ID })

	updatedAt := sqltime.Now()
	err = db.Model(ts.AlertLink{}).
		Where("id in (?)", linkIDs).
		UpdateColumns(map[string]any{
			"pull_request_id": pullRequestID,
			"ref":             nil,
			"updated_at":      updatedAt,
		}).
		Error
	if err != nil {
		return nil, errors.Wrap(err, "failed to update the alert link")
	}

	for _, link := range links {
		link.PullRequestID = pullRequestID
		link.Ref = nil
		link.UpdatedAt = updatedAt
	}

	return links, nil
}
