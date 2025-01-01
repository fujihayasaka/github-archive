// Package timeline contains a service for reading and writing TimelineEvents
package timeline

import (
	"context"

	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mysql/gormbulk"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/transforms"
)

// Service is used to interact with *ts.TimelineEvent resources
// on MySQL.
type Service struct {
	db *gorm.DB
}

// NewService returns a new *Service that handles
// interaction with timeline events.
func NewService(db *gorm.DB) *Service {
	return &Service{
		db: db,
	}
}

// FindTimelineEvents retrieves timeline events for the given filter and options
func (t *Service) FindTimelineEvents(ctx context.Context, filter *ts.TimelineEventFilter, opt *ts.FindOptions) ([]*ts.TimelineEvent, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, t.db)
	return findTimelineEvents(ctx, db, filter, opt)
}

// WriteTimelineEvents writes the specified events to the database
func (t *Service) WriteTimelineEvents(ctx context.Context, events []*ts.TimelineEvent) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	return gormbulk.Insert(ctx, &gormbulk.InsertOptions[ts.TimelineEvent]{
		DB:        t.db,
		Objects:   transforms.Filter(events, func(e *ts.TimelineEvent) bool { return !e.NonUnique }),
		ChunkSize: 100,
	})
}

// findTimelineEvents retrieves timeline events for the given filter and
// options. Use this function only internally in the mysql package. It's safe
// to combine with other functions if needed or combine it in a transaction.
func findTimelineEvents(ctx context.Context, db *gorm.DB, filter *ts.TimelineEventFilter, opt *ts.FindOptions) ([]*ts.TimelineEvent, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db = otelgorm.SetSpanToGorm(ctx, db)

	var events []*ts.TimelineEvent

	// if the event relates to a specific analysis (which is the case for several event types, but not all),
	// we only want to fetch the event if the analysis has been marked as complete (i.e., everything from that analysis was committed
	// to the database).
	db = db.Select("ts_timeline_events.*, a.analysis_category AS category").Model(ts.TimelineEvent{}).
		Joins("LEFT JOIN ts_analyses a ON a.id = ts_timeline_events.analysis_id AND a.repository_id = ts_timeline_events.repository_id").
		Where("ts_timeline_events.repository_id = ?", filter.RepositoryID).
		Where("ts_timeline_events.logical_alert_id = ? AND (a.analysis_complete = TRUE OR a.id IS NULL)", filter.LogicalAlertID)

	db = opt.Apply(db)

	err := db.Find(&events).Error
	if gorm.IsRecordNotFoundError(err) {
		return nil, ts.ErrTimeLineEventsNotFound
	} else if err != nil {
		return nil, errors.Wrap(err, "finding timeline events has failed")
	}

	return events, nil
}
