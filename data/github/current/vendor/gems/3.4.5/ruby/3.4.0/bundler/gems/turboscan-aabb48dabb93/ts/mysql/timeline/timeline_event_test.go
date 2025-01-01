package timeline

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func setUpTimelineEventTest(t *testing.T, db *gorm.DB) (*Service, context.Context, *ts.TimelineEventFilter) {
	t.Helper()
	return NewService(db),
		context.Background(),
		&ts.TimelineEventFilter{
			RepositoryID:   ts.RepositoryEID(6),
			LogicalAlertID: ts.LogicalAlertID(42),
		}
}

func TestTimelineEventService_FindTimelineEvents_NoData(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tles, ctx, filter := setUpTimelineEventTest(t, db)

	results, err := tles.FindTimelineEvents(ctx, filter, &ts.FindOptions{})
	require.NoError(t, err)
	require.Len(t, results, 0)
}

func TestTimelineEventService_FindTimelineEvents_NoMatchingData(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tles, ctx, filter := setUpTimelineEventTest(t, db)

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 23,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		EventTimestamp: sqltime.Now(),
	})

	results, err := tles.FindTimelineEvents(ctx, filter, &ts.FindOptions{})
	require.NoError(t, err)
	require.Len(t, results, 0)
}

func TestTimelineEventService_FindTimelineEvents_OneMatch(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tles, ctx, filter := setUpTimelineEventTest(t, db)

	an := &ts.Analysis{
		RepositoryID:       ts.RepositoryEID(6),
		SourceRepositoryID: ts.RepositoryEID(6),
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		Category:           "some_category",
		Ref:                []byte("refs/heads/master"),
	}
	dbtest.RequireCreate(t, db, an)

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 23,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an.ID,
		EventTimestamp: sqltime.Now(),
	})

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 42,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an.ID,
		EventTimestamp: sqltime.Now(),
	})

	results, err := tles.FindTimelineEvents(ctx, filter, &ts.FindOptions{})
	require.NoError(t, err)
	require.Len(t, results, 1)
	require.Equal(t, ts.LogicalAlertID(42), results[0].LogicalAlertID)
	require.Equal(t, "some_category", results[0].Category)
}

func TestTimelineEventService_FindTimelineEvents_TwoMatches(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tles, ctx, filter := setUpTimelineEventTest(t, db)

	an1 := &ts.Analysis{
		RepositoryID:       ts.RepositoryEID(6),
		SourceRepositoryID: ts.RepositoryEID(6),
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		Category:           "some_category1",
		Ref:                []byte("refs/heads/master"),
	}
	dbtest.RequireCreate(t, db, an1)

	an2 := &ts.Analysis{
		RepositoryID:       ts.RepositoryEID(6),
		SourceRepositoryID: ts.RepositoryEID(6),
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		Category:           "some_category2",
		Ref:                []byte("refs/heads/master"),
	}
	dbtest.RequireCreate(t, db, an2)

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 23,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an1.ID,
		EventTimestamp: sqltime.Now(),
	})

	// Insert out-of-order to test sorting
	earlier := sqltime.Date(2017, time.February, 16, 0, 0, 0, 0, time.UTC)
	later := sqltime.Date(2018, time.February, 16, 0, 0, 0, 0, time.UTC)

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 42,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an2.ID,
		EventTimestamp: later,
	})

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 42,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an1.ID,
		EventTimestamp: earlier,
	})

	opts := &ts.FindOptions{SortBy: "ts_timeline_events.event_timestamp"}

	results, err := tles.FindTimelineEvents(ctx, filter, opts)
	require.NoError(t, err)
	require.Len(t, results, 2)
	require.Equal(t, earlier, results[0].EventTimestamp)
	require.Equal(t, "some_category1", results[0].Category)
	require.Equal(t, "some_category2", results[1].Category)
}

func TestTimelineEventService_FindTimelineEvents_CompleteAnalysis(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tles, ctx, filter := setUpTimelineEventTest(t, db)

	an := &ts.Analysis{
		RepositoryID:       ts.RepositoryEID(6),
		SourceRepositoryID: ts.RepositoryEID(6),
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		Ref:                []byte("refs/heads/master"),
	}
	dbtest.RequireCreate(t, db, an)

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 23,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an.ID,
		EventTimestamp: sqltime.Now(),
	})

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 42,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an.ID,
		EventTimestamp: sqltime.Now(),
	})

	opts := &ts.FindOptions{SortBy: "ts_timeline_events.event_timestamp"}

	// test that events associated with a complete analysis are returned
	results, err := tles.FindTimelineEvents(ctx, filter, opts)
	require.NoError(t, err)
	require.Len(t, results, 1)
	require.Equal(t, ts.LogicalAlertID(42), results[0].LogicalAlertID)
}

func TestTimelineEventService_FindTimelineEvents_IncompleteAnalysis(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tles, ctx, filter := setUpTimelineEventTest(t, db)

	an := &ts.Analysis{
		RepositoryID:       ts.RepositoryEID(6),
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		SourceRepositoryID: ts.RepositoryEID(6),
		Ref:                []byte("refs/heads/master"),
	}
	dbtest.RequireCreate(t, db, an)

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 23,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an.ID,
		EventTimestamp: sqltime.Now(),
	})

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 42,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     an.ID,
		EventTimestamp: sqltime.Now(),
	})

	opts := &ts.FindOptions{SortBy: "ts_timeline_events.event_timestamp"}

	// test that events associated with an incomplete analysis are not returned
	results, err := tles.FindTimelineEvents(ctx, filter, opts)
	require.NoError(t, err)
	require.Len(t, results, 0)
}

func TestTimelineEventService_FindTimelineEvents_HandlesAnalysisNotSet(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tles, ctx, filter := setUpTimelineEventTest(t, db)

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 42,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		EventTimestamp: sqltime.Now(),
	})

	results, err := tles.FindTimelineEvents(ctx, filter, &ts.FindOptions{})
	require.NoError(t, err)
	require.Len(t, results, 1)
	require.Equal(t, ts.LogicalAlertID(42), results[0].LogicalAlertID)
	require.Equal(t, "", results[0].Category)
}

func TestTimelineEventService_FindTimelineEvents_HandlesAnalysisNotFound(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tles, ctx, filter := setUpTimelineEventTest(t, db)

	db.Create(&ts.TimelineEvent{
		RepositoryID:   ts.RepositoryEID(6),
		LogicalAlertID: 42,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		AnalysisID:     ts.AnalysisID(13),
		EventTimestamp: sqltime.Now(),
	})

	results, err := tles.FindTimelineEvents(ctx, filter, &ts.FindOptions{})
	require.NoError(t, err)
	require.Len(t, results, 1)
	require.Equal(t, ts.LogicalAlertID(42), results[0].LogicalAlertID)
	require.Equal(t, "", results[0].Category)
}
