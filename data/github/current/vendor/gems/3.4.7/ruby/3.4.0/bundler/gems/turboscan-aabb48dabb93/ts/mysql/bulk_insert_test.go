package mysql

import (
	"context"
	"testing"

	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mysql/gormbulk"
	"github.com/stretchr/testify/require"
)

func newTimelineEvent(now sqltime.Time) *ts.TimelineEvent {
	return &ts.TimelineEvent{
		RepositoryID:   1,
		LogicalAlertID: 10,
		EventType:      ts.TimelineEventTypeUnknown,
		EventTimestamp: now,
	}
}

func TestInsertIgnoreWithBadCondition(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	now := sqltime.Now()

	errorScope := func(db *gorm.DB, _ *ts.TimelineEvent) *gorm.DB {
		// this will never find any records
		return db.Where("id = 0")
	}

	events := make([]*ts.TimelineEvent, 3)
	for i := range events {
		events[i] = newTimelineEvent(now)
	}

	err := gormbulk.InsertIgnore(ctx, errorScope, &gormbulk.InsertOptions[ts.TimelineEvent]{
		DB:        db,
		Objects:   events,
		ChunkSize: 2,
	})

	require.Error(t, err)
}

func TestInsertIgnoreScopeError(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	now := sqltime.Now()

	testError := errors.New("test")

	errorScope := func(db *gorm.DB, _ *ts.TimelineEvent) *gorm.DB {
		_ = db.AddError(testError)
		return db
	}

	events := make([]*ts.TimelineEvent, 3)
	for i := range events {
		events[i] = newTimelineEvent(now)
	}

	err := gormbulk.InsertIgnore(ctx, errorScope, &gormbulk.InsertOptions[ts.TimelineEvent]{
		DB:        db,
		Objects:   events,
		ChunkSize: 2,
	})

	require.Error(t, err)
	require.ErrorIs(t, err, testError)
}

func TestInsert(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	now := sqltime.Now()

	// Test where total rows is divisible by chunk size and where it is not
	for _, length := range []int{3, 4} {
		events := make([]*ts.TimelineEvent, length)
		for i := range events {
			events[i] = newTimelineEvent(now)
		}

		err := gormbulk.Insert(ctx, &gormbulk.InsertOptions[ts.TimelineEvent]{
			DB:        db,
			Objects:   events,
			ChunkSize: 2,
		})
		require.NoError(t, err)

		firstID := events[0].ID
		require.NotZero(t, firstID)
		for i, event := range events {
			expectedID := firstID + ts.TimelineEventID(i)
			require.Equal(t, expectedID, event.ID)
		}
	}
}
