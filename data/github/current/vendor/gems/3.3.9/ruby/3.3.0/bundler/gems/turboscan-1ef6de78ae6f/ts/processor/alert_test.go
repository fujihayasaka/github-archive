package processor

import (
	"context"
	"database/sql"
	"encoding/binary"
	"fmt"
	"sort"
	"testing"
	"time"

	"github.com/aws/smithy-go/ptr"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/sarif"

	"github.com/SamuelTissot/sqltime"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/proto"
)

var nofilter = ts.AlertFilter{}
var repoAnalysisFilter = ts.AnalysisFilter{RepositoryID: testRepoID, State: ts.AnalysisStateFilterMostRecent}

func newTestRepository() *ts.Repository {
	return &ts.Repository{
		RepositoryID:        testRepoID,
		OwnerID:             1,
		CodeScanningEnabled: true,
		SourceUpdatedAt:     sqltime.Now(),
		Visibility:          sql.NullString{String: "public", Valid: true},
		DefaultRef:          []byte("refs/heads/main"),
		LastIndexedAt:       sql.NullTime{Time: time.Now(), Valid: true},
	}
}

func TestGetAlertId_NotFound(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	as := e.as
	ctx := e.ctx

	_, err := as.AlertId(ctx, testRepoID, 1)

	require.Equal(t, err, ts.ErrAlertNotFound)
}

func TestGetAlertId(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	alerts := e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       42,
			RuleID:       1,
			Resolution:   ts.AlertResolutionUsedInTests,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       43,
			RuleID:       2,
			Resolution:   ts.AlertResolutionUsedInTests,
			Weight:       160,
		},
	)

	id, err := as.AlertId(ctx, testRepoID, 42)
	require.NoError(t, err)
	require.Equal(t, alerts[0].ID, id)
	id, err = as.AlertId(ctx, testRepoID, 43)
	require.NoError(t, err)
	require.Equal(t, alerts[1].ID, id)
}

func TestGetAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			RuleID:       1,
			Resolution:   ts.AlertResolutionUsedInTests,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
			RuleID:       2,
			Weight:       160,
		},
		ts.LogicalAlert{
			RepositoryID: 77,
			Number:       3,
			RuleID:       2,
			Weight:       160,
		},
	)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
}

func TestGetAllWithLimit(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       3,
		},
	)

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 0}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 1}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 100}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 3)
}

func TestGetAllWithOffset(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			Weight:       160,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
			Weight:       210,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       3,
			Weight:       180,
		})

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 1}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 1, Offset: 1}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 1, Offset: 2}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Equal(t, uint32(3), logicalAlerts[0].Number)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: &ts.Pagination{Limit: 1, Offset: 100}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
}

func TestGetAllWithOrder(t *testing.T) {
	// Testing the sort ordering for replacing updated_at respects the logic:
	// ORDER BY COALESCE(la.resolved_at, pa.last_state_change)
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx
	now := time.Now()

	updatedEarliest := sqltime.Time{Time: now.AddDate(-2, 0, 0)}
	updatedNext := sqltime.Time{Time: now.AddDate(-1, 0, 0)}
	updatedLast := sqltime.Time{Time: now}

	alert1 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 1, Weight: 140}
	alert1.CreatedAt = sqltime.Time{Time: now.AddDate(-20, 0, 0)}
	alert1.UpdatedAt = sqltime.Time{Time: now.AddDate(-20, 0, 0)}

	pa := e.testLogicalAlerts(alert1)[0].PhysicalAlerts[0]
	pa.LastStateChangeAt = updatedEarliest
	e.db.Save(pa)

	alert2 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 2, Weight: 210}
	alert2.CreatedAt = sqltime.Time{Time: now.AddDate(-21, 0, 0)}
	alert2.UpdatedAt = sqltime.Time{Time: now.AddDate(-21, 0, 0)}
	pa = e.testLogicalAlerts(alert2)[0].PhysicalAlerts[0]
	pa.LastStateChangeAt = updatedNext
	e.db.Save(pa)

	alert3 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 3, Weight: 210}
	alert3.CreatedAt = sqltime.Time{Time: now.AddDate(-22, 0, 0)}
	alert3.UpdatedAt = sqltime.Time{Time: now.AddDate(-22, 0, 0)}

	alert3.ResolvedAt = &updatedLast
	pa = e.testLogicalAlerts(alert3)[0].PhysicalAlerts[0]
	// We should use the resolved date in place of the last state change, so make sure they are different to ensure that is happened
	pa.LastStateChangeAt = updatedNext
	e.db.Save(pa)

	pagination := &ts.Pagination{Limit: 3}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: pagination, SortBy: alert.SortBy(proto.AlertSortOrder_UPDATED_ASCENDING)})
	require.NoError(t, err)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	require.Equal(t, uint32(2), logicalAlerts[1].Number)
	require.Equal(t, uint32(3), logicalAlerts[2].Number)
	require.Equal(t, updatedEarliest.Unix(), logicalAlerts[0].LastStateChangeAt.Unix())
	require.Equal(t, updatedNext.Unix(), logicalAlerts[1].LastStateChangeAt.Unix())
	require.Equal(t, updatedLast.Unix(), logicalAlerts[2].LastStateChangeAt.Unix())

	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, &ts.FindOptions{Pagination: pagination, SortBy: alert.SortBy(proto.AlertSortOrder_UPDATED_DESCENDING)})
	require.NoError(t, err)
	require.Equal(t, uint32(3), logicalAlerts[0].Number)
	require.Equal(t, uint32(2), logicalAlerts[1].Number)
	require.Equal(t, uint32(1), logicalAlerts[2].Number)

	require.Equal(t, updatedLast.Unix(), logicalAlerts[0].LastStateChangeAt.Unix())
	require.Equal(t, updatedNext.Unix(), logicalAlerts[1].LastStateChangeAt.Unix())
	require.Equal(t, updatedEarliest.Unix(), logicalAlerts[2].LastStateChangeAt.Unix())
}

func TestAlertFilter(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          1,
			RuleID:          1,
			SarifIdentifier: "rule-1",
			Resolution:      ts.AlertResolutionUsedInTests,
			Weight:          180,
		},
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          2,
			RuleID:          2,
			SarifIdentifier: "rule-2",
			Weight:          160,
			SeverityLevel:   ts.SeverityLevelError,
		},
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           3,
			RuleID:           3,
			SarifIdentifier:  "rule-3",
			Weight:           160,
			SecuritySeverity: ptr.Float64(9.5),
		},
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           4,
			RuleID:           4,
			SarifIdentifier:  "rule-4",
			Weight:           160,
			SeverityLevel:    ts.SeverityLevelError,
			SecuritySeverity: ptr.Float64(9.5),
		},
		ts.LogicalAlert{
			RepositoryID:    77,
			Number:          5,
			RuleID:          2,
			SarifIdentifier: "rule-2",
			Weight:          160,
		},
	)

	filterOpen := ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterOpen, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 3)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filterOpen, repoAnalysisFilter, 3, 1)

	logicalAlerts, err = as.Alerts(ctx, 77, nofilter, ts.AnalysisFilter{RepositoryID: 77}, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(5), logicalAlerts[0].Number)
	e.requireCounts(77, nofilter, ts.AnalysisFilter{RepositoryID: 77}, 1, 0)

	filterOneRule := ts.AlertFilter{SarifIdentifiers: []string{"rule-2"}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterOneRule, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filterOneRule, repoAnalysisFilter, 1, 0)

	filterNoRule := ts.AlertFilter{SarifIdentifiers: []string{}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterNoRule, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
	e.requireCounts(testRepoID, filterNoRule, repoAnalysisFilter, 0, 0)

	filterSeverityError := ts.AlertFilter{SeverityLevels: []proto.Severity{proto.Severity_SEVERITY_ERROR}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterSeverityError, repoAnalysisFilter, options)
	require.NoError(t, err)
	// If an alert has both severity and security severity it should not appear when filtering by severity so only 1 result
	require.Len(t, logicalAlerts, 1)
	e.requireCounts(testRepoID, filterSeverityError, repoAnalysisFilter, 1, 0)

	// Critical

	filterSecuritySeverityCritical := ts.AlertFilter{SeverityLevels: []proto.Severity{proto.Severity_SEVERITY_CRITICAL}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterSecuritySeverityCritical, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	e.requireCounts(testRepoID, filterSecuritySeverityCritical, repoAnalysisFilter, 2, 0)

	filterResolved := ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterResolved, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filterResolved, repoAnalysisFilter, 3, 1)
}

func TestAlertFilterWithExcludedSarifIdentifiers(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          1,
			RuleID:          1,
			SarifIdentifier: "rule-1",
			Weight:          180,
		},
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          2,
			RuleID:          2,
			SarifIdentifier: "rule-2",
			Weight:          160,
		},
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          3,
			RuleID:          3,
			SarifIdentifier: "rule-3",
			Weight:          160,
		},
	)

	// Test that we can filter by a single excluded sarif identifier
	excludeOneRule := ts.AlertFilter{ExcludedSarifIdentifiers: []string{"rule-1"}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, excludeOneRule, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)
	require.Equal(t, uint32(3), logicalAlerts[1].Number)
	e.requireCounts(testRepoID, excludeOneRule, repoAnalysisFilter, 2, 0)

	// Test that we can filter by multiple excluded sarif identifiers
	excludeMultipleRules := ts.AlertFilter{ExcludedSarifIdentifiers: []string{"rule-2", "rule-3"}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, excludeMultipleRules, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, excludeMultipleRules, repoAnalysisFilter, 1, 0)

	// Test that excluding all available sarif identifiers will return no results.
	excludeAllRules := ts.AlertFilter{ExcludedSarifIdentifiers: []string{"rule-1", "rule-2", "rule-3"}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, excludeAllRules, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
	e.requireCounts(testRepoID, excludeAllRules, repoAnalysisFilter, 0, 0)
}

func TestAlertFilterWithMultipleSeverities(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          1,
			RuleID:          1,
			SarifIdentifier: "rule-1",
			Weight:          180,
			SeverityLevel:   ts.SeverityLevelError,
		},
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          2,
			RuleID:          1,
			SarifIdentifier: "rule-1",
			Weight:          180,
			SeverityLevel:   ts.SeverityLevelWarning,
		},
		// Make one of the alerts both an ERROR and LOW severity
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           3,
			RuleID:           1,
			SarifIdentifier:  "rule-1",
			Weight:           180,
			SeverityLevel:    ts.SeverityLevelError,
			SecuritySeverity: ptr.Float64(2.0),
		},
		// ssCritical := 9.5
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           4,
			RuleID:           2,
			SarifIdentifier:  "rule-2",
			Weight:           160,
			SecuritySeverity: ptr.Float64(9.5),
		},
		// ssMedium := 5.0
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           5,
			RuleID:           2,
			SarifIdentifier:  "rule-2",
			Weight:           160,
			SecuritySeverity: ptr.Float64(5.0),
		},
		// ssOutOfBounds := 15.0
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           6,
			RuleID:           2,
			SarifIdentifier:  "rule-2",
			Weight:           160,
			SecuritySeverity: ptr.Float64(15.0),
		},
		ts.LogicalAlert{
			RepositoryID:    77,
			Number:          7,
			RuleID:          2,
			SarifIdentifier: "rule-2",
			Weight:          160,
		},
	)

	// Verify that we can filter with a single rule severity level
	filterSeverity := []proto.Severity{proto.Severity_SEVERITY_ERROR}
	filterSeverityError, logicalAlerts := createSeverityFilterAndGetAlerts(ctx, t, as, filterSeverity, nil, options)
	e.verifyAlertCounts(t, filterSeverityError, logicalAlerts, 1)

	// Verify that we can filter with multiple rule severity levels

	severityLevels := []proto.Severity{proto.Severity_SEVERITY_ERROR, proto.Severity_SEVERITY_WARNING}
	filterSeverityBoth, logicalAlerts := createSeverityFilterAndGetAlerts(ctx, t, as, severityLevels, nil, options)
	e.verifyAlertCounts(t, filterSeverityBoth, logicalAlerts, 2)

	// Verify that we can filter with a single security severity level

	severityCritical := []proto.Severity{proto.Severity_SEVERITY_CRITICAL}
	severityMedium := []proto.Severity{proto.Severity_SEVERITY_MEDIUM}
	severityMedCrit := []proto.Severity{proto.Severity_SEVERITY_MEDIUM, proto.Severity_SEVERITY_CRITICAL}

	filterSecuritySeverityCritical, logicalAlertsCritical := createSeverityFilterAndGetAlerts(ctx, t, as, severityCritical, nil, options)
	e.verifyAlertCounts(t, filterSecuritySeverityCritical, logicalAlertsCritical, 1)

	filterSecuritySeverityMedium, logicalAlertsMedium := createSeverityFilterAndGetAlerts(ctx, t, as, severityMedium, nil, options)
	e.verifyAlertCounts(t, filterSecuritySeverityMedium, logicalAlertsMedium, 1)

	filterSecuritySeverityBoth, logicalAlerts := createSeverityFilterAndGetAlerts(ctx, t, as, severityMedCrit, nil, options)
	e.verifyAlertCounts(t, filterSecuritySeverityBoth, logicalAlerts, 2)

	// Verify that a mix of Security and Rule Severity levels work
	filterSecurityAndRuleSeverity, logicalAlertsSecurityAndRule := createSeverityFilterAndGetAlerts(
		ctx, t, as, []proto.Severity{proto.Severity_SEVERITY_CRITICAL, proto.Severity_SEVERITY_ERROR}, nil, options)
	e.verifyAlertCounts(t, filterSecurityAndRuleSeverity, logicalAlertsSecurityAndRule, 2)

	// Verify that a mix of Security and Rule Severity with alert overlap works
	filterOverlapSecurityAndRuleSeverity, logicalAlertsOverlapSecurityAndRule := createSeverityFilterAndGetAlerts(
		ctx, t, as, []proto.Severity{proto.Severity_SEVERITY_LOW, proto.Severity_SEVERITY_ERROR}, nil, options)
	e.verifyAlertCounts(t, filterOverlapSecurityAndRuleSeverity, logicalAlertsOverlapSecurityAndRule, 2)
}

