package alert

import (
	"context"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func TestLoadAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := TestService(db)

	// A loader with no filters should load all alerts.
	setup2alerts(t, db)
	loader := as.NewLoader(&ts.Repository{RepositoryID: 1})
	require.Len(t, loadAllAlerts(t, loader), 2)
}

func TestLoadMaxAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := TestService(db)

	// A loader with no filters should load all alerts.
	setup2alerts(t, db)
	loader := as.NewLoader(&ts.Repository{RepositoryID: 1})
	loader.SetMaxLoad(1)
	loader.SetBatchSize(1) // The max is not strict so we need to set the batch size to 1 to ensure we only load 1 alert.
	require.Len(t, loadAllAlerts(t, loader), 1)
}

func TestAutofixMetadata(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := TestService(db)

	setup2alerts(t, db)
	loader := as.NewLoader(&ts.Repository{RepositoryID: 1, DefaultRef: []byte("refs/heads/main")})
	alerts := loadAllAlerts(t, loader)
	require.Len(t, alerts, 2)
	// The first alert is not eligible for an autofix, but the second is.
	require.False(t, alerts[0].AutofixEligible)
	require.True(t, alerts[1].AutofixEligible)
	// The first alert does not have any suggested fix, the second does
	require.Nil(t, alerts[0].SuggestedFixAlert)
	require.NotNil(t, alerts[1].SuggestedFixAlert)
	require.Equal(t, ts.SuggestedFixAlertStateValid, alerts[1].SuggestedFixAlert.State)
	require.False(t, alerts[1].SuggestedFixAlert.WasSuggestionUsed())
}

// setup2alerts creates 2 alerts in the database.
func setup2alerts(t *testing.T, db *gorm.DB) {
	t.Helper()
	l1 := &ts.LogicalAlert{ID: 1,
		Number:                1,
		RepositoryID:          1,
		StableAlertIdentifier: []byte("1"),
		SarifIdentifier:       "foo/bar",
		Rule: &ts.Rule{
			Tool: &ts.Tool{
				CanonicalName: ts.ToolName("CodeQL"),
				GUID:          "1",
			},
		},
	}
	dbtest.RequireCreate(t, db, l1)
	p1 := &ts.PhysicalAlert{
		RepositoryID:          1,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: []byte("1"),
		LastStateChangeAt:     l1.CreatedAt,
	}
	dbtest.RequireCreate(t, db, p1)
	l2 := &ts.LogicalAlert{ID: 2,
		Number:                2,
		RepositoryID:          1,
		StableAlertIdentifier: []byte("2"),
		SarifIdentifier:       "rb/unsafe-code-construction",
		Rule: &ts.Rule{
			Tool: &ts.Tool{
				CanonicalName: ts.ToolName("CodeQL"),
				GUID:          "2",
			},
		},
	}
	dbtest.RequireCreate(t, db, l2)
	p2 := &ts.PhysicalAlert{
		RepositoryID:          1,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: []byte("2"),
		LastStateChangeAt:     l2.CreatedAt,
	}
	dbtest.RequireCreate(t, db, p2)
	sf := &ts.SuggestedFixAlert{
		RepositoryID:       1,
		LogicalAlertNumber: 2,
		State:              ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:     l2.CreatedAt,
		RefBytes:           []byte("refs/heads/main"),
		RequestedAt:        sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, sf)
}

// loadAllAlerts loads all alerts from the loader.
func loadAllAlerts(t *testing.T, loader *Loader) []*ts.LogicalAlert {
	t.Helper()
	ctx := context.Background()
	acc := []*ts.LogicalAlert{}
	require.NoError(t, loader.BatchedLoad(ctx, func(alerts []*ts.LogicalAlert) error {
		acc = append(acc, alerts...)
		return nil
	}))
	return acc
}

