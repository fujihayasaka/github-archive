package gc_test

import (
	"context"
	"encoding/binary"
	"fmt"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/tool"
	"github.com/github/turboscan/ts/sarif/samples"

	"github.com/github/turboscan/ts/mysql/gc"

	"github.com/jinzhu/gorm"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

func NewGarbageCollectorService(db *gorm.DB) *gc.Service {
	return gc.NewService(db, nil, 1) // Set batch size to 1 to test batching
}

var stableIDcounter = 0

func newStableID() []byte {
	stableIDcounter++
	stableID := make([]byte, 8)
	binary.BigEndian.PutUint64(stableID, uint64(stableIDcounter))
	return stableID
}

func TestFetchGarbageCollectableAnalyses(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewGarbageCollectorService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	now := time.Now()
	sqlNow := sqltime.Time{Time: now}
	sqlOneDayAgo := sqltime.Time{Time: now.AddDate(0, 0, -1)}
	sqlThirtyOneDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -31)}
	sqlThirtyTwoDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -32)}

	mostRecent := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	mostRecent.CreatedAt = sqlNow
	mostRecent.UpdatedAt = sqlNow
	dbtest.RequireCreate(t, db, mostRecent)

	oneDayOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	oneDayOld.CreatedAt = sqlOneDayAgo
	oneDayOld.UpdatedAt = sqlOneDayAgo
	dbtest.RequireCreate(t, db, oneDayOld)

	thirtyOneDaysOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	thirtyOneDaysOld.CreatedAt = sqlThirtyOneDaysAgo
	thirtyOneDaysOld.UpdatedAt = sqlThirtyOneDaysAgo
	dbtest.RequireCreate(t, db, thirtyOneDaysOld)

	thirtyTwoDaysOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	thirtyTwoDaysOld.CreatedAt = sqlThirtyTwoDaysAgo
	thirtyTwoDaysOld.UpdatedAt = sqlThirtyTwoDaysAgo
	dbtest.RequireCreate(t, db, thirtyTwoDaysOld)

	// fetch all older than 30 days
	analyses, err := s.FetchGarbageCollectableAnalyses(ctx, 30, 1000, 0)
	require.NoError(t, err)
	require.Len(t, analyses, 2)

	// fetch all analyses (method will never return 'most recent')
	analyses, err = s.FetchGarbageCollectableAnalyses(ctx, 0, 1000, 0)
	require.NoError(t, err)
	require.Len(t, analyses, 3)

	// fetch with limit
	analyses, err = s.FetchGarbageCollectableAnalyses(ctx, 30, 1, 0)
	require.NoError(t, err)
	require.Len(t, analyses, 1)

	cleaned := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
		Cleaned:            true,
	}
	cleaned.CreatedAt = sqlThirtyTwoDaysAgo
	cleaned.UpdatedAt = sqlThirtyTwoDaysAgo
	dbtest.RequireCreate(t, db, cleaned)
	// check cleaned filter
	analyses, err = s.FetchGarbageCollectableAnalyses(ctx, 0, 1000, 0)
	require.NoError(t, err)
	require.Len(t, analyses, 3)

	otherRepoID := ts.RepositoryEID(708)
	otherRepo := &ts.Analysis{
		RepositoryID:       otherRepoID,
		SourceRepositoryID: otherRepoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	otherRepo.CreatedAt = sqlThirtyTwoDaysAgo
	otherRepo.UpdatedAt = sqlThirtyTwoDaysAgo
	dbtest.RequireCreate(t, db, otherRepo)

	// filter by repo
	analyses, err = s.FetchGarbageCollectableAnalyses(ctx, 0, 1000, int(repoID))
	require.NoError(t, err)
	require.Len(t, analyses, 3)
	require.Equal(t, repoID, analyses[0].RepositoryID)

	analyses, err = s.FetchGarbageCollectableAnalyses(ctx, 0, 1000, int(otherRepoID))
	require.NoError(t, err)
	require.Len(t, analyses, 1)
	require.Equal(t, otherRepoID, analyses[0].RepositoryID)
}