func TestAlertFilterWithExcludedSeverities(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          1,
			RuleID:          1,
			SarifIdentifier: "rule-1",
			Weight:          180,
			SeverityLevel:   ts.SeverityLevelError,
		},
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			Number:          2,
			RuleID:          1,
			SarifIdentifier: "rule-1",
			Weight:          180,
			SeverityLevel:   ts.SeverityLevelWarning,
		},
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           3,
			RuleID:           1,
			SarifIdentifier:  "rule-1",
			Weight:           180,
			SecuritySeverity: ptr.Float64(2.0),
			SeverityLevel:    ts.SeverityLevelError,
		},
		// ssCritical := 9.5
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           4,
			RuleID:           2,
			SarifIdentifier:  "rule-2",
			Weight:           160,
			SecuritySeverity: ptr.Float64(9.5),
		},
		// ssMedium := 5.0
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           5,
			RuleID:           2,
			SarifIdentifier:  "rule-2",
			Weight:           160,
			SecuritySeverity: ptr.Float64(5.0),
		},
		// ssOutOfBounds := 15.0
		ts.LogicalAlert{
			RepositoryID:     testRepoID,
			Number:           6,
			RuleID:           2,
			SarifIdentifier:  "rule-2",
			Weight:           160,
			SecuritySeverity: ptr.Float64(15.0),
		},
	)

	// Verify that we can filter with a single excluded rule severity level
	excludedSeverity := []proto.Severity{proto.Severity_SEVERITY_ERROR}
	filterSeverityError, logicalAlerts := createSeverityFilterAndGetAlerts(ctx, t, as, nil, excludedSeverity, options)
	e.verifyAlertCounts(t, filterSeverityError, logicalAlerts, 5)

	// Verify that we can filter with multiple excluded rule severity levels
	excludedSeverities := []proto.Severity{proto.Severity_SEVERITY_ERROR, proto.Severity_SEVERITY_WARNING}
	filterSeverityBoth, logicalAlerts := createSeverityFilterAndGetAlerts(ctx, t, as, nil, excludedSeverities, options)
	e.verifyAlertCounts(t, filterSeverityBoth, logicalAlerts, 4)

	// Verify that we can filter with a single excluded security severity level
	excludedSeverityCritical := []proto.Severity{proto.Severity_SEVERITY_CRITICAL}
	excludedSeverityMedium := []proto.Severity{proto.Severity_SEVERITY_MEDIUM}
	excludedSeverityMedCrit := []proto.Severity{proto.Severity_SEVERITY_MEDIUM, proto.Severity_SEVERITY_CRITICAL}

	filterSecuritySeverityCritical, logicalAlertsCritical := createSeverityFilterAndGetAlerts(ctx, t, as, nil, excludedSeverityCritical, options)
	e.verifyAlertCounts(t, filterSecuritySeverityCritical, logicalAlertsCritical, 5)

	filterSecuritySeverityMedium, logicalAlertsMedium := createSeverityFilterAndGetAlerts(ctx, t, as, nil, excludedSeverityMedium, options)
	e.verifyAlertCounts(t, filterSecuritySeverityMedium, logicalAlertsMedium, 5)

	filterSecuritySeverityBoth, logicalAlerts := createSeverityFilterAndGetAlerts(ctx, t, as, nil, excludedSeverityMedCrit, options)
	e.verifyAlertCounts(t, filterSecuritySeverityBoth, logicalAlerts, 4)

	// Verify that a mix of Security and Rule Severity levels work
	filterSecurityAndRuleSeverity, logicalAlertsSecurityAndRule := createSeverityFilterAndGetAlerts(
		ctx, t, as, nil, []proto.Severity{proto.Severity_SEVERITY_CRITICAL, proto.Severity_SEVERITY_ERROR}, options)
	e.verifyAlertCounts(t, filterSecurityAndRuleSeverity, logicalAlertsSecurityAndRule, 4)

	// Verify that a mix of Security and Rule Severity with alert overlap works
	filterOverlapSecurityAndRuleSeverity, logicalAlertsOverlapSecurityAndRule := createSeverityFilterAndGetAlerts(
		ctx, t, as, nil, []proto.Severity{proto.Severity_SEVERITY_LOW, proto.Severity_SEVERITY_ERROR}, options)
	e.verifyAlertCounts(t, filterOverlapSecurityAndRuleSeverity, logicalAlertsOverlapSecurityAndRule, 4)
}

func TestAlertFilterByTool(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	newAlertForNewAnalysisWithTool := func(number uint32, toolID ts.ToolID) {
		r := &ts.Rule{
			SarifIdentifier: fmt.Sprintf("E%d", number),
			ToolID:          toolID,
		}
		dbtest.RequireCreate(t, db, &r)

		l := &ts.LogicalAlert{
			RepositoryID:          testRepoID,
			Number:                number,
			StableAlertIdentifier: newStableID(),
			RuleID:                r.ID,
		}
		dbtest.RequireCreate(t, db, &l)

		a := ts.Analysis{
			RepositoryID:       l.RepositoryID,
			SourceRepositoryID: l.RepositoryID,
			Ref:                []byte(fmt.Sprintf("%d", number)),
			MostRecent:         true,
			AnalysisComplete:   true,
			ToolID:             toolID,
		}
		dbtest.RequireCreate(t, db, &a)

		p := &ts.PhysicalAlert{
			LogicalAlertID:        l.ID,
			RepositoryID:          l.RepositoryID,
			StableAlertIdentifier: l.StableAlertIdentifier,
			AnalysisID:            a.ID,
			RuleID:                l.RuleID,
			LastStateChangeAt:     sqltime.Now(),
		}
		dbtest.RequireCreate(t, db, &p)
	}

	codeQL := e.requireToolByName(testRepoID, "CodeQL")
	esLint := e.requireToolByName(testRepoID, "ESLint")

	newAlertForNewAnalysisWithTool(1, codeQL.ID)
	newAlertForNewAnalysisWithTool(2, esLint.ID)
	newAlertForNewAnalysisWithTool(3, codeQL.ID)

	options := &ts.FindOptions{
		Pagination: &ts.Pagination{Limit: 25},
		SortBy:     alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING),
		Preloads:   []string{"Rule.Tool"},
	}

	analysisFilter := ts.AnalysisFilter{RepositoryID: testRepoID, ToolIDs: []ts.ToolID{codeQL.ID}}
	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, analysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	e.requireCounts(testRepoID, nofilter, analysisFilter, 2, 0)
	require.NotNil(t, logicalAlerts[0].Rule.Tool)

	// Note case here - filter should be case-insensitive
	wrongESLint := e.requireToolByName(testRepoID, "esLInt")
	require.Equal(t, wrongESLint.ID, esLint.ID)
	analysisFilter = ts.AnalysisFilter{RepositoryID: testRepoID, ToolIDs: []ts.ToolID{wrongESLint.ID}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, analysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	e.requireCounts(testRepoID, nofilter, analysisFilter, 1, 0)

	analysisFilter = ts.AnalysisFilter{RepositoryID: testRepoID, ToolIDs: []ts.ToolID{}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, analysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 3)
	e.requireCounts(testRepoID, nofilter, analysisFilter, 3, 0)
}

func TestAlertFilterByExcludedTools(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	newAlertForNewAnalysisWithTool := func(number uint32, toolID ts.ToolID) {
		r := &ts.Rule{
			SarifIdentifier: fmt.Sprintf("E%d", number),
			ToolID:          toolID,
		}
		dbtest.RequireCreate(t, db, &r)

		l := &ts.LogicalAlert{
			RepositoryID:          testRepoID,
			Number:                number,
			StableAlertIdentifier: newStableID(),
			RuleID:                r.ID,
		}
		dbtest.RequireCreate(t, db, &l)

		a := ts.Analysis{
			RepositoryID:       l.RepositoryID,
			SourceRepositoryID: l.RepositoryID,
			Ref:                []byte(fmt.Sprintf("%d", number)),
			MostRecent:         true,
			AnalysisComplete:   true,
			ToolID:             toolID,
		}
		dbtest.RequireCreate(t, db, &a)

		p := &ts.PhysicalAlert{
			LogicalAlertID:        l.ID,
			RepositoryID:          l.RepositoryID,
			StableAlertIdentifier: l.StableAlertIdentifier,
			AnalysisID:            a.ID,
			RuleID:                l.RuleID,
			LastStateChangeAt:     sqltime.Now(),
		}
		dbtest.RequireCreate(t, db, &p)
	}

	codeQL := e.requireToolByName(testRepoID, "CodeQL")
	esLint := e.requireToolByName(testRepoID, "ESLint")

	newAlertForNewAnalysisWithTool(1, codeQL.ID)
	newAlertForNewAnalysisWithTool(2, esLint.ID)
	newAlertForNewAnalysisWithTool(3, codeQL.ID)

	options := &ts.FindOptions{
		Pagination: &ts.Pagination{Limit: 25},
		SortBy:     alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING),
		Preloads:   []string{"Rule.Tool"},
	}

	// Filter with singular excluded tool
	analysisFilter := ts.AnalysisFilter{RepositoryID: testRepoID, ExcludedToolIDs: []ts.ToolID{codeQL.ID}}
	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, analysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	e.requireCounts(testRepoID, nofilter, analysisFilter, 1, 0)
	require.NotNil(t, logicalAlerts[0].Rule.Tool)

	analysisFilter = ts.AnalysisFilter{RepositoryID: testRepoID, ExcludedToolIDs: []ts.ToolID{esLint.ID}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, analysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	e.requireCounts(testRepoID, nofilter, analysisFilter, 2, 0)
	require.NotNil(t, logicalAlerts[0].Rule.Tool)
	require.NotNil(t, logicalAlerts[1].Rule.Tool)

	// Filter with multiple excluded tools
	analysisFilter = ts.AnalysisFilter{RepositoryID: testRepoID, ExcludedToolIDs: []ts.ToolID{codeQL.ID, esLint.ID}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, nofilter, analysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
	e.requireCounts(testRepoID, nofilter, analysisFilter, 0, 0)
}

func TestAlertFilterByResolution(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			RuleID:       1,
			Resolution:   ts.AlertResolutionUsedInTests,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
			RuleID:       2,
			Resolution:   ts.AlertResolutionWontFix,
			Weight:       160,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       3,
			RuleID:       3,
			Resolution:   ts.AlertResolutionNone,
			Weight:       160,
		},
	)

	// Constants aren't addressable, so this helper function is used when
	// passing AlertResolution pointers to the filter
	addr := func(r ts.AlertResolution) []*ts.AlertResolution { return []*ts.AlertResolution{&r} }

	filter := ts.AlertFilter{Resolutions: addr(ts.AlertResolutionUsedInTests)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)

	filter = ts.AlertFilter{Resolutions: addr(ts.AlertResolutionWontFix)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)

	filter = ts.AlertFilter{Resolutions: addr(ts.AlertResolutionNone)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(3), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 1, 0)

	// The default resolution should be "all, including none"
	filter = ts.AlertFilter{}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 3)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 1, 2)

	filter = ts.AlertFilter{Resolutions: addr(ts.AlertResolutionFalsePositive)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 0)

	// Test that a resolution of "none" can be combined with a state filter
	// to return alerts that have been programmatically fixed rather than
	// manually resolved

	// At present, alert 3 has no resolution and is not fixed,
	// so this query should return 0 results
	filter = ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED, Resolutions: addr(ts.AlertResolutionNone)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 1, 0)

	// "Fix" alert 3
	var pa ts.PhysicalAlert
	err = db.Where(&ts.PhysicalAlert{RepositoryID: testRepoID, RuleID: 3}).First(&pa).Error
	require.NoError(t, err)
	analysisID := ts.AnalysisID(1)
	pa.LastSeenAnalysisID = &analysisID
	err = db.Save(pa).Error
	require.NoError(t, err)

	// It should now be returned by the query
	filter = ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED, Resolutions: addr(ts.AlertResolutionNone)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(3), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)
}

func TestAlertFilterByResolutions(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			RuleID:       1,
			Resolution:   ts.AlertResolutionUsedInTests,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
			RuleID:       2,
			Resolution:   ts.AlertResolutionWontFix,
			Weight:       160,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       3,
			RuleID:       3,
			Resolution:   ts.AlertResolutionNone,
			Weight:       160,
		},
	)

	// Constants aren't addressable, so this helper function is used when
	// passing AlertResolution pointers to the filter
	addr := func(r ts.AlertResolution) []*ts.AlertResolution {
		return []*ts.AlertResolution{&r}
	}

	// Verify Individual Resolutions
	filter := ts.AlertFilter{Resolutions: addr(ts.AlertResolutionUsedInTests)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)

	filter = ts.AlertFilter{Resolutions: addr(ts.AlertResolutionWontFix)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)

	filter = ts.AlertFilter{Resolutions: addr(ts.AlertResolutionNone)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(3), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 1, 0)

	// Verify Multiple Resolutions

	filter = ts.AlertFilter{Resolutions: addr(ts.AlertResolutionUsedInTests)}
	filter.Resolutions = append(filter.Resolutions, addr(ts.AlertResolutionWontFix)...)
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	require.Equal(t, uint32(2), logicalAlerts[1].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 2)

	// The default resolution should be "all, including none"
	filter = ts.AlertFilter{}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 3)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 1, 2)

	filter = ts.AlertFilter{Resolutions: addr(ts.AlertResolutionFalsePositive)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 0)

	// Test that a resolution of "none" can be combined with a state filter
	// to return alerts that have been programmatically fixed rather than
	// manually resolved

	// At present, alert 3 has no resolution and is not fixed,
	// so this query should return 0 results
	filter = ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED, Resolutions: addr(ts.AlertResolutionNone)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 1, 0)

	// "Fix" alert 3
	var pa ts.PhysicalAlert
	err = db.Where(&ts.PhysicalAlert{RepositoryID: testRepoID, RuleID: 3}).First(&pa).Error
	require.NoError(t, err)
	analysisID := ts.AnalysisID(1)
	pa.LastSeenAnalysisID = &analysisID
	err = db.Save(pa).Error
	require.NoError(t, err)

	// It should now be returned by the query
	filter = ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED, Resolutions: addr(ts.AlertResolutionNone)}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(3), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)
}

func TestAlertFilterByExcludedResolutions(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	wontFix := ts.AlertResolutionWontFix
	usedInTests := ts.AlertResolutionUsedInTests
	falsePositive := ts.AlertResolutionFalsePositive

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			RuleID:       1,
			Resolution:   usedInTests,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
			RuleID:       2,
			Resolution:   wontFix,
			Weight:       160,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       3,
			RuleID:       3,
			Resolution:   falsePositive,
			Weight:       160,
		},
	)

	// Test single exclusion resolution
	filter := ts.AlertFilter{ExcludedResolutions: []*ts.AlertResolution{&usedInTests}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)
	require.Equal(t, uint32(3), logicalAlerts[1].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 2)

	filter = ts.AlertFilter{ExcludedResolutions: []*ts.AlertResolution{&wontFix}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	require.Equal(t, uint32(3), logicalAlerts[1].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 2)

	filter = ts.AlertFilter{ExcludedResolutions: []*ts.AlertResolution{&falsePositive}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	require.Equal(t, uint32(2), logicalAlerts[1].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 2)

	// Test multiple excluded resolutions
	filter = ts.AlertFilter{ExcludedResolutions: []*ts.AlertResolution{&usedInTests, &wontFix}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(3), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)

	filter = ts.AlertFilter{ExcludedResolutions: []*ts.AlertResolution{&usedInTests, &falsePositive}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)

	filter = ts.AlertFilter{ExcludedResolutions: []*ts.AlertResolution{&wontFix, &falsePositive}}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
	e.requireCounts(testRepoID, filter, repoAnalysisFilter, 0, 1)
}

func TestAlertFilterByState(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			RuleID:       1,
			Resolution:   ts.AlertResolutionUsedInTests,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
			RuleID:       2,
			Resolution:   ts.AlertResolutionWontFix,
			Weight:       160,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       3,
			RuleID:       3,
			Resolution:   ts.AlertResolutionNone,
			Weight:       160,
		},
	)

	// get everything
	filter := ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_ALL}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 3)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)

	// get all closed
	filter = ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)

	// get only open
	filter = ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(3), logicalAlerts[0].Number)

	// get resolved/dismissed
	filter = ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_RESOLVED}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)

	// get fixed (currently none)
	filter = ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)
}

