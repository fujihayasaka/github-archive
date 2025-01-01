package twirp

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/proto"
)

// The GetAlertsForInsightsBackfill endpoint is e2e tested via cassettes.
// These tests focus on internal/suppelmentary behavior.

func TestGetAlertsForInsightsBackfillPagination(t *testing.T) {
	nextCursor := "foobar"
	updatedAfter := time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)

	// If no pagination provided, use defaults
	req := &proto.GetAlertsForInsightsBackfillRequest{}
	pagination, err := toPagination(req)
	require.NoError(t, err)
	require.Equal(t, uint32(0), pagination.Offset)
	require.Equal(t, ts.MAX_PAGE_SIZE, pagination.Limit)
	require.Nil(t, pagination.Cursor)

	// If NextCursor provided, use it
	req = &proto.GetAlertsForInsightsBackfillRequest{
		NextCursor: nextCursor,
	}
	pagination, err = toPagination(req)
	require.NoError(t, err)
	require.Equal(t, uint32(0), pagination.Offset)
	require.Equal(t, ts.MAX_PAGE_SIZE, pagination.Limit)
	require.Equal(t, nextCursor, pagination.Cursor.String)

	// If UpdatedAfter provided, construct a cursor from it
	req = &proto.GetAlertsForInsightsBackfillRequest{
		UpdatedAfter: timestamppb.New(updatedAfter),
	}
	pagination, err = toPagination(req)
	require.NoError(t, err)
	require.Equal(t, uint32(0), pagination.Offset)
	require.Equal(t, ts.MAX_PAGE_SIZE, pagination.Limit)
	require.Equal(t, "eyJhbGVydF9pZCI6MCwiaW5zaWdodHNfdXBkYXRlZF9hdCI6MTU3NzkyMzIwMDAwMH0K", pagination.Cursor.String)

	// If both provided, use NextCursor
	req = &proto.GetAlertsForInsightsBackfillRequest{
		NextCursor:   nextCursor,
		UpdatedAfter: timestamppb.New(updatedAfter),
	}
	pagination, err = toPagination(req)
	require.NoError(t, err)
	require.Equal(t, uint32(0), pagination.Offset)
	require.Equal(t, ts.MAX_PAGE_SIZE, pagination.Limit)
	require.Equal(t, "foobar", pagination.Cursor.String)
}

func TestGetAlertsForInsightsBackfill_E2E(t *testing.T) {
	db, ctx, resolver := setupGetAlertsForInsightsBackfillTests(t)

	commit := "da39a3ee5e6b4b0d3255bfef95601890afd80709"
	repoID := ts.RepositoryEID(1)
	analysis := setupFirstAnalysis(t, db, repoID, commit)
	rule1 := &ts.Rule{
		Name:             "Rule1",
		ShortDescription: "Rule 1",
		FullDescription:  "This is Rule 1",
		SeverityLevel:    ts.SeverityLevelError,
		SarifIdentifier:  "js/one",
	}
	rule1.SetTags([]string{"rule1"})
	dbtest.RequireCreate(t, db, rule1)

	// Create a different analysis
	analysis = createAnalysis(t, db, repoID, analysis.ToolVersion, commit, "js2")

	alertId := 2
	alertNumber := 101

	createNewAlertCombo(t, db, analysis, rule1, alertId, uint8(alertNumber))

	fixed := false
	enabled := true
	err := resolver.es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FullDescription:     "XSS is good",
				SarifIdentifier:     rule1.SarifIdentifier,
				FixedOnDefault:      &fixed,
				Resolution:          "AlertResolutionNone",
				CodeScanningEnabled: &enabled,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
				InsightsUpdatedAt:   &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				Number:              uint32(alertNumber),
				CanonicalID:         "2",
				FullDescription:     "XSS is bad",
				SarifIdentifier:     rule1.SarifIdentifier,
				FixedOnDefault:      &fixed,
				Resolution:          "AlertResolutionNone",
				CodeScanningEnabled: &enabled,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				InsightsUpdatedAt:   &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
			},
		},
	)
	require.NoError(t, err)
	// Force an index refresh to make the results visible via search
	require.NoError(t, resolver.es.Refresh(ctx, ts.Index_OrgLevel))

	updatedAfter := time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)
	req := &proto.GetAlertsForInsightsBackfillRequest{
		RepositoryId: 1,
		UpdatedAfter: timestamppb.New(updatedAfter),
	}

	res, err := resolver.GetAlertsForInsightsBackfill(ctx, req)
	require.NoError(t, err)

	require.Len(t, res.Alerts, 1)
	require.Equal(t, uint64(alertId), res.Alerts[0].Id)
	require.Equal(t, uint32(alertNumber), res.Alerts[0].Number)
	require.Empty(t, res.NextCursor) //  No previous page
}