func TestIncompleteAnalysisGC(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewGarbageCollectorService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	now := time.Now()
	sqlNow := sqltime.Time{Time: now}
	sqlOneDayAgo := sqltime.Time{Time: now.AddDate(0, 0, -1)}
	sqlThirtyOneDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -31)}
	sqlThirtyTwoDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -32)}

	mostRecent := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	mostRecent.CreatedAt = sqlNow
	mostRecent.UpdatedAt = sqlNow
	dbtest.RequireCreate(t, db, mostRecent)

	oneDayOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	oneDayOld.CreatedAt = sqlOneDayAgo
	oneDayOld.UpdatedAt = sqlOneDayAgo
	dbtest.RequireCreate(t, db, oneDayOld)

	thirtyOneDaysOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	thirtyOneDaysOld.CreatedAt = sqlThirtyOneDaysAgo
	thirtyOneDaysOld.UpdatedAt = sqlThirtyOneDaysAgo
	dbtest.RequireCreate(t, db, thirtyOneDaysOld)

	thirtyTwoDaysOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	thirtyTwoDaysOld.CreatedAt = sqlThirtyTwoDaysAgo
	thirtyTwoDaysOld.UpdatedAt = sqlThirtyTwoDaysAgo
	dbtest.RequireCreate(t, db, thirtyTwoDaysOld)

	// fetch analyses older than 30 days
	analyses, err := s.FetchGarbageCollectableAnalyses(ctx, 30, 1000, 0)
	require.NoError(t, err)
	require.Len(t, analyses, 2)

	// fetch all GC-able analyses
	analyses, err = s.FetchGarbageCollectableAnalyses(ctx, 0, 1000, 0)
	require.NoError(t, err)
	require.Len(t, analyses, 3)

	// clean _all_ incomplete analyses
	s.CleanAnalyses(ctx, []ts.CleaningType{ts.CleaningTypeIncomplete}, analyses)

	// no eligible analyses should remain
	analyses, err = s.FetchGarbageCollectableAnalyses(ctx, 0, 1000, 0)
	require.NoError(t, err)
	require.Empty(t, analyses)

	require.NoError(t, db.Find(&analyses).Error)
	for _, analysis := range analyses {
		t.Log(analysis)
	}

	// check that both analyses have been set to failed
	require.NoError(t, db.Find(&analyses, "failed = TRUE").Error)
	require.Len(t, analyses, 2)
	sort.Slice(analyses, func(i, j int) bool {
		return analyses[i].ID < analyses[j].ID
	})
	require.Equal(t, oneDayOld.ID, analyses[0].ID)
	require.Equal(t, thirtyTwoDaysOld.ID, analyses[1].ID)
}

func TestAlertsGC(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewGarbageCollectorService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)
	otherRepoID := ts.RepositoryEID(2)

	// We set up 3 analysis across 2 repos each with 2 results (one fixed one not).
	mostRecent := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	dbtest.RequireCreate(t, db, mostRecent)

	notMostRecent := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	dbtest.RequireCreate(t, db, notMostRecent)

	otherRepo := &ts.Analysis{
		RepositoryID:       otherRepoID,
		SourceRepositoryID: otherRepoID,
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	dbtest.RequireCreate(t, db, otherRepo)

	// Create 1 fixed and 1 open result for each analysis
	now := sqltime.Now()
	for idx, a := range []*ts.Analysis{mostRecent, notMostRecent, otherRepo} {
		open := &ts.PhysicalAlert{
			RepositoryID:          a.RepositoryID,
			AnalysisID:            a.ID,
			Message:               fmt.Sprintf("Alert %d (open)", idx),
			StableAlertIdentifier: newStableID(),
			LastStateChangeAt:     now,
		}
		// TODO: Move this to RequireCreate
		open.CreatedAt = sqltime.Now()
		open.UpdatedAt = sqltime.Now()

		lastSeen := ts.AnalysisID(99)
		fixed := &ts.PhysicalAlert{
			RepositoryID:          a.RepositoryID,
			AnalysisID:            a.ID,
			Message:               fmt.Sprintf("Alert %d (fixed)", idx),
			LastSeenAnalysisID:    &lastSeen,
			StableAlertIdentifier: newStableID(),
			LastStateChangeAt:     now,
		}
		fixed.CreatedAt = sqltime.Now()
		fixed.UpdatedAt = sqltime.Now()

		dbtest.RequireCreate(t, db, open)
		dbtest.RequireCreate(t, db, fixed)
	}
	totAlerts := 6
	dbtest.RequireCount(t, totAlerts, db.Model(&ts.PhysicalAlert{}))

	// Perform the GC - we intentionally do not include the analysis from otherRepo
	s.CleanAnalyses(ctx, []ts.CleaningType{ts.CleaningTypeAnalysisAssociations}, []ts.Analysis{*mostRecent, *notMostRecent})

	// Check that we only deleted 1 result (from notMostRecent)
	totAlerts--
	dbtest.RequireCount(t, totAlerts, db.Model(&ts.PhysicalAlert{}))

	// Check that we flagged the analysis as cleaned
	require.False(t, notMostRecent.Cleaned)
	require.NoError(t, db.Find(&notMostRecent, "id=?", notMostRecent.ID).Error)
	require.True(t, notMostRecent.Cleaned)
}