func TestAlertFilterByClassification(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			RuleID:       1,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID:       testRepoID,
			Number:             2,
			RuleID:             2,
			Weight:             180,
			FileClassification: ts.FileClassification{"test"},
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       3,
			RuleID:       3,
			Weight:       180,
		},
	)

	filterIgnoreClassification := ts.AlertFilter{}
	filterIgnoreClassificationExplicitly := ts.AlertFilter{Classification: proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_NO_FILTER}
	filterUnclassified := ts.AlertFilter{Classification: proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED}
	filterClassified := ts.AlertFilter{Classification: proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_ANY_CLASSIFICATION}

	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterIgnoreClassification, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 3)
	e.requireCounts(testRepoID, filterIgnoreClassification, repoAnalysisFilter, 3, 0)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterIgnoreClassificationExplicitly, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 3)
	e.requireCounts(testRepoID, filterIgnoreClassificationExplicitly, repoAnalysisFilter, 3, 0)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterUnclassified, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	e.requireCounts(testRepoID, filterUnclassified, repoAnalysisFilter, 2, 0)

	logicalAlerts, err = as.Alerts(ctx, testRepoID, filterClassified, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, ts.RuleID(2), logicalAlerts[0].RuleID)
	e.requireCounts(testRepoID, filterClassified, repoAnalysisFilter, 1, 0)
}

func TestAlertFilterIncludeDeleted(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	options := &ts.FindOptions{Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 0)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			RuleID:       1,
			Resolution:   ts.AlertResolutionUsedInTests,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
			RuleID:       2,
			Resolution:   ts.AlertResolutionWontFix,
			Weight:       160,
		},
	)

	// get default
	defaultFilter := ts.AlertFilter{}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, defaultFilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)

	// delete first one
	require.NoError(t, db.Model(&ts.LogicalAlert{}).Where("repository_id = ? AND number = ?", testRepoID, 1).Update("soft_deleted_at", sqltime.Time{Time: time.Now()}).Error)

	// get default, should not include the deleted
	logicalAlerts, err = as.Alerts(ctx, testRepoID, defaultFilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.Equal(t, uint32(2), logicalAlerts[0].Number)

	// get all including deleted
	allFilter := ts.AlertFilter{IncludeDeleted: true}
	logicalAlerts, err = as.Alerts(ctx, testRepoID, allFilter, repoAnalysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 2)
	require.Equal(t, uint32(1), logicalAlerts[0].Number)
}

func TestCount(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	openFilter := ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN}
	closedFilter := ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED}

	count, err := as.Count(ctx, testRepoID, openFilter, repoAnalysisFilter)
	require.NoError(t, err)
	require.EqualValues(t, 0, count)

	count, err = as.Count(ctx, testRepoID, closedFilter, repoAnalysisFilter)
	require.NoError(t, err)
	require.EqualValues(t, 0, count)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       1,
			RuleID:       1,
			Resolution:   ts.AlertResolutionUsedInTests,
			Weight:       180,
		},
		ts.LogicalAlert{
			RepositoryID: testRepoID,
			Number:       2,
			RuleID:       2,
			Weight:       160,
		},
		ts.LogicalAlert{
			RepositoryID: 77,
			Number:       3,
			RuleID:       2,
			Weight:       160,
		},
	)
	count, err = as.Count(ctx, testRepoID, openFilter, repoAnalysisFilter)
	require.NoError(t, err)
	require.EqualValues(t, 1, count)

	count, err = as.Count(ctx, 77, openFilter, ts.AnalysisFilter{RepositoryID: 77})
	require.NoError(t, err)
	require.EqualValues(t, 1, count)

	count, err = as.Count(ctx, testRepoID, closedFilter, repoAnalysisFilter)
	require.NoError(t, err)
	require.EqualValues(t, 1, count)

	count, err = as.Count(ctx, 77, closedFilter, ts.AnalysisFilter{RepositoryID: 77})
	require.NoError(t, err)
	require.EqualValues(t, 0, count)
}

func TestCountByTool(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	// The basic behaviour is checked by VCR cassette (count-by-tool.yml). Here,
	// we test the behaviour when alerts are shared between tools, and also that
	// tools are returned even if they have no alerts.

	toolA := testConfig{repositoryID: testRepoID, tool: "A", analysisKey: "A", commitOid: "fixed"}
	toolB := testConfig{repositoryID: testRepoID, tool: "B", analysisKey: "B", commitOid: "fixed"}
	toolC := testConfig{repositoryID: testRepoID, tool: "C", analysisKey: "C", commitOid: "fixed"}

	alert1 := testAlert("foo.js", "foo")
	alert2 := testAlert("bar.js", "bar")
	alert3 := testAlert("baz.js", "baz")

	// alert2 is shared between two tools, toolC has no results
	e.deliverAlerts(toolA, alert1, alert2)
	e.deliverAlerts(toolB, alert2, alert3)
	e.deliverAlerts(toolC)

	total, err := as.Count(ctx, testRepoID, nofilter, repoAnalysisFilter)
	require.NoError(t, err, "count failed")

	counts, err := as.CountByTool(ctx, testRepoID, nofilter, repoAnalysisFilter)
	require.NoError(t, err, "count by tool failed")

	// The total should be 3, but the count for each tool should be 2, 2, and 0, respectively.
	require.Equal(t, uint64(3), total)
	require.Equal(t, 3, len(counts))

	seen := map[ts.ToolName]bool{}
	for canonicalName, count := range counts {
		seen[canonicalName] = true
		if canonicalName == "C" {
			require.Equal(t, uint64(0), count)
		} else {
			require.Equal(t, uint64(2), count)
		}
	}
	require.True(t, seen["A"] && seen["B"] && seen["C"], "incorrect tool names")
}

func toolVersion(guid string, name ts.ToolName, version string) *ts.ToolVersion {
	return &ts.ToolVersion{
		Name:    name,
		Version: version,
		Tool:    sarif.NewTool(guid, name),
	}
}

func TestSaveAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	tool := toolVersion("", "codeql", "2.0.1")
	analysis := &ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		CommitOid:          "deadbeef",
		Ref:                []byte("main"),
		AnalysisName:       "my-project",
		ToolID:             tool.ToolID,
		ToolVersionID:      tool.ID,
		Environment:        ts.AnalysisEnv{},
		WorkflowRunID:      101,
	}
	dbtest.RequireCreate(t, db, analysis)

	newAlerts := []*ts.PhysicalAlert{
		{
			FilePath:              "main.js",
			RuleSarifIdentifier:   "xxx",
			RepositoryID:          analysis.RepositoryID,
			StableAlertIdentifier: testStableID(1),
			LastStateChangeAt:     sqltime.Now(),
		},
		{
			FilePath:              "src/promiseUtils.js",
			RuleSarifIdentifier:   "xxx",
			RepositoryID:          analysis.RepositoryID,
			StableAlertIdentifier: testStableID(2),
			LastStateChangeAt:     sqltime.Now(),
		},
	}

	err := e.as.SaveAlerts(e.ctx, analysis, newTestRepository(), newAlerts)
	require.NoError(t, err)

	var logical []ts.LogicalAlert
	db.Find(&logical)
	require.Len(t, logical, 2)
	require.Equal(t, uint32(1), logical[0].Number)
	require.Equal(t, uint32(2), logical[1].Number)
	require.Equal(t, "main.js", logical[0].FilePath)
	require.Equal(t, "src/promiseUtils.js", logical[1].FilePath)

	// Test that the 2 timestamps on each logical alert are the same as the analysis created at
	require.Equal(t, analysis.CreatedAt.Time, logical[0].CreatedAt.Time)
	require.Equal(t, analysis.CreatedAt.Time, logical[1].CreatedAt.Time)
}

// TestSaveAlertsFromFork checks that a fork cannot update a logical alert of the parent repository
func TestSaveAlertsFromFork(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	tool := toolVersion("", "codeql", "2.0.1")
	dbtest.RequireCreate(t, db, &tool)

	analysis := &ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		CommitOid:          "deadbeef",
		Ref:                []byte("main"),
		ToolID:             tool.ToolID,
		ToolVersionID:      tool.ID,
		Environment:        ts.AnalysisEnv{},
		WorkflowRunID:      101,
	}
	dbtest.RequireCreate(t, db, &analysis)

	rule1 := &ts.Rule{SarifIdentifier: "xxx", ShortDescription: "Found a problem", ToolID: tool.Tool.ID}
	dbtest.RequireCreate(t, db, &rule1)

	rule2 := &ts.Rule{SarifIdentifier: "xxx", ShortDescription: "Found a problem (fork)", ToolID: tool.Tool.ID}
	dbtest.RequireCreate(t, db, &rule2)

	// the first analysis comes from the parent repository using tool1
	err := e.as.SaveAlerts(e.ctx, analysis, newTestRepository(), []*ts.PhysicalAlert{
		{
			AnalysisID:            analysis.ID,
			FilePath:              "main.js",
			RuleID:                rule1.ID,
			RuleSarifIdentifier:   rule1.SarifIdentifier,
			RepositoryID:          analysis.RepositoryID,
			StableAlertIdentifier: testStableID(1),
			LastStateChangeAt:     sqltime.Now(),
		},
		{
			AnalysisID:            analysis.ID,
			FilePath:              "src/promiseUtils.js",
			RuleID:                rule1.ID,
			RuleSarifIdentifier:   rule1.SarifIdentifier,
			RepositoryID:          analysis.RepositoryID,
			StableAlertIdentifier: testStableID(2),
			LastStateChangeAt:     sqltime.Now(),
		},
	})
	require.NoError(t, err)

	var logical []ts.LogicalAlert
	db.Find(&logical)
	require.Len(t, logical, 2)
	require.Equal(t, rule1.ID, logical[0].RuleID)
	require.Equal(t, rule1.ID, logical[1].RuleID)

	analysis2 := &ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID + 1,
		CommitOid:          "deadbeef",
		Ref:                []byte("main"),
		ToolID:             tool.ToolID,
		ToolVersionID:      tool.ID,
		Environment:        ts.AnalysisEnv{},
		WorkflowRunID:      101,
	}
	dbtest.RequireCreate(t, db, &analysis2)

	// the second analysis comes from the fork repository using tool2
	err = e.as.SaveAlerts(e.ctx, analysis2, newTestRepository(), []*ts.PhysicalAlert{
		{
			AnalysisID:            analysis2.ID,
			FilePath:              "main.js",
			RuleID:                rule2.ID,
			RuleSarifIdentifier:   rule2.SarifIdentifier,
			RepositoryID:          analysis.RepositoryID,
			StableAlertIdentifier: testStableID(1),
			LastStateChangeAt:     sqltime.Now(),
		},
		{
			AnalysisID:            analysis2.ID,
			FilePath:              "src/promiseUtils.js",
			RuleID:                rule2.ID,
			RuleSarifIdentifier:   rule2.SarifIdentifier,
			RepositoryID:          analysis.RepositoryID,
			StableAlertIdentifier: testStableID(2),
			LastStateChangeAt:     sqltime.Now(),
		},
	})
	require.NoError(t, err)

	var physical []ts.PhysicalAlert
	db.Find(&physical)
	require.Len(t, physical, 4)
	require.Equal(t, rule1.ID, physical[0].RuleID)
	require.Equal(t, rule1.ID, physical[1].RuleID)
	require.Equal(t, rule2.ID, physical[2].RuleID)
	require.Equal(t, rule2.ID, physical[3].RuleID)

	// we prove that even though the physical alerts point to tool 2, the logical alert is not changed
	db.Find(&logical)
	require.Len(t, logical, 2)
	require.Equal(t, "main.js", logical[0].FilePath)
	require.Equal(t, "src/promiseUtils.js", logical[1].FilePath)
	require.Equal(t, rule1.ID, logical[0].RuleID)
	require.Equal(t, rule1.ID, logical[1].RuleID)

	analysis3 := &ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		CommitOid:          "deadbeef",
		Ref:                []byte("main"),
		ToolID:             tool.ToolID,
		ToolVersionID:      tool.ID,
		Environment:        ts.AnalysisEnv{},
		WorkflowRunID:      101,
	}
	dbtest.RequireCreate(t, db, &analysis3)

	// the third analysis is from the original repository again, this time using tool 2
	err = e.as.SaveAlerts(e.ctx, analysis, newTestRepository(), []*ts.PhysicalAlert{
		{
			AnalysisID:            analysis3.ID,
			FilePath:              "main.js",
			RuleID:                rule2.ID,
			RuleSarifIdentifier:   rule2.SarifIdentifier,
			RepositoryID:          analysis3.RepositoryID,
			StableAlertIdentifier: testStableID(1),
			LastStateChangeAt:     sqltime.Now(),
		},
		{
			AnalysisID:            analysis3.ID,
			FilePath:              "src/promiseUtils.js",
			RuleID:                rule2.ID,
			RuleSarifIdentifier:   rule2.SarifIdentifier,
			RepositoryID:          analysis3.RepositoryID,
			StableAlertIdentifier: testStableID(2),
			LastStateChangeAt:     sqltime.Now(),
		},
	})
	require.NoError(t, err)

	// the RuleID should be updated this time
	db.Find(&logical)
	require.Len(t, logical, 2)
	require.Equal(t, rule2.ID, logical[0].RuleID)
	require.Equal(t, rule2.ID, logical[1].RuleID)
}