func TestGetAlertsForInsightsBackfill_SortByCreatedAtAndId(t *testing.T) {
	db, ctx, resolver := setupGetAlertsForInsightsBackfillTests(t)

	commit := "da39a3ee5e6b4b0d3255bfef95601890afd80709"
	repoID := ts.RepositoryEID(1)
	analysis := setupFirstAnalysis(t, db, repoID, commit)
	rule1 := &ts.Rule{
		Name:             "Rule1",
		ShortDescription: "Rule 1",
		FullDescription:  "This is Rule 1",
		SeverityLevel:    ts.SeverityLevelError,
		SarifIdentifier:  "js/one",
	}
	rule1.SetTags([]string{"rule1"})
	dbtest.RequireCreate(t, db, rule1)

	// Create a different analysis
	analysis = createAnalysis(t, db, repoID, analysis.ToolVersion, commit, "js2")

	alertId1 := 1
	alertId2 := 2
	alertNumber1 := 101
	alertNumber2 := 102

	createNewAlertCombo(t, db, analysis, rule1, alertId1, uint8(alertNumber1))
	createNewAlertCombo(t, db, analysis, rule1, alertId2, uint8(alertNumber2))

	fixed := false
	enabled := true
	err := resolver.es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				Number:              uint32(alertNumber1),
				CanonicalID:         "1",
				FullDescription:     "XSS is good",
				SarifIdentifier:     "js/good-xss",
				FixedOnDefault:      &fixed,
				Resolution:          "AlertResolutionNone",
				CodeScanningEnabled: &enabled,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				InsightsUpdatedAt:   &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				Number:              uint32(alertNumber2),
				CanonicalID:         "2",
				FullDescription:     "XSS is bad",
				SarifIdentifier:     "java/bad-xss",
				FixedOnDefault:      &fixed,
				Resolution:          "AlertResolutionNone",
				CodeScanningEnabled: &enabled,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				InsightsUpdatedAt:   &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
			},
		},
	)
	require.NoError(t, err)
	// Force an index refresh to make the results visible via search
	require.NoError(t, resolver.es.Refresh(ctx, ts.Index_OrgLevel))

	req := &proto.GetAlertsForInsightsBackfillRequest{
		RepositoryId: 1,
	}

	res, err := resolver.GetAlertsForInsightsBackfill(ctx, req)
	require.NoError(t, err)

	require.Len(t, res.Alerts, 3)
	require.Equal(t, uint64(alertId1), res.Alerts[0].Id)
	require.Equal(t, uint64(alertId2), res.Alerts[2].Id)
	require.Equal(t, uint32(alertNumber1), res.Alerts[0].Number)
	require.Equal(t, uint32(alertNumber2), res.Alerts[2].Number)
	require.Empty(t, res.NextCursor) //  No previous page
}