func TestDeletesDeliveriesWhenCleaningAnalyses(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewGarbageCollectorService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	now := time.Now()
	sqlThirtyOneDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -31)}
	sqlThirtyTwoDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -32)}
	sqlTwoDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -2)}

	ref := []byte("refs/heads/branch")

	firstDelivery := &ts.Delivery{
		RepositoryID: repoID,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha(strings.Repeat("a", 40)),
		Ref:          ref,
		AnalysisKey:  "woot",
	}

	secondDelivery := &ts.Delivery{
		RepositoryID: repoID,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha(strings.Repeat("b", 40)),
		Ref:          ref,
		AnalysisKey:  "woot",
	}

	thirdDelivery := &ts.Delivery{
		RepositoryID: repoID,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha(strings.Repeat("c", 40)),
		Ref:          ref,
		AnalysisKey:  "woot",
	}

	dbtest.RequireCreate(t, db, firstDelivery)
	dbtest.RequireCreate(t, db, secondDelivery)
	dbtest.RequireCreate(t, db, thirdDelivery)

	thirtyOneDaysOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/bbb"),
		ToolID:             1,
		DeliveryID:         firstDelivery.ID,
	}
	thirtyOneDaysOld.CreatedAt = sqlThirtyOneDaysAgo
	thirtyOneDaysOld.UpdatedAt = sqlThirtyOneDaysAgo
	dbtest.RequireCreate(t, db, thirtyOneDaysOld)

	thirtyTwoDaysOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
		DeliveryID:         secondDelivery.ID,
	}
	thirtyTwoDaysOld.CreatedAt = sqlThirtyTwoDaysAgo
	thirtyTwoDaysOld.UpdatedAt = sqlThirtyTwoDaysAgo
	dbtest.RequireCreate(t, db, thirtyTwoDaysOld)

	twoDaysOld := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/ccc"),
		ToolID:             1,
		DeliveryID:         thirdDelivery.ID,
	}
	twoDaysOld.CreatedAt = sqlTwoDaysAgo
	twoDaysOld.UpdatedAt = sqlTwoDaysAgo
	dbtest.RequireCreate(t, db, twoDaysOld)

	dbtest.RequireCount(t, 3, db.Model(&ts.Analysis{}))
	dbtest.RequireCount(t, 3, db.Model(&ts.Delivery{}))

	analyses, err := s.FetchGarbageCollectableAnalyses(ctx, 30, 1000, 0)
	require.NoError(t, err)

	s.CleanAnalyses(ctx, []ts.CleaningType{ts.CleaningTypeAnalysisAssociations}, analyses)

	dbtest.RequireCount(t, 3, db.Model(&ts.Analysis{}))
	dbtest.RequireCount(t, 1, db.Model(&ts.Delivery{}))
}

func TestDeletesExtractedFiles(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewGarbageCollectorService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	now := time.Now()
	sqlThirtyOneDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -31)}
	sqlTwoDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -2)}

	doc := samples.RequireSARIF(t, "../sarif/testdata/toolExecutionNotifications.sarif")
	toolService := tool.NewService(db, limits.TestLimitSelector())
	ams := analysismessage.NewService(db)

	a1 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/bbb"),
		Tool: &ts.Tool{
			ID:            1519,
			GUID:          "guid",
			CanonicalName: "CodeQL",
		},
		ToolID: 1519,
	}
	a1.CreatedAt = sqlThirtyOneDaysAgo
	a1.UpdatedAt = sqlThirtyOneDaysAgo
	dbtest.RequireCreate(t, db, a1)

	err := toolService.CreateAnalysisExtractedFiles(ctx, a1, doc.Runs[0], ams)
	require.NoError(t, err)
	dbtest.RequireCount(t, 1, db.Model(ts.AnalysisExtractedFiles{}))

	a2 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/ccc"),
		Tool: &ts.Tool{
			ID:            1519,
			GUID:          "guid",
			CanonicalName: "CodeQL",
		},
		ToolID: 1519,
	}
	a2.CreatedAt = sqlTwoDaysAgo
	a2.UpdatedAt = sqlTwoDaysAgo
	dbtest.RequireCreate(t, db, a2)
	err = toolService.CreateAnalysisExtractedFiles(ctx, a2, doc.Runs[0], ams)
	require.NoError(t, err)
	dbtest.RequireCount(t, 2, db.Model(ts.AnalysisExtractedFiles{}))

	analyses, err := s.FetchGarbageCollectableAnalyses(ctx, 30, 1000, 0)
	require.NoError(t, err)

	s.CleanAnalyses(ctx, []ts.CleaningType{ts.CleaningTypeAnalysisAssociations}, analyses)
	dbtest.RequireCount(t, 1, db.Model(ts.AnalysisExtractedFiles{}))
	f := &ts.AnalysisExtractedFiles{}
	require.NoError(t, db.Find(f).Error)
	require.Equal(t, a2.ID, f.AnalysisID)
}