// TODO(arthurnn): this is testing too much.
// It should be split in 2 parts: test the SaveAlerts
// (which is part of TestSaveAlerts) and test timeline events,
// which should be on the processor
func TestSaveAlerts_Legacy(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)
	analysis := e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/example.sarif")

	var physical []ts.PhysicalAlert
	db.Find(&physical)
	require.Equal(t, 2, len(physical))

	var logical []ts.LogicalAlert
	db.Find(&logical)
	require.Equal(t, 2, len(logical))
	require.Equal(t, uint32(1), logical[0].Number)
	require.Equal(t, uint32(2), logical[1].Number)
	require.Equal(t, "main.js", logical[0].FilePath)
	require.Equal(t, "src/promiseUtils.js", logical[1].FilePath)

	// Test that the 2 timestamps on each logical alert are the same as the analysis created_at
	require.Equal(t, analysis.CreatedAt.Time, logical[0].CreatedAt.Time)
	require.Equal(t, analysis.CreatedAt.Time, logical[1].CreatedAt.Time)

	// Test that the weights assigned to the logical alerts are as expected
	require.Equal(t, ts.MagicWeight(ts.SeverityLevelNote, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelVeryHigh), logical[0].Weight)
	require.Equal(t, ts.MagicWeight(ts.SeverityLevelWarning, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelVeryHigh), logical[1].Weight)

	// Test that we have the expected related locations
	var expectedPhysicalAlertID = physical[1].ID
	var relatedLocations []ts.RelatedLocation
	db.Find(&relatedLocations)
	require.Equal(t, 2, len(relatedLocations))
	require.Equal(t, expectedPhysicalAlertID, relatedLocations[0].PhysicalAlertID)
	require.Equal(t, expectedPhysicalAlertID, relatedLocations[1].PhysicalAlertID)

	// Test that we have a timeline event (alert created) for each logical alert
	var event []ts.TimelineEvent
	db.Where("event_type = ?", ts.TimelineEventTypeAlertCreated).Find(&event)
	require.Equal(t, 2, len(event))
	require.Equal(t, logical[0].ID, event[0].LogicalAlertID)
	require.Equal(t, logical[0].RepositoryID, event[0].RepositoryID)
	require.Equal(t, analysis.ID, event[0].AnalysisID)
	require.Equal(t, analysis.Environment, event[0].Environment)
	require.Equal(t, analysis.CommitOid, event[0].CommitOid)
	require.Equal(t, analysis.Ref, []byte(event[0].Ref))
	require.Equal(t, logical[0].FilePath, event[0].FilePath)
	require.Equal(t, logical[0].Region.StartLine, event[0].StartLine)
	require.Equal(t, analysis.ToolVersionID, event[0].ToolVersionID)
	require.Equal(t, logical[1].ID, event[1].LogicalAlertID)
	require.Equal(t, analysis.ID, event[1].AnalysisID)
	require.Equal(t, analysis.Environment, event[1].Environment)
	require.Equal(t, analysis.CommitOid, event[1].CommitOid)
	require.Equal(t, analysis.Ref, []byte(event[1].Ref))
	require.Equal(t, logical[1].FilePath, event[1].FilePath)
	require.Equal(t, logical[1].Region.StartLine, event[1].StartLine)
	require.Equal(t, analysis.ToolVersionID, event[1].ToolVersionID)

	// Test that we have no timeline events (alert appeared in ref, or reappeared) when no baseline exists
	var event1 []ts.TimelineEvent
	db.Where("event_type = ? or event_type = ?", ts.TimelineEventTypeAlertAppearedInBranch, ts.TimelineEventTypeAlertReappeared).Find(&event1)
	require.Equal(t, 0, len(event1))
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "cafed00d"}, "../sarif/testdata/example.sarif")
	// make sure logical alerts are still two
	db.Find(&logical)
	require.Equal(t, 2, len(logical))

	db.Find(&physical)
	// Check that it created similar but different physical alerts
	require.Equal(t, 4, len(physical))
	require.NotEqual(t, physical[0].ID, physical[2].ID)
	// Check that the two different physical alerts refer to the same logical alert
	require.Equal(t, physical[0].LogicalAlertID, physical[2].LogicalAlertID)
	// Check that the logical alerts have now been updated
	require.Equal(t, true, logical[0].UpdatedAt.Time.After(logical[0].CreatedAt.Time))
	require.Equal(t, true, logical[1].UpdatedAt.Time.After(logical[1].CreatedAt.Time))

	require.NotEqual(t, physical[1].ID, physical[3].ID)
	// Check that the two different physical alerts refer to the same logical alert
	require.Equal(t, physical[1].LogicalAlertID, physical[3].LogicalAlertID)

	// Run a third analysis with different data.
	analysis = e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "facefeed"}, "../sarif/testdata/example2-codeql.sarif")

	db.Find(&physical)
	// Check that it created similar but different physical alerts
	require.Equal(t, 8, len(physical))
	db.Find(&logical)
	// Check that we got 2 new logical alerts
	require.Equal(t, 4, len(logical))
	// Test that we have a timeline event for each ref elimination point
	var event2 []ts.TimelineEvent
	db.Where("event_type = ?", ts.TimelineEventTypeAlertClosedBecameFixed).Find(&event2)
	require.Equal(t, 2, len(event2))
	require.Equal(t, logical[0].ID, event2[1].LogicalAlertID)
	require.Equal(t, logical[0].RepositoryID, event2[1].RepositoryID)
	require.Equal(t, analysis.ID, event2[1].AnalysisID)
	require.Equal(t, analysis.Environment, event2[1].Environment)
	require.Equal(t, analysis.CommitOid, event2[1].CommitOid)
	require.Equal(t, analysis.Ref, []byte(event2[1].Ref))
	require.Equal(t, logical[0].FilePath, event2[1].FilePath)
	require.Equal(t, logical[0].Region.StartLine, event2[1].StartLine)
	require.Equal(t, analysis.ToolVersionID, event2[1].ToolVersionID)
	require.Equal(t, logical[1].ID, event2[0].LogicalAlertID)
	require.Equal(t, logical[1].RepositoryID, event2[0].RepositoryID)
	require.Equal(t, analysis.ID, event2[0].AnalysisID)
	require.Equal(t, analysis.Environment, event2[0].Environment)
	require.Equal(t, analysis.CommitOid, event2[0].CommitOid)
	require.Equal(t, analysis.Ref, []byte(event2[0].Ref))
	require.Equal(t, logical[1].FilePath, event2[0].FilePath)
	require.Equal(t, logical[1].Region.StartLine, event2[0].StartLine)
	require.Equal(t, analysis.ToolVersionID, event2[0].ToolVersionID)
	// This analysis has a baseline, so we can expect branch-related timeline events.
	// Test that we have a timeline event (alert appeared in ref, or reappeared) for each ref introduction point
	var event3 []ts.TimelineEvent
	db.Where("event_type = ? or event_type = ?", ts.TimelineEventTypeAlertAppearedInBranch, ts.TimelineEventTypeAlertReappeared).Find(&event3)
	require.Equal(t, 2, len(event3))
	require.Equal(t, logical[2].ID, event3[0].LogicalAlertID)
	require.Equal(t, logical[2].RepositoryID, event3[0].RepositoryID)
	require.Equal(t, analysis.ID, event3[0].AnalysisID)
	require.Equal(t, analysis.Environment, event3[0].Environment)
	require.Equal(t, analysis.CommitOid, event3[0].CommitOid)
	require.Equal(t, analysis.Ref, []byte(event3[0].Ref))
	require.Equal(t, logical[2].FilePath, event3[0].FilePath)
	require.Equal(t, logical[2].Region.StartLine, event3[0].StartLine)
	require.Equal(t, analysis.ToolVersionID, event3[0].ToolVersionID)
	require.Equal(t, logical[3].ID, event3[1].LogicalAlertID)
	require.Equal(t, logical[3].RepositoryID, event3[1].RepositoryID)
	require.Equal(t, analysis.ID, event3[1].AnalysisID)
	require.Equal(t, analysis.Environment, event3[1].Environment)
	require.Equal(t, analysis.CommitOid, event3[1].CommitOid)
	require.Equal(t, analysis.Ref, []byte(event3[1].Ref))
	require.Equal(t, logical[3].FilePath, event3[1].FilePath)
	require.Equal(t, logical[3].Region.StartLine, event3[1].StartLine)
	require.Equal(t, analysis.ToolVersionID, event3[1].ToolVersionID)

	// Run an analysis with the same commit ID as the previous one, but different alerts. This could happen if the queries being run changed.
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "facefeed"}, "../sarif/testdata/example.sarif")
}

func TestSaveAlersWithDuplicates(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	repositoryID := testRepoID
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/example_dup.sarif")

	var physical []ts.PhysicalAlert
	require.NoError(t, db.Find(&physical).Error)
	require.Equal(t, 3, len(physical))
	require.Equal(t, physical[1].StableAlertIdentifier[:20], physical[0].StableAlertIdentifier[:20], "Stable id base is the same")
	require.Equal(t, uint8(0), physical[0].StableAlertIdentifier[20])
	require.Equal(t, uint8(1), physical[1].StableAlertIdentifier[20])

	var logical []ts.LogicalAlert
	require.NoError(t, db.Find(&logical).Error)
	require.Equal(t, 3, len(logical), "Duplicated physical alerts point to different logical alert")
	require.Equal(t, "main.js", logical[0].FilePath)
	require.Equal(t, "main.js", logical[1].FilePath)
}

func TestSaveAlertRules(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/example.sarif")

	var physicals []ts.PhysicalAlert
	err := db.Find(&physicals).Error
	require.NoError(t, err)
	require.Equal(t, 2, len(physicals))

	var logicals []ts.LogicalAlert
	err = db.Find(&logicals).Error
	require.NoError(t, err)
	require.Equal(t, 2, len(logicals))

	dbtest.RequireCount(t, 2, db.Model(&ts.Rule{}))

	var rule ts.Rule
	err = db.Model(physicals[1]).Related(&rule).Error
	require.NoError(t, err)
	require.NotNil(t, rule)
	require.Equal(t, "js/inconsistent-use-of-new", rule.Name)

	var rule2 ts.Rule
	err = db.Model(logicals[1]).Related(&rule2).Error
	require.NoError(t, err)
	require.NotNil(t, rule2)
	require.Equal(t, "js/inconsistent-use-of-new", rule2.Name)
}

func TestResolveLogicalAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)

	as := alert.TestService(db)
	ctx := context.Background()

	someUserID := ts.UserEID(999)
	resolvedAt := sqltime.Date(2018, time.February, 16, 0, 0, 0, 0, time.UTC)
	la0 := ts.LogicalAlert{
		RepositoryID:          1,
		Number:                3,
		Resolution:            ts.AlertResolutionNone,
		ResolverID:            nil,
		StableAlertIdentifier: []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	la1 := ts.LogicalAlert{
		RepositoryID:          1,
		Number:                5,
		Resolution:            ts.AlertResolutionFalsePositive,
		ResolverID:            &someUserID,
		ResolvedAt:            &resolvedAt,
		StableAlertIdentifier: []byte{2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	dbtest.RequireCreate(t, db, &la0)
	dbtest.RequireCreate(t, db, &la1)
	las := []*ts.LogicalAlert{&la0, &la1}

	expectedResolverID := ts.UserEID(123)
	expectedResolutionNote := ts.ToNote("I don't want to fix this.")
	now := sqltime.Now()
	err := as.ResolveLogicalAlerts(ctx, las, ts.AlertResolutionWontFix, expectedResolverID, expectedResolutionNote, now)
	require.NoError(t, err)

	actual := []ts.LogicalAlert{}
	err = db.Find(&actual).Error
	require.NoError(t, err)
	require.Len(t, actual, 2)

	require.Equal(t, las[0].RepositoryID, actual[0].RepositoryID)
	require.Equal(t, las[1].RepositoryID, actual[1].RepositoryID)
	require.Equal(t, ts.AlertResolutionWontFix, actual[0].Resolution)
	require.Equal(t, ts.AlertResolutionWontFix, las[0].Resolution)
	require.Equal(t, ts.AlertResolutionWontFix, actual[1].Resolution)
	require.Equal(t, ts.AlertResolutionWontFix, las[1].Resolution)
	require.Equal(t, &expectedResolverID, actual[0].ResolverID)
	require.Equal(t, &expectedResolverID, las[0].ResolverID)
	require.Equal(t, &expectedResolverID, actual[1].ResolverID)
	require.Equal(t, &expectedResolverID, las[1].ResolverID)
	require.Equal(t, &now, actual[0].ResolvedAt)
	require.Equal(t, &now, las[0].ResolvedAt)
	require.Equal(t, &now, actual[1].ResolvedAt)
	require.Equal(t, &now, las[1].ResolvedAt)
	require.Equal(t, expectedResolutionNote, actual[0].ResolutionNote)
	require.Equal(t, expectedResolutionNote, actual[1].ResolutionNote)
	// LastStateChangeAt should be set on the passed in logical alerts
	require.Equal(t, &now, las[0].LastStateChangeAt)
	require.Equal(t, &now, las[1].LastStateChangeAt)
	// LastStateChangeAt should be nil on the loaded logical alerts, as it is not stored in DB
	require.Nil(t, actual[0].LastStateChangeAt)
	require.Nil(t, actual[1].LastStateChangeAt)
}

func TestReopenLogicalAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	resolverID := ts.UserEID(1)
	resolvedAt := sqltime.Date(2018, time.February, 16, 0, 0, 0, 0, time.UTC)
	la0 := ts.LogicalAlert{
		RepositoryID:          1,
		Number:                3,
		Resolution:            ts.AlertResolutionUsedInTests,
		ResolverID:            &resolverID,
		ResolvedAt:            &resolvedAt,
		StableAlertIdentifier: []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	la1 := ts.LogicalAlert{
		RepositoryID:          1,
		Number:                5,
		Resolution:            ts.AlertResolutionFalsePositive,
		ResolverID:            &resolverID,
		ResolvedAt:            &resolvedAt,
		StableAlertIdentifier: []byte{2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	dbtest.RequireCreate(t, db, &la0)
	dbtest.RequireCreate(t, db, &la1)

	oldDateTime := sqltime.Date(2020, 1, 20, 10, 0, 0, 0, sqltime.DatabaseLocation)

	p1 := ts.PhysicalAlert{
		AnalysisID:            1,
		RepositoryID:          la0.RepositoryID,
		LogicalAlertID:        la0.ID,
		StableAlertIdentifier: la0.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     oldDateTime,
	}
	p2 := ts.PhysicalAlert{
		AnalysisID:            1,
		RepositoryID:          la1.RepositoryID,
		LogicalAlertID:        la1.ID,
		StableAlertIdentifier: la1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     oldDateTime,
	}

	dbtest.RequireCreate(t, db, &p1)
	dbtest.RequireCreate(t, db, &p2)

	las := []*ts.LogicalAlert{&la0, &la1}

	err := as.ReopenLogicalAlerts(ctx, las, sqltime.Now())
	require.NoError(t, err)

	actual := []ts.LogicalAlert{}
	err = db.Find(&actual).Error
	require.NoError(t, err)
	require.Len(t, actual, 2)

	require.Equal(t, las[0].RepositoryID, actual[0].RepositoryID)
	require.Equal(t, las[1].RepositoryID, actual[1].RepositoryID)
	require.Equal(t, ts.AlertResolutionNone, actual[0].Resolution)
	require.Equal(t, ts.AlertResolutionNone, actual[1].Resolution)
	require.Nil(t, actual[0].ResolverID)
	require.Nil(t, actual[1].ResolverID)
	require.Nil(t, actual[0].ResolvedAt)
	require.Nil(t, actual[1].ResolvedAt)
	// Allow the serializer to default to UpdatedAt in place of LastStateChangeAt in this case.
	require.Nil(t, las[0].LastStateChangeAt)
	require.Nil(t, las[1].LastStateChangeAt)
	// LastStateChangeAt not stored directly in the DB, and should always be Nil
	require.Nil(t, actual[0].LastStateChangeAt)
	require.Nil(t, actual[1].LastStateChangeAt)

	actualAlerts := []ts.PhysicalAlert{}
	err = db.Find(&actualAlerts).Error
	require.NoError(t, err)
	require.Len(t, actual, 2)

	// verify that the associated physical alerts all reflect the change in alert state
	require.Greater(t, actualAlerts[0].LastStateChangeAt.UnixMicro(), oldDateTime.UnixMicro())
	require.Greater(t, actualAlerts[1].LastStateChangeAt.UnixMicro(), oldDateTime.UnixMicro())
}

func TestPutGet(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	e := requireTestEnv(t, db)
	ctx := context.Background()

	e.deliverSARIF(testConfig{repositoryID: testRepoID, commitOid: "xxx"}, "../sarif/testdata/example.sarif")

	options := &ts.FindOptions{
		Pagination: &ts.Pagination{Limit: 100},
		Preloads:   []string{"Rule", "PhysicalAlerts"},
		SortBy:     alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING),
	}

	logicalAlerts, err := as.Alerts(ctx, testRepoID, nofilter, repoAnalysisFilter, options)
	require.NoError(t, err)

	e.requireCounts(testRepoID, nofilter, repoAnalysisFilter, 2, 0)
	require.Equal(t, 2, len(logicalAlerts))

	require.Equal(t, uint32(1), logicalAlerts[0].Number)

	require.Equal(t, 1, len(logicalAlerts[0].PhysicalAlerts))
	require.Equal(t, "main.js", logicalAlerts[0].FilePath)
	require.Equal(t, "js/unused-local-variable", logicalAlerts[0].Rule.SarifIdentifier)
	require.Equal(t, uint32(2), logicalAlerts[1].Number)
	require.Equal(t, 1, len(logicalAlerts[1].PhysicalAlerts))
	require.Equal(t, "src/promiseUtils.js", logicalAlerts[1].FilePath)
	require.Equal(t, "js/inconsistent-use-of-new", logicalAlerts[1].Rule.SarifIdentifier)
}

func TestRules(t *testing.T) {
	db := dbtest.RequireConnection(t)

	tool := &ts.ToolVersion{
		Name:    "CodeQL",
		Version: "2.0.1",
		ToolID:  1519,
		Tool: &ts.Tool{
			ID:            1519,
			GUID:          "",
			CanonicalName: "CodeQL",
		},
	}

	as := alert.TestService(db)
	ctx := context.Background()
	dbtest.RequireCreate(t, db, &tool.Tool)

	shiftLeftTool := &ts.Tool{
		CanonicalName: "ShiftLeft",
	}

	a1 := ts.Analysis{
		Ref:                []byte("main"),
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		ToolID:             tool.ToolID,
		MostRecent:         false,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a1)

	a2 := ts.Analysis{
		Ref:                []byte("main"),
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		ToolID:             shiftLeftTool.ID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a2)

	// Prepare 3 rules, only 2 of them are used in the repository
	rule1 := &ts.Rule{
		SarifIdentifier: "js/rule1",
		Tags: []ts.RuleTag{
			{Tag: "red"},
			{Tag: "green"},
		},
		ToolID: tool.ToolID,
	}
	rule2 := &ts.Rule{
		SarifIdentifier: "js/rule2",
		Tags: []ts.RuleTag{
			{Tag: "blue"},
			{Tag: "red"},
		},
		ToolID: shiftLeftTool.ID,
	}
	rule3 := &ts.Rule{
		ToolID:          tool.ToolID,
		SarifIdentifier: "js/rule3",
	}
	dbtest.RequireCreate(t, db, rule1)
	dbtest.RequireCreate(t, db, rule2)
	dbtest.RequireCreate(t, db, rule3)

	l1 := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                1,
		RuleID:                rule1.ID,
		StableAlertIdentifier: []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	dbtest.RequireCreate(t, db, l1)

	l2 := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                2,
		RuleID:                rule1.ID,
		StableAlertIdentifier: []byte{2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	dbtest.RequireCreate(t, db, l2)

	l3 := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                3,
		RuleID:                rule2.ID,
		StableAlertIdentifier: []byte{3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	dbtest.RequireCreate(t, db, l3)

	p1 := ts.PhysicalAlert{
		AnalysisID:            a1.ID,
		RepositoryID:          a1.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p1)

	p2 := ts.PhysicalAlert{
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: l2.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p2)

	p3 := ts.PhysicalAlert{
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l3.ID,
		StableAlertIdentifier: l3.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p3)

	rules, err := as.AlertsRules(ctx, ts.RuleFilter{RepoID: testRepoID})
	require.NoError(t, err)
	require.Len(t, rules, 2)
	require.True(t, rule1.SarifIdentifier == rules[0].SarifIdentifier || rule1.SarifIdentifier == rules[1].SarifIdentifier)
	require.True(t, rule2.SarifIdentifier == rules[0].SarifIdentifier || rule2.SarifIdentifier == rules[1].SarifIdentifier)
	// Make consistent ruleA = rule1, ruleB = rule2
	ruleA := rules[0]
	ruleB := rules[1]
	if ruleA.SarifIdentifier == rule2.SarifIdentifier {
		ruleA, ruleB = ruleB, ruleA
	}
	require.ElementsMatch(t, rule1.Tags, ruleA.Tags)
	require.ElementsMatch(t, rule2.Tags, ruleB.Tags)
	require.Equal(t, rule1.ToolID, ruleA.ToolID)
	require.Equal(t, rule2.ToolID, ruleB.ToolID)

	rules, err = as.AlertsRules(ctx, ts.RuleFilter{RepoID: testRepoID, ToolIDs: []ts.ToolID{tool.ToolID}})
	require.NoError(t, err)
	require.Len(t, rules, 1)
	require.Equal(t, rule1.SarifIdentifier, rules[0].SarifIdentifier)
	require.ElementsMatch(t, rule1.Tags, rules[0].Tags)
	require.Equal(t, rule1.ToolID, rules[0].ToolID)

	rules, err = as.AlertsRules(ctx, ts.RuleFilter{RepoID: testRepoID, Tags: []string{"blue"}})
	require.NoError(t, err)
	require.Len(t, rules, 1)
	require.Equal(t, rule2.SarifIdentifier, rules[0].SarifIdentifier)
	require.ElementsMatch(t, rule2.Tags, rules[0].Tags)
	require.Equal(t, rule2.ToolID, rules[0].ToolID)

	rules, err = as.AlertsRules(ctx, ts.RuleFilter{RepoID: 1})
	require.NoError(t, err)
	require.Len(t, rules, 0)
}

func TestRuleFilterTags(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	codeQLTool := ts.ToolID(1)

	rule1 := &ts.Rule{
		SarifIdentifier: "js/rule2",
		Tags: []ts.RuleTag{
			{Tag: "high"},
		},
		ToolID: codeQLTool,
	}
	dbtest.RequireCreate(t, db, rule1)

	rule2 := &ts.Rule{
		SarifIdentifier: "js/rule2",
		Tags: []ts.RuleTag{
			{Tag: "critical"},
			{Tag: "low"},
			{Tag: "other"},
		},
		ToolID: codeQLTool,
	}
	dbtest.RequireCreate(t, db, rule2)

	a := &ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/bbb"),
		ToolID:             codeQLTool,
	}
	dbtest.RequireCreate(t, db, a)

	la1 := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                1,
		RuleID:                rule1.ID,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, la1)
	pa1 := &ts.PhysicalAlert{
		RepositoryID:          testRepoID,
		RuleID:                rule1.ID,
		LogicalAlertID:        la1.ID,
		AnalysisID:            a.ID,
		StableAlertIdentifier: la1.StableAlertIdentifier,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, pa1)
	la2 := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                2,
		RuleID:                rule2.ID,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, la2)
	pa2 := &ts.PhysicalAlert{
		RepositoryID:          testRepoID,
		RuleID:                rule2.ID,
		LogicalAlertID:        la2.ID,
		AnalysisID:            a.ID,
		StableAlertIdentifier: la2.StableAlertIdentifier,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, pa2)

	rules, err := as.AlertsRules(ctx, ts.RuleFilter{
		RepoID:  testRepoID,
		ToolIDs: []ts.ToolID{codeQLTool},
		Tags:    []string{"critical", "low"},
	})
	require.NoError(t, err)
	require.Len(t, rules, 1)
	require.Equal(t, rules[0].ID, rule2.ID)
}

func TestRuleFilterAllTools(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	tool := &ts.ToolVersion{
		Name:    "CodeQL",
		Version: "2.0.1",
		ToolID:  1519,
		Tool: &ts.Tool{
			ID:            1519,
			GUID:          "",
			CanonicalName: "CodeQL",
		},
	}

	dbtest.RequireCreate(t, db, &tool.Tool)

	rule1 := &ts.Rule{
		SarifIdentifier: "js/rule2",
		Tags: []ts.RuleTag{
			{Tag: "critical"},
			{Tag: "low"},
		},
		ToolID: tool.ToolID,
	}
	dbtest.RequireCreate(t, db, rule1)

	a := &ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		CommitOid:          "deadbeef",
		Ref:                []byte("main"),
		ToolID:             tool.ToolID,
		ToolVersionID:      tool.ID,
		Environment:        ts.AnalysisEnv{},
		WorkflowRunID:      101,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, a)

	la1 := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                1,
		RuleID:                rule1.ID,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, la1)
	pa1 := &ts.PhysicalAlert{
		RepositoryID:          testRepoID,
		RuleID:                rule1.ID,
		LogicalAlertID:        la1.ID,
		AnalysisID:            a.ID,
		StableAlertIdentifier: la1.StableAlertIdentifier,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, pa1)

	rules, err := as.AlertsRules(ctx, ts.RuleFilter{
		RepoID: testRepoID,
		Tags:   []string{"critical"},
	})
	require.NoError(t, err)
	require.Len(t, rules, 1)
	require.Equal(t, rules[0].ID, rule1.ID)
}