func TestGetAlertsForInsightsBackfill_NumbersForMissingAlerts(t *testing.T) {
	db, ctx, resolver := setupGetAlertsForInsightsBackfillTests(t)

	commit := "da39a3ee5e6b4b0d3255bfef95601890afd80709"
	repoID := ts.RepositoryEID(1)
	analysis := setupFirstAnalysis(t, db, repoID, commit)
	rule1 := &ts.Rule{
		Name:             "Rule1",
		ShortDescription: "Rule 1",
		FullDescription:  "This is Rule 1",
		SeverityLevel:    ts.SeverityLevelError,
		SarifIdentifier:  "js/one",
	}
	rule1.SetTags([]string{"rule1"})
	dbtest.RequireCreate(t, db, rule1)
	createNewAlertCombo(t, db, analysis, rule1, 1, 1)
	createNewAlertCombo(t, db, analysis, rule1, 2, 2)
	createNewAlertCombo(t, db, analysis, rule1, 3, 3)

	fixed := false
	enabled := true
	err := resolver.es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				Number:              1,
				AlertID:             999, // Simulate a missing alert by setting a wrong logical alert ID
				CanonicalID:         "1",
				FullDescription:     "XSS is good",
				SarifIdentifier:     rule1.SarifIdentifier,
				FixedOnDefault:      &fixed,
				Resolution:          "AlertResolutionNone",
				CodeScanningEnabled: &enabled,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
				InsightsUpdatedAt:   &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				Number:              2,
				AlertID:             2,
				CanonicalID:         "999", // Simulate a missing alert by setting a wrong physical alert ID
				FullDescription:     "XSS is bad",
				SarifIdentifier:     rule1.SarifIdentifier,
				FixedOnDefault:      &fixed,
				Resolution:          "AlertResolutionNone",
				CodeScanningEnabled: &enabled,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				InsightsUpdatedAt:   &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             3,
				Number:              3,
				CanonicalID:         "3",
				FullDescription:     "XSS is bad",
				SarifIdentifier:     rule1.SarifIdentifier,
				FixedOnDefault:      &fixed,
				Resolution:          "AlertResolutionNone",
				CodeScanningEnabled: &enabled,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
				InsightsUpdatedAt:   &sqltime.Time{Time: time.Date(2020, 1, 2, 0, 0, 0, 0, time.UTC)},
			},
		},
	)
	require.NoError(t, err)
	// Force an index refresh to make the results visible via search
	require.NoError(t, resolver.es.Refresh(ctx, ts.Index_OrgLevel))

	req := &proto.GetAlertsForInsightsBackfillRequest{
		RepositoryId: 1,
	}

	res, err := resolver.GetAlertsForInsightsBackfill(ctx, req)
	require.NoError(t, err)

	// Alerts 1 and 2 are missing, but they should still have a non-zero number
	require.Len(t, res.Alerts, 3)
	require.Equal(t, uint64(999), res.Alerts[0].Id)
	require.Equal(t, uint32(1), res.Alerts[0].Number)
	require.Equal(t, uint64(2), res.Alerts[1].Id)
	require.Equal(t, uint32(2), res.Alerts[1].Number)
	require.Equal(t, uint64(3), res.Alerts[2].Id)
	require.Equal(t, uint32(3), res.Alerts[2].Number)
}

func setupGetAlertsForInsightsBackfillTests(t *testing.T) (
	*gorm.DB,
	context.Context,
	*ResultsResolver,
) {
	t.Helper()
	db := dbtest.RequireConnection(t)
	alertService := alert.TestService(db)
	ctx := context.Background()
	es := elasticsearch.SetUpTestElasticSearchService(t)
	resolver := NewResultsResolver(alertService, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, es, nil, nil, nil, nil, false)

	return db, ctx, resolver
}

func setupFirstAnalysis(t *testing.T, db *gorm.DB, repoID ts.RepositoryEID, commit string) *ts.Analysis {
	t.Helper()
	tool := &ts.Tool{
		CanonicalName:  "CodeQL",
		GUID:           "e91e0de1-9ce6-4ed3-83ec-16bb54c8000a",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, tool)
	toolVersion := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  tool.ID,
	}
	dbtest.RequireCreate(t, db, toolVersion)

	return createAnalysis(t, db, repoID, toolVersion, commit, "js1")
}

func createNewAlertCombo(t *testing.T, db *gorm.DB, analysis *ts.Analysis, rule1 *ts.Rule, alertId int, alertNumber uint8) {
	t.Helper()
	a1 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(alertId),
		RuleID:                rule1.ID,
		Number:                uint32(alertNumber),
		StableAlertIdentifier: []byte{alertNumber},
		RepositoryID:          analysis.RepositoryID,
		SarifIdentifier:       rule1.SarifIdentifier,
		Message:               "message",
		FilePath:              "src/file1",
	}
	dbtest.RequireCreate(t, db, a1)
	p1 := &ts.PhysicalAlert{
		ID:                  ts.PhysicalAlertID(alertId),
		RuleSarifIdentifier: rule1.SarifIdentifier,
		SeverityLevel:       rule1.SeverityLevel,
		Fingerprint:         "fp1",
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		LogicalAlertID:        a1.ID,
		StableAlertIdentifier: []byte{alertNumber},
		AnalysisID:            analysis.ID,
		RepositoryID:          analysis.RepositoryID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, p1)
}

func createAnalysis(t *testing.T, db *gorm.DB, repoID ts.RepositoryEID, tv *ts.ToolVersion, commit, category string) (analysis *ts.Analysis) {
	t.Helper()
	analysis = &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          ts.ToSha(commit),
		ToolID:             tv.ToolID,
		ToolVersionID:      tv.ID,
		ToolVersion:        tv,
		Category:           ts.ToCategory(category),
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, analysis)

	return
}