func TestDeletesExtractedFilesMessages(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewGarbageCollectorService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	now := time.Now()
	sqlThirtyOneDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -31)}
	sqlTwoDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -2)}
	a1 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/bbb"),
		Tool: &ts.Tool{
			ID:            1519,
			GUID:          "guid",
			CanonicalName: "CodeQL",
		},
		ToolID: 1519,
	}
	a1.CreatedAt = sqlThirtyOneDaysAgo
	a1.UpdatedAt = sqlThirtyOneDaysAgo
	dbtest.RequireCreate(t, db, a1)

	m1 := &ts.AnalysisExtractedFilesMessages{
		RepositoryID: repoID,
		AnalysisID:   a1.ID,
		Path:         "foo",
		Message:      "bar",
	}
	dbtest.RequireCreate(t, db, m1)

	a2 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/ccc"),
		Tool: &ts.Tool{
			ID:            1519,
			GUID:          "guid",
			CanonicalName: "CodeQL",
		},
		ToolID: 1519,
	}
	a2.CreatedAt = sqlTwoDaysAgo
	a2.UpdatedAt = sqlTwoDaysAgo
	dbtest.RequireCreate(t, db, a2)
	m2 := &ts.AnalysisExtractedFilesMessages{
		RepositoryID: repoID,
		AnalysisID:   a2.ID,
		Path:         "foo",
		Message:      "bar",
	}
	dbtest.RequireCreate(t, db, m2)
	analyses, err := s.FetchGarbageCollectableAnalyses(ctx, 30, 1000, 0)
	require.NoError(t, err)

	s.CleanAnalyses(ctx, []ts.CleaningType{ts.CleaningTypeAnalysisAssociations}, analyses)
	dbtest.RequireCount(t, 1, db.Model(ts.AnalysisExtractedFilesMessages{}))
	m := &ts.AnalysisExtractedFilesMessages{}
	require.NoError(t, db.Find(m).Error)
	require.Equal(t, a2.ID, m.AnalysisID)
}

func TestAnalysisStateAfterGCAndTipDeletion(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	s := NewGarbageCollectorService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	a1 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	dbtest.RequireCreate(t, db, a1)

	a2 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		BaselineID:         &a1.ID,
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	dbtest.RequireCreate(t, db, a2)

	// Perform the GC on A1
	s.CleanAnalyses(ctx, []ts.CleaningType{ts.CleaningTypeAnalysisAssociations}, []ts.Analysis{*a1})
	require.NoError(t, db.Find(&a1, "id=?", a1.ID).Error)
	require.True(t, a1.Cleaned)

	// Delete the tip (A2)
	baseline, err := as.SoftDeleteAnalysis(context.Background(), repoID, a2.ID, true)
	require.NoError(t, err)
	require.Nil(t, baseline) // baseline should be nil as it was garbage collected

	// Check A1 status
	require.NoError(t, db.Find(&a1, "id=?", a1.ID).Error)
	require.False(t, a1.MostRecent) // Even if after deleting a2 is the most recent, as a1 was garbage collected it is not marked as most recent
}

func TestMarkAsCleaned(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewGarbageCollectorService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	now := time.Now()
	sqlOneDayAgo := sqltime.Time{Time: now.AddDate(0, 0, -1)}

	complete := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	complete.CreatedAt = sqlOneDayAgo
	complete.UpdatedAt = sqlOneDayAgo
	dbtest.RequireCreate(t, db, complete)

	incomplete := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
	}
	incomplete.CreatedAt = sqlOneDayAgo
	incomplete.UpdatedAt = sqlOneDayAgo
	dbtest.RequireCreate(t, db, incomplete)

	s.CleanAnalyses(ctx, []ts.CleaningType{ts.CleaningTypeAnalysisAssociations}, []ts.Analysis{*complete})
	require.NoError(t, db.Find(&complete, "id=?", complete.ID).Error)
	require.True(t, complete.Cleaned)

	s.CleanAnalyses(ctx, []ts.CleaningType{ts.CleaningTypeIncomplete}, []ts.Analysis{*incomplete})
	require.NoError(t, db.Find(&incomplete, "id=?", incomplete.ID).Error)
	require.True(t, incomplete.AnalysisComplete)
	require.True(t, incomplete.Failed)
	require.True(t, incomplete.Cleaned)
}