func TestRuleFilterAllTags(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	codeQLTool := ts.ToolID(1)

	rule1 := &ts.Rule{
		SarifIdentifier: "js/rule2",
		Tags: []ts.RuleTag{
			{Tag: "critical"},
			{Tag: "low"},
		},
		ToolID: codeQLTool,
	}
	dbtest.RequireCreate(t, db, rule1)

	a := &ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/bbb"),
		ToolID:             codeQLTool,
	}
	dbtest.RequireCreate(t, db, a)

	la1 := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                1,
		RuleID:                rule1.ID,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, la1)
	pa1 := &ts.PhysicalAlert{
		RepositoryID:          testRepoID,
		RuleID:                rule1.ID,
		LogicalAlertID:        la1.ID,
		AnalysisID:            a.ID,
		StableAlertIdentifier: la1.StableAlertIdentifier,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, pa1)

	// must match ALL tags
	rules, err := as.AlertsRules(ctx, ts.RuleFilter{
		RepoID:  testRepoID,
		ToolIDs: []ts.ToolID{codeQLTool},
		Tags:    []string{"critical", "low", "other"},
	})
	require.NotNil(t, rules)
	require.NoError(t, err)
	require.Len(t, rules, 0)
}

func TestSaveAlertsWithMissingLocationRegion(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/example3.sarif")
}

func TestSaveAlertsWithNoRules(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/no_rules.sarif")

	rules, err := e.as.AlertsRules(e.ctx, ts.RuleFilter{RepoID: repositoryID})
	require.NoError(t, err)
	require.Len(t, rules, 1)
	require.Equal(t, "[unknown-rule]", rules[0].SarifIdentifier)
}

func TestSaveAlertsWithExtensions(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)
	a := e.deliverAndStoreSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/exampleExtensions.sarif", nil)

	err := e.archiveService.Unarchive(e.ctx, a)
	require.NoError(t, err)
	require.Len(t, a.Rules, 2)
}

func TestSaveAlertsWithResultSeverity(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/severity.sarif")

	var alerts []ts.LogicalAlert
	err := db.Find(&alerts).Error
	require.NoError(t, err)
	require.Len(t, alerts, 4)
	for _, a := range alerts {
		switch a.Message {
		case "Result specifies severity level":
			require.Equal(t, ts.SeverityLevelError, a.SeverityLevel)
		case "Result overrides rules severity level":
			require.Equal(t, ts.SeverityLevelError, a.SeverityLevel)
		case "Rule defines severity level":
			require.Equal(t, ts.SeverityLevelNote, a.SeverityLevel)
		case "Neither rule or result defines severity level":
			require.Equal(t, ts.SeverityLevelWarning, a.SeverityLevel)
		default:
			require.Fail(t, "Unexpected result found")
		}
	}
}

func TestSaveAlertsWithWeight(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/severity.sarif")

	var alerts []ts.LogicalAlert
	err := db.Preload("PhysicalAlerts").Preload("Rule").Find(&alerts).Error
	require.NoError(t, err)
	require.Len(t, alerts, 4)
	for _, a := range alerts {
		require.NoError(t, err)
		switch a.Message {
		case "Result specifies severity level":
			// Default rule is associated with precision 0
			weight := ts.MagicWeight(ts.SeverityLevelError, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelUnknown)
			require.Equal(t, weight, a.Weight)
		case "Result overrides rules severity level":
			weight := ts.MagicWeight(ts.SeverityLevelError, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelVeryHigh)
			require.Equal(t, weight, a.Weight)
		case "Rule defines severity level":
			weight := ts.MagicWeight(ts.SeverityLevelNote, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelVeryHigh)
			require.Equal(t, weight, a.Weight)
		case "Neither rule or result defines severity level":
			// Default rule is associate with precision Unknonw and severity Warning
			weight := ts.MagicWeight(ts.SeverityLevelWarning, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelUnknown)
			require.Equal(t, weight, a.Weight)
		default:
			require.Fail(t, "Unexpected result found")
		}
	}
}

func TestSaveAlertsWithUpdatedWeight(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)

	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef1"}, "../sarif/testdata/severity.sarif")

	var targetAlert ts.LogicalAlert
	require.NoError(t, db.Where("message = ?", "Result overrides rules severity level").First(&targetAlert).Error)
	weight := ts.MagicWeight(ts.SeverityLevelError, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelVeryHigh)
	require.Equal(t, weight, targetAlert.Weight)

	// The second delivery changes the severity of the physical alert
	// and thus the logical alert should update
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef2"}, "../sarif/testdata/severity2.sarif")
	require.NoError(t, db.First(&targetAlert, "id = ?", targetAlert.ID).Error)
	newWeight := ts.MagicWeight(ts.SeverityLevelNote, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelVeryHigh)
	require.Equal(t, newWeight, targetAlert.Weight)
}

func TestSaveAlertsWithUpdatedSeverities(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)

	analysis := e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef1"}, "../sarif/testdata/security-severity-small.sarif")

	var p ts.PhysicalAlert
	var targetAlert ts.LogicalAlert
	require.NoError(e.t, db.First(&p, "analysis_id = ?", analysis.ID).Error)
	require.NoError(t, db.First(&targetAlert, "id = ?", p.LogicalAlertID).Error)
	require.Equal(t, 7.8, *targetAlert.SecuritySeverity)
	require.Equal(t, p.SecuritySeverity, targetAlert.SecuritySeverity)
	require.Equal(t, ts.SeverityLevelError, targetAlert.SeverityLevel)

	// The second delivery changes the severities of the physical alert
	// and thus the logical alert should update
	analysis2 := e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef2"}, "../sarif/testdata/security-severity-small2.sarif")

	var p2 ts.PhysicalAlert
	var targetAlert2 ts.LogicalAlert
	require.NoError(e.t, db.First(&p2, "analysis_id = ?", analysis2.ID).Error)
	require.NoError(t, db.First(&targetAlert2, "id = ?", p2.LogicalAlertID).Error)
	require.Equal(t, 5.0, *targetAlert2.SecuritySeverity)
	require.Equal(t, p2.SecuritySeverity, targetAlert2.SecuritySeverity)
	require.Equal(t, ts.SeverityLevelWarning, targetAlert2.SeverityLevel)
}

func TestSaveAlertsWithUpdatedRule(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)

	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef1"}, "../sarif/testdata/rule1.sarif")

	var origAlert, updatedAlert ts.LogicalAlert
	require.NoError(t, db.Where("message = ?", "before").Preload("PhysicalAlerts").First(&origAlert).Error)

	// The second delivery changes the severity of the rule
	// and thus the logical alert should update
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef2"}, "../sarif/testdata/rule2.sarif")
	require.NoError(t, db.Where("message = ?", "after").First(&updatedAlert).Error)
	require.Equal(t, origAlert.ID, updatedAlert.ID)
	require.NotEqual(t, origAlert.RuleID, updatedAlert.RuleID)
}

func TestAlertRule(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	repoID := testRepoID
	toolID := ts.ToolID(1)
	sarifID := "js/rule1"
	ruleName := "TestRule"

	rule := &ts.Rule{
		SarifIdentifier: sarifID,
		ToolID:          toolID,
		Name:            ruleName,
	}
	dbtest.RequireCreate(t, db, rule)

	r, err := as.Rule(ctx, repoID, toolID, sarifID)
	require.NoError(t, err)
	require.Equal(t, rule.Name, r.Name)
}