func TestFixedAt_InvalidAnalyses(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := TestService(db)

	testRepoID := ts.RepositoryEID(1)
	defaultRef := []byte("refs/heads/main")

	loader := as.NewLoader(&ts.Repository{RepositoryID: testRepoID, DefaultRef: defaultRef})

	// Test that the last fix date is set correctly
	baseAnalysis := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Ref:                defaultRef,
		Category:           "1",
		CommitOid:          "aaaa",
		AnalysisComplete:   true,
	}

	// The alert we are aiming to fix
	la := &ts.LogicalAlert{
		ID:                    1,
		Number:                1,
		RepositoryID:          testRepoID,
		StableAlertIdentifier: []byte("1"),
		SarifIdentifier:       "foo/bar",
		Rule: &ts.Rule{
			Tool: &ts.Tool{
				CanonicalName: ts.ToolName("CodeQL"),
				GUID:          "1",
			},
		},
	}
	dbtest.RequireCreate(t, db, &la)

	// The shared information for the physical alerts
	basePAlert := ts.PhysicalAlert{
		RuleID:                la.RuleID,
		RepositoryID:          testRepoID,
		LogicalAlertID:        la.ID,
		StableAlertIdentifier: la.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelWarning,
	}

	// We start from an abstract analysis. We only care about the ID
	baselineID1 := ts.AnalysisID(9999)

	// Add a failed analysis
	failedAnalysisPre := baseAnalysis
	failedAnalysisPre.BaselineID = &baselineID1
	failedAnalysisPre.Failed = true
	dbtest.RequireCreate(t, db, &failedAnalysisPre)

	// Add a deleted analysis
	deletedAnalysisPre := baseAnalysis
	deletedAnalysisPre.BaselineID = &baselineID1
	deletedAnalysisPre.MarkAsDeleted()
	dbtest.RequireCreate(t, db, &deletedAnalysisPre)

	// Add an incomplete analysis
	incompleteAnalysisPre := baseAnalysis
	incompleteAnalysisPre.BaselineID = &baselineID1
	incompleteAnalysisPre.AnalysisComplete = false
	dbtest.RequireCreate(t, db, &incompleteAnalysisPre)

	// We fix the alert in this analysis
	fixAnalysis := baseAnalysis
	fixAnalysis.BaselineID = &baselineID1
	dbtest.RequireCreate(t, db, &fixAnalysis)

	// Another failed analysis
	failedAnalysisPost := baseAnalysis
	failedAnalysisPost.BaselineID = &baselineID1
	failedAnalysisPost.Failed = true
	dbtest.RequireCreate(t, db, &failedAnalysisPost)

	// Another deleted analysis
	deletedAnalysisPost := baseAnalysis
	deletedAnalysisPost.BaselineID = &baselineID1
	deletedAnalysisPost.MarkAsDeleted()
	dbtest.RequireCreate(t, db, &deletedAnalysisPost)

	// Another incomplete analysis
	incompleteAnalysisPost := baseAnalysis
	incompleteAnalysisPost.BaselineID = &baselineID1
	incompleteAnalysisPost.AnalysisComplete = false
	dbtest.RequireCreate(t, db, &incompleteAnalysisPost)

	// Finally we add a most recent analysis
	mostRecentAnalysis := baseAnalysis
	mostRecentAnalysis.BaselineID = &fixAnalysis.ID
	mostRecentAnalysis.MostRecent = true
	dbtest.RequireCreate(t, db, &mostRecentAnalysis)

	// We create the physical alerts for the logical alert
	p1 := basePAlert
	p1.AnalysisID = mostRecentAnalysis.ID
	p1.LastSeenAnalysisID = &baselineID1
	p1.LastStateChangeAt = sqltime.Now()
	dbtest.RequireCreate(t, db, &p1)

	alerts := loadAllAlerts(t, loader)
	require.Len(t, alerts, 1)

	require.Equal(t, fixAnalysis.CreatedAt, *alerts[0].LastObservedFixAt)
	require.Equal(t, fixAnalysis.CreatedAt, *alerts[0].GetFixedAt())
	require.NotEqual(t, failedAnalysisPre.CreatedAt, *alerts[0].LastObservedFixAt)
	require.NotEqual(t, failedAnalysisPost.CreatedAt, *alerts[0].LastObservedFixAt)
	require.NotEqual(t, deletedAnalysisPre.CreatedAt, *alerts[0].LastObservedFixAt)
	require.NotEqual(t, deletedAnalysisPost.CreatedAt, *alerts[0].LastObservedFixAt)
	require.NotEqual(t, incompleteAnalysisPre.CreatedAt, *alerts[0].LastObservedFixAt)
	require.NotEqual(t, incompleteAnalysisPost.CreatedAt, *alerts[0].LastObservedFixAt)
}