func TestRulesTags(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()
	repo := testRepoID

	a := ts.Analysis{
		Ref:                []byte("main"),
		RepositoryID:       repo,
		SourceRepositoryID: repo,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a)

	tool1 := ts.ToolID(1)
	tool2 := ts.ToolID(2)

	// Prepare 3 rules, only 2 of them are in the same repository
	rule1 := &ts.Rule{
		SarifIdentifier: "js/rule1",
		ToolID:          tool1,
		Tags: []ts.RuleTag{
			{Tag: "red"},
			{Tag: "green"},
		},
	}
	rule2 := &ts.Rule{
		SarifIdentifier: "js/rule2",
		ToolID:          tool2,
		Tags: []ts.RuleTag{
			{Tag: "blue"},
			{Tag: "red"},
		},
	}
	rule3 := &ts.Rule{
		SarifIdentifier: "js/rule3",
		Tags: []ts.RuleTag{
			{Tag: "yellow"},
		},
	}
	dbtest.RequireCreate(t, db, rule1)
	dbtest.RequireCreate(t, db, rule2)
	dbtest.RequireCreate(t, db, rule3)
	dbtest.RequireCount(t, 5, db.Model(ts.RuleTag{}))

	l1 := &ts.LogicalAlert{
		RepositoryID:          repo,
		Number:                1,
		RuleID:                rule1.ID,
		StableAlertIdentifier: []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	dbtest.RequireCreate(t, db, l1)

	l2 := &ts.LogicalAlert{
		RepositoryID:          repo,
		Number:                2,
		RuleID:                rule2.ID,
		StableAlertIdentifier: []byte{2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	dbtest.RequireCreate(t, db, l2)

	l3 := &ts.LogicalAlert{
		RepositoryID:          0,
		Number:                3,
		RuleID:                rule3.ID,
		StableAlertIdentifier: []byte{3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	dbtest.RequireCreate(t, db, l3)

	p1 := ts.PhysicalAlert{
		AnalysisID:            a.ID,
		RepositoryID:          a.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p1)

	p2 := ts.PhysicalAlert{
		AnalysisID:            a.ID,
		RepositoryID:          a.RepositoryID,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: l2.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p2)

	p3 := ts.PhysicalAlert{
		AnalysisID:            a.ID,
		RepositoryID:          a.RepositoryID,
		LogicalAlertID:        l3.ID,
		StableAlertIdentifier: l3.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p3)

	tags, err := as.RulesTags(ctx, ts.RuleTagFilter{RepoID: repo})
	require.NoError(t, err)
	require.Len(t, tags, 3)
	require.Contains(t, tags, "red")
	require.Contains(t, tags, "blue")
	require.Contains(t, tags, "green")

	tags, err = as.RulesTags(ctx, ts.RuleTagFilter{RepoID: repo, ToolIDs: []ts.ToolID{tool1}})
	require.NoError(t, err)
	require.Len(t, tags, 2)
	require.Contains(t, tags, "red")
	require.Contains(t, tags, "green")

	tags, err = as.RulesTags(ctx, ts.RuleTagFilter{RepoID: 1})
	require.NoError(t, err)
	require.Len(t, tags, 0)

	// Delete alert number 1, rule1.ID should not appear anymore.
	require.NoError(t, db.Model(&ts.LogicalAlert{}).Where("repository_id = ? AND number = ?", testRepoID, 1).Update("soft_deleted_at", sqltime.Time{Time: time.Now()}).Error)

	tags, err = as.RulesTags(ctx, ts.RuleTagFilter{RepoID: repo, ToolIDs: []ts.ToolID{tool1}})
	require.NoError(t, err)
	require.Len(t, tags, 0)
}

// Test that Alerts correctly retrieves and preloads the canonical alert when p1 is newer.
func TestAlerts_WithCanonical(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	tool := &ts.Tool{CanonicalName: "CodeQL"}
	dbtest.RequireCreate(t, db, &tool)

	a1 := ts.Analysis{
		Tool:               tool,
		Ref:                []byte("refs/heads/main"),
		Category:           "windows",
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a1)
	a2 := ts.Analysis{
		Tool:               tool,
		Ref:                []byte("refs/heads/main"),
		Category:           "linux",
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a2)

	l1 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 1, StableAlertIdentifier: newStableID()}
	dbtest.RequireCreate(t, db, &l1)

	l2 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 2, StableAlertIdentifier: newStableID()}
	dbtest.RequireCreate(t, db, &l2)

	p1 := ts.PhysicalAlert{
		AnalysisID:            a1.ID,
		RepositoryID:          a1.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p1)

	p2 := ts.PhysicalAlert{
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: time.Now().Add(-1 * time.Hour)},
		},
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p2)

	p3 := ts.PhysicalAlert{
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: l2.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p3)

	// The canonical alert should be p1 as it has a CreatedAt after p2
	alerts, err := e.as.Alerts(e.ctx, testRepoID, ts.AlertFilter{}, ts.AnalysisFilter{RepositoryID: testRepoID, Refs: [][]byte{[]byte("refs/heads/main")}, State: ts.AnalysisStateFilterMostRecent}, &ts.FindOptions{Preloads: []string{"PhysicalAlerts", "PhysicalAlerts.Analysis", "PhysicalAlerts.Analysis.Tool"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, alerts[0].PhysicalAlerts, 1)
	require.Len(t, alerts[1].PhysicalAlerts, 1)
	require.NotNil(t, alerts[1].PhysicalAlerts[0])
	require.NotNil(t, alerts[0].PhysicalAlerts[0])
	require.NotNil(t, alerts[1].PhysicalAlerts[0])
	require.NotNil(t, alerts[0].PhysicalAlerts[0].Analysis)
	require.Equal(t, p1.ID, alerts[0].PhysicalAlerts[0].ID)
	require.Equal(t, p3.ID, alerts[1].PhysicalAlerts[0].ID)
	require.Equal(t, a1.ID, alerts[0].PhysicalAlerts[0].Analysis.ID)
	require.NotNil(t, alerts[0].PhysicalAlerts[0].Analysis.Tool)
}

// Test that Alerts correctly retrieves and preloads the canonical alert when p2 is newer.
func TestAlerts_WithCanonicalReversed(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	tool := &ts.Tool{CanonicalName: "CodeQL"}
	dbtest.RequireCreate(t, db, &tool)

	a1 := ts.Analysis{
		Tool:               tool,
		Ref:                []byte("main"),
		Category:           "windows",
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a1)
	a2 := ts.Analysis{
		Tool:               tool,
		Ref:                []byte("main"),
		Category:           "linux",
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a2)

	l1 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 1, StableAlertIdentifier: newStableID()}
	dbtest.RequireCreate(t, db, &l1)

	l2 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 2, StableAlertIdentifier: newStableID()}
	dbtest.RequireCreate(t, db, &l2)

	p1 := ts.PhysicalAlert{
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: time.Now().Add(-1 * time.Hour)},
		},
		AnalysisID:            a1.ID,
		RepositoryID:          a1.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p1)

	p2 := ts.PhysicalAlert{
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p2)

	p3 := ts.PhysicalAlert{
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: l2.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p3)

	// The canonical alert should be p1 as it has a CreatedAt after p2
	alerts, err := e.as.Alerts(e.ctx, testRepoID, ts.AlertFilter{}, repoAnalysisFilter, &ts.FindOptions{Preloads: []string{"PhysicalAlerts", "PhysicalAlerts.Analysis", "PhysicalAlerts.Analysis.Tool"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Equal(t, 2, len(alerts))
	require.Len(t, alerts[0].PhysicalAlerts, 1)
	require.Len(t, alerts[1].PhysicalAlerts, 1)
	require.NotNil(t, alerts[1].PhysicalAlerts[0])
	require.NotNil(t, alerts[0].PhysicalAlerts[0])
	require.NotNil(t, alerts[1].PhysicalAlerts[0])
	require.NotNil(t, alerts[0].PhysicalAlerts[0].Analysis)
	require.Equal(t, p2.ID, alerts[0].PhysicalAlerts[0].ID)
	require.Equal(t, p3.ID, alerts[1].PhysicalAlerts[0].ID)
	require.Equal(t, a2.ID, alerts[0].PhysicalAlerts[0].Analysis.ID)
	require.NotNil(t, alerts[0].PhysicalAlerts[0].Analysis.Tool)
}

// Test that Alerts correctly retrieves and preloads the canonical alert when the created_at has a duplicate.
func TestAlerts_WithCanonicalSameTimestamp(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	tool := &ts.Tool{CanonicalName: "CodeQL"}
	dbtest.RequireCreate(t, db, &tool)

	a1 := ts.Analysis{
		Tool:               tool,
		Ref:                []byte("main"),
		Category:           "windows",
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a1)
	a2 := ts.Analysis{
		Tool:               tool,
		Ref:                []byte("main"),
		Category:           "linux",
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a2)

	l1 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 1, StableAlertIdentifier: newStableID()}
	dbtest.RequireCreate(t, db, &l1)

	l2 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 2, StableAlertIdentifier: newStableID()}
	dbtest.RequireCreate(t, db, &l2)

	now := sqltime.Time{Time: time.Now()}

	p1 := ts.PhysicalAlert{
		ID: 201,
		BaseModel: ts.BaseModel{
			CreatedAt: now,
		},
		AnalysisID:            a1.ID,
		RepositoryID:          a1.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p1)

	p2 := ts.PhysicalAlert{
		ID: 201001,
		BaseModel: ts.BaseModel{
			CreatedAt: now,
		},
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p2)

	p3 := ts.PhysicalAlert{
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: l2.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p3)

	// The canonical alert should be p2 as it was inserted after p1
	alerts, err := e.as.Alerts(e.ctx, testRepoID, ts.AlertFilter{}, repoAnalysisFilter, &ts.FindOptions{Preloads: []string{"PhysicalAlerts", "PhysicalAlerts.Analysis", "PhysicalAlerts.Analysis.Tool"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Equal(t, 2, len(alerts))
	require.Len(t, alerts[0].PhysicalAlerts, 1)
	require.Len(t, alerts[1].PhysicalAlerts, 1)
	require.NotNil(t, alerts[1].PhysicalAlerts[0])
	require.NotNil(t, alerts[0].PhysicalAlerts[0])
	require.NotNil(t, alerts[1].PhysicalAlerts[0])
	require.NotNil(t, alerts[0].PhysicalAlerts[0].Analysis)
	require.Equal(t, p2.ID, alerts[0].PhysicalAlerts[0].ID)
	require.Equal(t, p3.ID, alerts[1].PhysicalAlerts[0].ID)
	require.Equal(t, a2.ID, alerts[0].PhysicalAlerts[0].Analysis.ID)
	require.NotNil(t, alerts[0].PhysicalAlerts[0].Analysis.Tool)
}

func TestAlerts_FilePathFilter(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	a1 := ts.Analysis{
		Ref:                []byte("main"),
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a1)

	// filepath is part of the StableAlertIdentifier so we need two alerts here for the different languages

	l1 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 1, StableAlertIdentifier: newStableID(), SeverityLevel: ts.SeverityLevelError, FilePath: "foo/bar.go"}
	dbtest.RequireCreate(t, db, &l1)

	l2 := ts.LogicalAlert{RepositoryID: testRepoID, Number: 2, StableAlertIdentifier: newStableID(), SeverityLevel: ts.SeverityLevelWarning, FilePath: "foo/bar.go/bat.rb"}
	dbtest.RequireCreate(t, db, &l2)

	p1 := ts.PhysicalAlert{
		AnalysisID:            a1.ID,
		RepositoryID:          a1.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p1)

	a2 := ts.Analysis{
		Ref:                []byte("develop"),
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a2)
	p2 := ts.PhysicalAlert{
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: l2.StableAlertIdentifier,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(e.t, e.db, &p2)

	{
		filter := ts.AlertFilter{FilePaths: []string{"*.go"}}
		alerts, err := e.as.Alerts(
			e.ctx,
			testRepoID,
			filter,
			repoAnalysisFilter,
			&ts.FindOptions{Preloads: []string{"PhysicalAlerts"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)},
		)
		require.NoError(t, err)
		require.Equal(t, 1, len(alerts))
		require.Equal(t, 1, len(alerts[0].PhysicalAlerts))
		require.Equal(t, p1.ID, alerts[0].PhysicalAlerts[0].ID)
	}

	{
		filter := ts.AlertFilter{FilePaths: []string{"*.rb"}}
		alerts, err := e.as.Alerts(
			e.ctx,
			testRepoID,
			filter,
			repoAnalysisFilter,
			&ts.FindOptions{Preloads: []string{"PhysicalAlerts"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)},
		)
		require.NoError(t, err)
		require.Equal(t, 1, len(alerts))
		require.Equal(t, 1, len(alerts[0].PhysicalAlerts))
		require.Equal(t, p2.ID, alerts[0].PhysicalAlerts[0].ID)
	}
}

// testLogicalAlerts stores the logical alers in the db and creates
// linked physical alerts and logical refs entries
// It returns the same elements to make it easier to refer to them later
func (e *testEnv) testLogicalAlerts(la ...ts.LogicalAlert) []ts.LogicalAlert {
	for i, l := range la {
		l.StableAlertIdentifier = newStableID()
		dbtest.RequireCreate(e.t, e.db, &l)
		a := ts.Analysis{
			ID:                 ts.AnalysisID(l.RepositoryID),
			RepositoryID:       l.RepositoryID,
			SourceRepositoryID: l.RepositoryID,
			MostRecent:         true,
			AnalysisComplete:   true,
			Environment:        ts.AnalysisEnv{},
			Ref:                []byte("refs/heads/master"),
		}
		err := e.db.FirstOrCreate(&a, ts.Analysis{ID: a.ID}).Error
		require.NoError(e.t, err)

		p := &ts.PhysicalAlert{
			LogicalAlertID:        l.ID,
			RepositoryID:          l.RepositoryID,
			StableAlertIdentifier: l.StableAlertIdentifier,
			AnalysisID:            ts.AnalysisID(l.RepositoryID),
			RuleID:                l.RuleID,
			LastStateChangeAt:     sqltime.Now(),
		}

		dbtest.RequireCreate(e.t, e.db, p)
		l.PhysicalAlerts = []*ts.PhysicalAlert{p}
		la[i] = l
	}
	return la
}

var stableIDcounter = 0

func newStableID() []byte {
	stableIDcounter++
	stableID := make([]byte, 8)
	binary.BigEndian.PutUint64(stableID, uint64(stableIDcounter))
	return stableID
}

func (e *testEnv) requireCounts(repositoryID ts.RepositoryEID, filter ts.AlertFilter, analysisFilter ts.AnalysisFilter, expectedOpen uint64, expectedResolved uint64) {
	openFilter := filter
	openFilter.State = proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN
	actualOpen, err := e.as.Count(e.ctx, repositoryID, openFilter, analysisFilter)
	require.NoError(e.t, err)
	require.Equal(e.t, expectedOpen, actualOpen)
	resolvedFilter := filter
	resolvedFilter.State = proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED
	actualResolved, err := e.as.Count(e.ctx, repositoryID, resolvedFilter, analysisFilter)
	require.NoError(e.t, err)
	require.Equal(e.t, expectedResolved, actualResolved)
}

func createSeverityFilterAndGetAlerts(ctx context.Context, t *testing.T, as *alert.Service, severities []proto.Severity, excludedSeverities []proto.Severity, options *ts.FindOptions) (ts.AlertFilter, []*ts.LogicalAlert) {
	t.Helper()
	filter := ts.AlertFilter{SeverityLevels: severities, ExcludedSeverityLevels: excludedSeverities}
	logicalAlerts, err := as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, options)
	require.NoError(t, err)

	return filter, logicalAlerts
}

func (e *testEnv) verifyAlertCounts(t *testing.T, alerts ts.AlertFilter, logicalAlerts []*ts.LogicalAlert, expectedCount uint64) {
	t.Helper()
	require.Len(t, logicalAlerts, int(expectedCount))
	e.requireCounts(testRepoID, alerts, repoAnalysisFilter, expectedCount, 0)
}

// TestLimitsTooManyResults imports a file with 2000 rules and 2000 alerts. The
// import is truncated but consistent (all results have the associate rule
// imported).
func TestLimitsTooManyResults(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(999) // 999 has a special "small" group
	a := e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/limits_too_many_results.sarif")
	require.NotNil(t, a.ProcessWarning)
	require.Equal(t, "1000 results were ignored", *a.ProcessWarning)
	dbtest.RequireCount(t, 1000, db.Model(&ts.PhysicalAlert{}))
}

func TestRulesSharedBetweenAnalyses(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repositoryID := ts.RepositoryEID(1)
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "deadbeef"}, "../sarif/testdata/rules_shared_between_analyses1.sarif")
	e.deliverSARIF(testConfig{repositoryID: repositoryID, commitOid: "feedc0de"}, "../sarif/testdata/rules_shared_between_analyses2.sarif")
}

func TestMagicWeight(t *testing.T) {
	var tests = []struct {
		severity         ts.SeverityLevel
		securitySeverity proto.SecuritySeverity
		precision        ts.PrecisionLevel
		weight           uint16
	}{
		{ts.SeverityLevelNone, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelUnknown, 0},
		{ts.SeverityLevelError, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelUnknown, 150 + 0},
		{ts.SeverityLevelError, proto.SecuritySeverity_NO_SECURITY_SEVERITY, ts.PrecisionLevelVeryHigh, 150 + 90},
		{ts.SeverityLevelNone, proto.SecuritySeverity_MEDIUM, ts.PrecisionLevelUnknown, 250},
		{ts.SeverityLevelError, proto.SecuritySeverity_MEDIUM, ts.PrecisionLevelUnknown, 250 + 0},
		{ts.SeverityLevelError, proto.SecuritySeverity_CRITICAL, ts.PrecisionLevelVeryHigh, 350 + 90},
	}
	for _, test := range tests {
		a := ts.MagicWeight(test.severity, test.securitySeverity, test.precision)
		require.Equal(t, test.weight, a)
	}
}

func TestCombineExtensions(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	a := e.deliverAndStoreSARIF(testConfig{repositoryID: testRepoID, commitOid: "deadbeef"}, "../sarif/testdata/combineExtensions.sarif", nil)

	dbtest.RequireCount(t, 1, db.Model(&ts.Tool{}).Where("canonical_name = 'CodeQL'"))
	dbtest.RequireCount(t, 3, db.Model(&ts.ToolVersion{}))

	analysis := &ts.Analysis{ID: a.ID, RepositoryID: testRepoID, ArchivalDataUrl: a.ArchivalDataUrl}
	err := e.archiveService.Unarchive(e.ctx, analysis)
	require.NoError(t, err)

	require.Len(t, analysis.ToolVersions, 3)

	names := make([]string, 0, len(analysis.ToolVersions))

	for _, tv := range analysis.ToolVersions {
		names = append(names, tv.Name.String())
	}

	require.ElementsMatch(t, names, []string{"query-pack1", "query-pack2", "CodeQL"})
}

func TestCodeQLRename_Regression(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// always add the analysis to the new tool, even though the sarif contains the old name
	e.deliverSARIF(testConfig{repositoryID: testRepoID, commitOid: "deadbeef"}, "../sarif/testdata/codeql_command_line_toolchain.sarif")
	e.deliverSARIF(testConfig{repositoryID: testRepoID, commitOid: "deadbeef"}, "../sarif/testdata/codeql.sarif")

	dbtest.RequireCount(t, 1, db.Model(&ts.Tool{}).Where("canonical_name = 'CodeQL'"))
	dbtest.RequireCount(t, 0, db.Model(&ts.Tool{}).Where("canonical_name = 'CodeQL command-line toolchain'"))
	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Select("COUNT(DISTINCT ts_analyses.tool_id)"))
}

func TestUnsoftDeleteAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	main := testConfig{ref: "main"}
	e.deliverAlerts(main, testAlert("X", "P1"))

	filter := ts.AlertFilter{
		Numbers: []uint32{1},
	}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID: testRepoID,
	}
	opts := &ts.FindOptions{
		Preloads:   []string{"Rule", "Rule.Tags", "Rule.Tool"},
		Pagination: &ts.Pagination{Limit: 1},
	}
	_, err := as.Alerts(ctx, testRepoID, filter, analysisFilter, opts)
	require.NoError(t, err)

	// Delete
	require.NoError(t, db.Model(&ts.LogicalAlert{}).Where("repository_id = ? AND number = ?", testRepoID, 1).Update("soft_deleted_at", sqltime.Time{Time: time.Now()}).Error)

	// Alert is not there
	a, err := as.Alerts(ctx, testRepoID, filter, analysisFilter, opts)
	require.NoError(t, err)
	require.Len(t, a, 0)

	// New Delivery
	e.deliverAlerts(main, testAlert("X", "P1"))

	a, err = as.Alerts(ctx, testRepoID, filter, analysisFilter, opts)
	require.NoError(t, err)
	require.Len(t, a, 1)

	require.Nil(t, a[0].SoftDeletedAt)
	require.Nil(t, a[0].SoftDeleterID)
}

func TestAlertPreloadsTool(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx
	repoID := testRepoID

	codeQL := e.requireToolByName(repoID, "CodeQL")
	r := &ts.Rule{
		Name:   "My rule",
		ToolID: codeQL.ID,
	}
	dbtest.RequireCreate(t, db, &r)

	l := &ts.LogicalAlert{
		RepositoryID:          repoID,
		Number:                123,
		StableAlertIdentifier: newStableID(),
		RuleID:                r.ID,
	}
	dbtest.RequireCreate(t, db, &l)

	a := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		MostRecent:         true,
		AnalysisComplete:   true,
		ToolID:             codeQL.ID,
		Ref:                []byte("refs/heads/master"),
	}
	dbtest.RequireCreate(t, db, &a)

	p := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            a.ID,
		RuleID:                l.RuleID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p)

	analysisFilter := ts.AnalysisFilter{
		RepositoryID: repoID,
		ToolIDs:      []ts.ToolID{codeQL.ID},
	}

	options := &ts.FindOptions{
		Pagination: &ts.Pagination{Limit: 25},
		Preloads:   []string{"Rule.Tool"},
		SortBy:     alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING),
	}

	logicalAlerts, err := as.Alerts(ctx, repoID, ts.AlertFilter{}, analysisFilter, options)
	require.NoError(t, err)
	require.Len(t, logicalAlerts, 1)
	require.NotNil(t, logicalAlerts[0].Rule.Tool)

}

func TestPhysicalAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx
	repoID := testRepoID

	filter := ts.AlertFilter{
		Numbers: []uint32{123},
	}

	// alert doesn't exist yet
	physicalAlerts, err := as.PhysicalAlerts(ctx, repoID, filter, repoAnalysisFilter, &ts.FindOptions{})
	require.NoError(t, err)
	require.Empty(t, physicalAlerts)

	count, err := as.CountPhysicalAlerts(ctx, repoID, filter, repoAnalysisFilter)
	require.NoError(t, err)
	require.Equal(t, uint64(0), count)

	l := &ts.LogicalAlert{
		ID:                    1,
		RepositoryID:          repoID,
		Number:                123,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, &l)
	a := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		MostRecent:         true,
		AnalysisComplete:   true,
		Ref:                []byte("refs/heads/master"),
	}
	dbtest.RequireCreate(t, db, &a)
	oldAnalysis := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		MostRecent:         false,
		Ref:                []byte("refs/heads/master"),
	}
	dbtest.RequireCreate(t, db, &oldAnalysis)
	expectedPA := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            a.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &expectedPA)
	oldPA := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            oldAnalysis.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &oldPA)
	otherPA := &ts.PhysicalAlert{
		LogicalAlertID:        44,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: newStableID(),
		AnalysisID:            a.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &otherPA)

	filter.IDs = []ts.LogicalAlertID{l.ID}
	physicalAlerts, err = as.PhysicalAlerts(ctx, repoID, filter, repoAnalysisFilter, &ts.FindOptions{})
	require.NoError(t, err)
	require.Equal(t, 1, len(physicalAlerts))
	require.EqualValues(t, expectedPA.ID, physicalAlerts[0].ID)

	count, err = as.CountPhysicalAlerts(ctx, repoID, filter, repoAnalysisFilter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), count)

	// test with multiple logical alerts
	l2 := &ts.LogicalAlert{
		ID:                    2,
		RepositoryID:          repoID,
		Number:                124,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, &l2)
	expectedPA2 := &ts.PhysicalAlert{
		LogicalAlertID:        l2.ID,
		RepositoryID:          l2.RepositoryID,
		StableAlertIdentifier: l2.StableAlertIdentifier,
		AnalysisID:            a.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &expectedPA2)
	filter.IDs = []ts.LogicalAlertID{l.ID, l2.ID}
	physicalAlerts, err = as.PhysicalAlerts(ctx, repoID, filter, repoAnalysisFilter, &ts.FindOptions{})
	require.NoError(t, err)
	require.Equal(t, 2, len(physicalAlerts))
	require.EqualValues(t, expectedPA2.ID, physicalAlerts[0].ID)
	require.EqualValues(t, expectedPA.ID, physicalAlerts[1].ID)

	count, err = as.CountPhysicalAlerts(ctx, repoID, filter, repoAnalysisFilter)
	require.NoError(t, err)
	require.Equal(t, uint64(2), count)
}

func TestPhysicalAlertsRefsFilter(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx
	repoID := testRepoID

	l := &ts.LogicalAlert{
		RepositoryID:          repoID,
		Number:                123,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, &l)
	a := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		Ref:                []byte("main"),
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a)
	otherAnalysis := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		Ref:                []byte("not-main"),
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &otherAnalysis)
	expectedPA := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            a.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &expectedPA)
	otherPA := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            otherAnalysis.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &otherPA)

	filter := ts.AlertFilter{
		Numbers: []uint32{l.Number},
	}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID: repoID,
		Refs:         [][]byte{[]byte("main")},
	}
	physicalAlerts, err := as.PhysicalAlerts(ctx, repoID, filter, analysisFilter, &ts.FindOptions{
		Preloads: []string{"Analysis"},
	})
	require.NoError(t, err)
	require.Equal(t, 1, len(physicalAlerts))
	require.EqualValues(t, []byte("main"), physicalAlerts[0].Analysis.Ref)

	count, err := as.CountPhysicalAlerts(ctx, repoID, filter, analysisFilter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), count)
}

func TestPhysicalAlertsPagination(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx
	repoID := testRepoID

	l := &ts.LogicalAlert{
		RepositoryID:          repoID,
		Number:                123,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, &l)
	a1 := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		Ref:                []byte("a"),
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a1)
	a2 := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		Ref:                []byte("b"),
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a2)
	p1 := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            a1.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	p1.CreatedAt = sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(t, db, &p1)
	p2 := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            a2.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	p2.CreatedAt = sqltime.Date(2016, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(t, db, &p2)

	filter := ts.AlertFilter{Numbers: []uint32{l.Number}}
	physicalAlerts, err := as.PhysicalAlerts(ctx, repoID, filter, repoAnalysisFilter, &ts.FindOptions{
		Pagination: &ts.Pagination{Limit: 1},
	})
	require.NoError(t, err)
	require.Equal(t, 1, len(physicalAlerts))
	require.EqualValues(t, p1.ID, physicalAlerts[0].ID)

	physicalAlerts, err = as.PhysicalAlerts(ctx, repoID, filter, repoAnalysisFilter, &ts.FindOptions{
		Pagination: &ts.Pagination{Limit: 1, Offset: 1},
	})
	require.NoError(t, err)
	require.Equal(t, 1, len(physicalAlerts))
	require.EqualValues(t, p2.ID, physicalAlerts[0].ID)
}

func TestPhysicalAlertPreloading(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	l := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                123,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, &l)
	codeQL := ts.Tool{
		ID:            1519,
		GUID:          "guid",
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, &codeQL)
	a := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		Ref:                []byte("main"),
		MostRecent:         true,
		AnalysisComplete:   true,
		Tool:               &codeQL,
	}
	dbtest.RequireCreate(t, db, &a)
	expectedPA := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            a.ID,
		LastSeenAnalysisID:    &a.ID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &expectedPA)

	filter := ts.AlertFilter{
		Numbers: []uint32{l.Number},
	}

	physicalAlerts, err := as.PhysicalAlerts(ctx, testRepoID, filter, repoAnalysisFilter, &ts.FindOptions{
		Preloads: []string{"LastSeenAnalysis"},
	})
	require.NoError(t, err)
	require.Equal(t, 1, len(physicalAlerts))
	require.EqualValues(t, a.ID, physicalAlerts[0].LastSeenAnalysis.ID)

	physicalAlerts, err = as.PhysicalAlerts(ctx, testRepoID, filter, repoAnalysisFilter, &ts.FindOptions{
		Preloads: []string{"Analysis.Tool"},
	})
	require.NoError(t, err)
	require.Equal(t, 1, len(physicalAlerts))
	require.EqualValues(t, codeQL.CanonicalName, physicalAlerts[0].Analysis.Tool.CanonicalName)
}

func TestAlertsWithDifferentRules(t *testing.T) {
	// The system allows us to have physical alerts with rule_ids that are different
	// to the rule_id of the logical alert they belong to.
	// This occurs if the most recent alert had different rule metadata to previous ones (e.g: CodeQL rule help was
	// updated).
	// This test verifies that filtering by rule correctly retrieves the alerts in these cases.
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	as := e.as
	ctx := e.ctx

	l := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		Number:                123,
		StableAlertIdentifier: newStableID(),
		RuleID:                1,
		SarifIdentifier:       "rule-1",
	}
	dbtest.RequireCreate(t, db, &l)
	codeQL := ts.Tool{
		ID:            1519,
		GUID:          "guid",
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, &codeQL)
	a := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		Ref:                []byte("main"),
		MostRecent:         true,
		AnalysisComplete:   true,
		Tool:               &codeQL,
	}
	dbtest.RequireCreate(t, db, &a)
	expectedPA := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            a.ID,
		RuleID:                2,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &expectedPA)

	filter := ts.AlertFilter{
		IDs:              []ts.LogicalAlertID{l.ID},
		SarifIdentifiers: []string{l.SarifIdentifier},
	}

	alerts, err := as.Alerts(ctx, testRepoID, filter, repoAnalysisFilter, &ts.FindOptions{SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Equal(t, 1, len(alerts))
}

func TestAutomationIDCategory(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	main := testConfig{ref: "main"}

	// Single run - no custom category
	a := e.deliverSARIF(main, "../sarif/testdata/example.sarif")
	require.EqualValues(t, a.AnalysisKey, a.Category)

	// Single run - one custom category
	a = e.deliverSARIF(main, "../sarif/testdata/automation_id.sarif")
	require.EqualValues(t, "my-category", a.Category)

	// Multiple runs - consistent categories
	a = e.deliverSARIF(main, "../sarif/testdata/automation_id_multiple_consistent.sarif")
	require.EqualValues(t, "javascript/Linux", a.Category)

	// Multiple runs - one run missing a category
	as := e.deliverSARIFMultiple(main, "../sarif/testdata/automation_id_multiple_absent.sarif")
	sort.Slice(as, func(i, j int) bool { return as[i].Category < as[j].Category })
	require.Len(t, as, 2)
	require.EqualValues(t, as[0].AnalysisKey, as[0].Category)
	require.EqualValues(t, "javascript/Linux", as[1].Category)

	// Two runs - two categories
	as = e.deliverSARIFMultiple(main, "../sarif/testdata/automation_id_multiple_inconsistent.sarif")
	sort.Slice(as, func(i, j int) bool { return as[i].Category < as[j].Category })
	require.Len(t, as, 2)
	require.EqualValues(t, "javascript/Linux", as[0].Category)
	require.EqualValues(t, "javascript/Unix", as[1].Category)

	// Three runs - two categories
	as = e.deliverSARIFMultiple(main, "../sarif/testdata/automation_id_three_runs_two_matching.sarif")
	sort.Slice(as, func(i, j int) bool { return as[i].Category < as[j].Category })
	require.Len(t, as, 2)
	require.EqualValues(t, "javascript/Linux", as[0].Category)
	require.EqualValues(t, "javascript/Unix", as[1].Category)
}

func TestCountWithTools(t *testing.T) {
	db := dbtest.RequireConnection(t)

	globalTool := &ts.Tool{
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, globalTool)

	e := requireTestEnv(t, db)
	a1 := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Tool:               globalTool,
		ToolID:             globalTool.ID,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          "aaaa",
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a1)
	a2 := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Tool:               globalTool,
		ToolID:             globalTool.ID,
		Ref:                []byte("refs/heads/branch"),
		CommitOid:          "bbbb",
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a2)
	l1 := &ts.LogicalAlert{
		RepositoryID:          a1.RepositoryID,
		RuleID:                1,
		Number:                1,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, &l1)

	l2 := &ts.LogicalAlert{
		RepositoryID:          a2.RepositoryID,
		RuleID:                2,
		Number:                2,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, &l2)
	p1 := ts.PhysicalAlert{
		RuleID:                l1.RuleID,
		AnalysisID:            a1.ID,
		RepositoryID:          a1.RepositoryID,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: l1.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelWarning,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p1)

	p2 := ts.PhysicalAlert{
		RuleID:                l2.RuleID,
		AnalysisID:            a2.ID,
		RepositoryID:          a2.RepositoryID,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: l2.StableAlertIdentifier,
		SeverityLevel:         ts.SeverityLevelError,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, &p2)

	counts, err := e.as.CountByTool(e.ctx, testRepoID, ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN}, ts.AnalysisFilter{RepositoryID: testRepoID, ToolIDs: e.toolIDs()})
	require.NoError(t, err)
	require.Len(t, counts, 1)
	require.Contains(t, counts, ts.ToToolName("CodeQL"))
	require.Equal(t, uint64(2), counts["CodeQL"])
}

// TestAlertIsFixed checks the logical alert IsFixed permutations of two analyses
func TestAlertIsFixed(t *testing.T) {
	// a map of logical alert numbers to test configurations
	testCases := []map[uint32]struct {
		// what we expect the fixed status of the logical alert to be
		expected bool
		// what the fixed status of the physical alerts for analysis 1 and 2 should be
		setup [2]bool
	}{
		{ // If the physical alerts agree, the logical alert has the same fixed status
			1: {true, [2]bool{true, true}},
			2: {false, [2]bool{false, false}},
		},
		{ // Does not matter how the physical alerts disagree, the logical alert is not fixed.
			1: {false, [2]bool{true, false}},
			2: {false, [2]bool{false, true}},
		},
	}

	options := &ts.FindOptions{Preloads: []string{"PhysicalAlerts"}, Pagination: &ts.Pagination{Limit: 25}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)}

	for n, testCase := range testCases {
		t.Run(fmt.Sprintf("fixed alert combinations %d", n+1), func(t *testing.T) {
			db := dbtest.RequireConnection(t)
			e := requireTestEnv(t, db)

			la1 := &ts.LogicalAlert{
				RepositoryID:          testRepoID,
				Number:                1,
				StableAlertIdentifier: newStableID(),
			}
			dbtest.RequireCreate(t, db, la1)
			la2 := &ts.LogicalAlert{
				RepositoryID:          testRepoID,
				Number:                2,
				StableAlertIdentifier: newStableID(),
			}
			dbtest.RequireCreate(t, db, la2)

			a1 := &ts.Analysis{
				RepositoryID:       testRepoID,
				SourceRepositoryID: testRepoID,
				Ref:                []byte("a"),
				MostRecent:         true,
				AnalysisComplete:   true,
			}
			dbtest.RequireCreate(t, db, a1)

			a2 := &ts.Analysis{
				RepositoryID:       testRepoID,
				SourceRepositoryID: testRepoID,
				Ref:                []byte("b"),
				MostRecent:         true,
				AnalysisComplete:   true,
			}
			dbtest.RequireCreate(t, db, a2)

			analyses := []*ts.Analysis{a1, a2}
			a100 := ts.AnalysisID(100)

			for _, la := range []*ts.LogicalAlert{la1, la2} {
				for n, isFixed := range testCase[la.Number].setup {
					var fixedID *ts.AnalysisID

					if isFixed {
						fixedID = &a100
					}

					dbtest.RequireCreate(t, db, &ts.PhysicalAlert{
						LogicalAlertID:        la.ID,
						RepositoryID:          la.RepositoryID,
						StableAlertIdentifier: la.StableAlertIdentifier,
						AnalysisID:            analyses[n].ID,
						LastSeenAnalysisID:    fixedID,
						LastStateChangeAt:     sqltime.Now(),
					})
				}

			}

			las, err := e.as.Alerts(e.ctx, testRepoID, nofilter, repoAnalysisFilter, options)
			require.NoError(t, err)
			require.Len(t, las, len(testCase))

			for _, la := range las {
				require.Equal(t, testCase[la.Number].expected, *la.IsFixed)
			}
		})
	}

}

func TestLastFixDate_Nominal(t *testing.T) {
	// Test the computation of the fix date in the nominal case.
	// This is when, for the same category, we have a linear sequence of analysis:
	//   base <- fix <- mostRecent

	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that the last fix date is set correctly
	baseAnalysis := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Ref:                []byte("refs/heads/master"),
		CommitOid:          "aaaa",
	}

	// The alert we are aiming to fix
	la := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		RuleID:                1,
		Number:                1,
		StableAlertIdentifier: newStableID(),
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

	// We fix the alert in this analysis
	fixAnalysis1 := baseAnalysis
	fixAnalysis1.Category = "1"
	fixAnalysis1.MostRecent = false
	fixAnalysis1.AnalysisComplete = true
	fixAnalysis1.BaselineID = &baselineID1
	dbtest.RequireCreate(t, db, &fixAnalysis1)

	// Finally we add a most recent analysis for category 1
	mostRecentAnalysis1 := baseAnalysis
	mostRecentAnalysis1.Category = "1"
	mostRecentAnalysis1.MostRecent = true
	mostRecentAnalysis1.AnalysisComplete = true
	mostRecentAnalysis1.BaselineID = &fixAnalysis1.ID
	dbtest.RequireCreate(t, db, &mostRecentAnalysis1)

	// We follow the same structure for category 2
	// baseline -> fix -> most recent
	baselineID2 := ts.AnalysisID(9999)

	fixAnalysis2 := baseAnalysis
	fixAnalysis2.Category = "2"
	fixAnalysis2.MostRecent = false
	fixAnalysis2.AnalysisComplete = true
	fixAnalysis2.BaselineID = &baselineID2
	dbtest.RequireCreate(t, db, &fixAnalysis2)

	mostRecentAnalysis2 := baseAnalysis
	mostRecentAnalysis2.Category = "2"
	mostRecentAnalysis2.MostRecent = true
	mostRecentAnalysis2.AnalysisComplete = true
	dbtest.RequireCreate(t, db, &mostRecentAnalysis2)

	// We create two physical alerts for the logical alert, one for each category
	p1 := basePAlert
	p1.AnalysisID = mostRecentAnalysis1.ID
	p1.LastSeenAnalysisID = &baselineID1
	p1.LastStateChangeAt = sqltime.Now()
	dbtest.RequireCreate(t, db, &p1)

	p2 := basePAlert
	p2.AnalysisID = mostRecentAnalysis2.ID
	p2.LastSeenAnalysisID = &baselineID2
	p2.LastStateChangeAt = sqltime.Now()
	dbtest.RequireCreate(t, db, &p2)

	opts := &ts.FindOptions{
		Preloads:   []string{"Rule", "Rule.Tags", "Rule.Tool"},
		Pagination: &ts.Pagination{Limit: 1},
	}
	// We expect the fix date to be the creation time for the 2nd fix analysis
	foundLAs, err := e.as.Alerts(e.ctx, testRepoID, nofilter, repoAnalysisFilter, opts)
	require.NoError(t, err)
	require.Len(t, foundLAs, 1)
	require.Equal(t, fixAnalysis2.CreatedAt, *foundLAs[0].LastObservedFixAt)
	require.Equal(t, fixAnalysis2.CreatedAt, *foundLAs[0].GetFixedAt())
	require.NotEqual(t, fixAnalysis1.CreatedAt, *foundLAs[0].LastObservedFixAt)
}

func TestLastFixDate_InvalidAnalyses(t *testing.T) {
	// Test the computation of the fix date in the case another analysis points to
	// the same baseline but it is not part of the "chain".
	// This can happen if the analysis:
	// * Failed processing
	// * Was deleted
	// * Was never complete
	//
	// Effectively, this creates a fork:
	//
	//   base <- fix <- mostRecent
	//        \ failed
	//        \ deleted
	//        \ incomplete
	//
	// To avoid behaviors that are due to ordering we will create "invalid" analyses
	// before AND after the "valid" one.

	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that the last fix date is set correctly
	baseAnalysis := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Ref:                []byte("refs/heads/master"),
		Category:           "1",
		CommitOid:          "aaaa",
		AnalysisComplete:   true,
	}

	// The alert we are aiming to fix
	la := &ts.LogicalAlert{
		RepositoryID:          testRepoID,
		RuleID:                1,
		Number:                1,
		StableAlertIdentifier: newStableID(),
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

	opts := &ts.FindOptions{
		Preloads:   []string{"Rule", "Rule.Tags", "Rule.Tool"},
		Pagination: &ts.Pagination{Limit: 1},
	}
	// We expect the fix date to be the creation time for the 2nd fix analysis
	foundLAs, err := e.as.Alerts(e.ctx, testRepoID, nofilter, repoAnalysisFilter, opts)
	require.NoError(t, err)
	require.Len(t, foundLAs, 1)
	require.Equal(t, fixAnalysis.CreatedAt, *foundLAs[0].LastObservedFixAt)
	require.Equal(t, fixAnalysis.CreatedAt, *foundLAs[0].GetFixedAt())
	require.NotEqual(t, failedAnalysisPre.CreatedAt, *foundLAs[0].LastObservedFixAt)
	require.NotEqual(t, failedAnalysisPost.CreatedAt, *foundLAs[0].LastObservedFixAt)
	require.NotEqual(t, deletedAnalysisPre.CreatedAt, *foundLAs[0].LastObservedFixAt)
	require.NotEqual(t, deletedAnalysisPost.CreatedAt, *foundLAs[0].LastObservedFixAt)
	require.NotEqual(t, incompleteAnalysisPre.CreatedAt, *foundLAs[0].LastObservedFixAt)
	require.NotEqual(t, incompleteAnalysisPost.CreatedAt, *foundLAs[0].LastObservedFixAt)
}

func TestGetWithCursor(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			SarifIdentifier: "query1",
			Number:          1,
			RuleID:          1,
			Weight:          10,
		},
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			SarifIdentifier: "query2",
			Number:          2,
			RuleID:          2,
			Weight:          20,
		},
		ts.LogicalAlert{
			RepositoryID:    testRepoID,
			SarifIdentifier: "query3",
			Number:          3,
			RuleID:          3,
			Weight:          30,
		},
	)

	// Test paging through the results using a cursor
	order := proto.AlertSortOrder_UPDATED_ASCENDING
	opts := ts.FindOptions{}

	// Initial page (page 1)
	opts.Pagination = &ts.Pagination{Limit: 1}
	page1, err := e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Len(t, page1.Results, 1)
	require.Equal(t, uint32(1), page1.Results[0].Number)
	require.Empty(t, page1.PrevCursor) //  No previous page

	// Next page is page 2
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page1.NextCursor, Descending: false}}
	page2, err := e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Len(t, page2.Results, 1)
	require.Equal(t, uint32(2), page2.Results[0].Number)

	// Prev page is page 1
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page2.PrevCursor, Descending: true}}
	result, err := e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Len(t, result.Results, 1)
	require.Equal(t, uint32(1), result.Results[0].Number)
	require.Equal(t, page1, result)

	// Next page is page 3
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page2.NextCursor}}
	page3, err := e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Len(t, page3.Results, 1)
	require.Equal(t, uint32(3), page3.Results[0].Number)
	require.Empty(t, page3.NextCursor) //  No more pages

	// Prev page is page 2
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page3.PrevCursor, Descending: true}}
	result, err = e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Equal(t, page2, result)

	// First page is page 1
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: "", Descending: false}}
	result, err = e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Equal(t, page1, result)

	// Last page is page 3
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: "", Descending: true}}
	result, err = e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Equal(t, page3, result)

	// Test pagination links for multiple results, use a new order for more coverage
	order = proto.AlertSortOrder_WEIGHT

	// Initial page should include alerts 3 and 2
	opts.Pagination = &ts.Pagination{Limit: 2}
	page1, err = e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Len(t, page1.Results, 2)
	require.Equal(t, uint32(3), page1.Results[0].Number)
	require.Equal(t, uint32(2), page1.Results[1].Number)
	require.Empty(t, page1.PrevCursor) //  No previous page

	// Next page should include alert 1
	opts.Pagination = &ts.Pagination{Limit: 2, Cursor: &ts.SerializedCursor{String: page1.NextCursor}}
	page2, err = e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Len(t, page2.Results, 1)
	require.Equal(t, uint32(1), page2.Results[0].Number)
	require.Empty(t, page2.NextCursor) //  No more pages

	// Previous page should be identical to page 1
	opts.Pagination = &ts.Pagination{Limit: 2, Cursor: &ts.SerializedCursor{String: page2.PrevCursor, Descending: true}}
	result, err = e.as.AlertsWithCursor(e.ctx, testRepoID, nofilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	// The following equality check applies to alert information and the prev/next cursors
	require.Equal(t, page1, result)

	// Test pagination with filters, new order again
	order = proto.AlertSortOrder_CREATED_ASCENDING
	alertFilter := ts.AlertFilter{
		SarifIdentifiers: []string{"query1", "query3"},
	}
	// Initial page should include alerts 1
	opts.Pagination = &ts.Pagination{Limit: 1}
	page1, err = e.as.AlertsWithCursor(e.ctx, testRepoID, alertFilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Len(t, page1.Results, 1)
	require.Equal(t, uint32(1), page1.Results[0].Number)
	require.Empty(t, page1.PrevCursor) //  No previous page

	// Next page is page 2 including only alert 3
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page1.NextCursor, Descending: false}}
	page2, err = e.as.AlertsWithCursor(e.ctx, testRepoID, alertFilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	require.Len(t, page2.Results, 1)
	require.Equal(t, uint32(3), page2.Results[0].Number)

	// Previous page should be identical to page 1
	opts.Pagination = &ts.Pagination{Limit: 2, Cursor: &ts.SerializedCursor{String: page2.PrevCursor, Descending: true}}
	result, err = e.as.AlertsWithCursor(e.ctx, testRepoID, alertFilter, repoAnalysisFilter, order, &opts)
	require.NoError(t, err)
	// The following equality check applies to alert information and the prev/next cursors
	require.Equal(t, page1, result)

}
