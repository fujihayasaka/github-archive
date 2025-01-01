package processor

import (
	"database/sql"
	"strconv"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/jobs"
	"github.com/stretchr/testify/require"
)

func TestInsightsProcessing(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	e.ctx = flipper.WithFeatureEnabled(e.ctx, "code_scanning_async_alert_indexing")

	// Just single repository
	defaultRef := "refs/heads/main"
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 1, OwnerID: 1, DefaultRef: []byte(defaultRef), SourceUpdatedAt: updatedAt, CodeScanningEnabled: true, Visibility: sql.NullString{String: "public", Valid: true}})
	main := testConfig{repositoryID: 1, ref: defaultRef}

	analysis := e.deliverSARIF(main, "../sarif/testdata/security-severity-small.sarif")
	var alert ts.PhysicalAlert
	require.NoError(e.t, db.First(&alert, "analysis_id = ?", analysis.ID).Error)

	// The Insights hydro events fired
	require.Len(e.t, e.publisher.insightBatches, 1)
	require.Len(e.t, e.publisher.insightBatches[0].EntitiesUpdated, 1)

	expectedInsightsAlert := map[string]string{
		"closed":                 "false",
		"id":                     strconv.FormatUint(uint64(alert.LogicalAlertID), 10),
		"present_on_default_ref": "true",
		"repository_id":          "1",
		"resolution":             "0",
		"rule_name":              "js/sql-injection",
		"rule_sarif_identifier":  "js/sql-injection",
		"severity":               "3",
		"tool_name":              "CodeQL",
		"number":                 "1",
		"has_autofix":            "false",
		"autofix_accepted":       "false",
	}

	actualInsightsAlert := stripTimestamps(e.publisher.insightBatches[0].EntitiesUpdated[0].Data)
	require.Equal(e.t, expectedInsightsAlert, actualInsightsAlert)

	// If we deliver the exact same alert then we should not get an event
	e.deliverSARIF(main, "../sarif/testdata/security-severity-small.sarif")

	require.Len(e.t, e.publisher.insightBatches, 1)
	require.Len(e.t, e.publisher.insightBatches[0].EntitiesUpdated, 1)

	// If we change the severity then we should deliver a new event, with updated severity
	e.deliverSARIF(main, "../sarif/testdata/security-severity-small2.sarif")

	require.Len(e.t, e.publisher.insightBatches, 2)
	require.Len(e.t, e.publisher.insightBatches[1].EntitiesUpdated, 1)

	expectedInsightsAlert["severity"] = "2"

	actualInsightsAlert = stripTimestamps(e.publisher.insightBatches[1].EntitiesUpdated[0].Data)
	require.Equal(e.t, expectedInsightsAlert, actualInsightsAlert)

	// If we fix the alert then it should also be delivered
	e.deliverSARIF(main, "../sarif/testdata/security-severity-empty.sarif")

	require.Len(e.t, e.publisher.insightBatches, 3)
	require.Len(e.t, e.publisher.insightBatches[2].EntitiesUpdated, 1)

	expectedInsightsAlert["closed"] = "true"
	actualInsightsAlert = stripTimestamps(e.publisher.insightBatches[2].EntitiesUpdated[0].Data)
	require.Equal(e.t, expectedInsightsAlert, actualInsightsAlert)
}

func TestInsightsNonDefaultBranchAnalysis(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Just single repository
	defaultRef := "refs/heads/main"
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 1, OwnerID: 1, DefaultRef: []byte(defaultRef), SourceUpdatedAt: updatedAt, CodeScanningEnabled: true, Visibility: sql.NullString{String: "public", Valid: true}})

	nonDefaultConfig := testConfig{repositoryID: 1, ref: "ref/heads/develop"}

	analysis := e.deliverSARIF(nonDefaultConfig, "../sarif/testdata/security-severity-small.sarif")
	var alert ts.PhysicalAlert
	require.NoError(e.t, db.First(&alert, "analysis_id = ?", analysis.ID).Error)

	// The Insights hydro events should not fire
	require.Len(e.t, e.publisher.insightBatches, 0)
}

func TestInsightsUpdateAlert(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Just single repository
	defaultRef := "refs/heads/main"
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 1, OwnerID: 1, DefaultRef: []byte(defaultRef), SourceUpdatedAt: updatedAt, CodeScanningEnabled: true, Visibility: sql.NullString{String: "public", Valid: true}})
	main := testConfig{repositoryID: 1, ref: defaultRef}

	// Get two alerts for testing.
	e.deliverSARIF(main, "../sarif/testdata/example.sarif")
	var alerts []*ts.LogicalAlert
	require.NoError(e.t, db.Find(&alerts).Error)
	require.Len(e.t, alerts, 2)

	// The Insights hydro events fired and both alerts are not closed
	require.Len(e.t, e.publisher.insightBatches, 1)
	require.Len(e.t, e.publisher.insightBatches[0].EntitiesUpdated, 2)
	require.Equal(e.t, "false", e.publisher.insightBatches[0].EntitiesUpdated[0].Data["closed"])
	require.Equal(e.t, "false", e.publisher.insightBatches[0].EntitiesUpdated[1].Data["closed"])

	// TODO: below we tie directly into ES for alert dismissal, it should be refactored to a common method.

	// Manually dismiss the first alert.
	err := e.as.ResolveLogicalAlerts(e.ctx, alerts[0:1], ts.AlertResolutionFalsePositive, ts.UserEID(1), "", sqltime.Now(), nil)
	require.NoError(e.t, err)
	// Refresh index and sync manual changes to ES
	require.NoError(e.t, e.es.Refresh(e.ctx, ts.Index_OrgLevel))
	resolveFields := map[string]interface{}{
		"resolved":    true,
		"resolution":  ts.AlertResolutionFalsePositive.String(),
		"resolver_id": "1",
		"resolved_at": sqltime.Now(),
		"updated_at":  sqltime.Now(),
	}
	require.NoError(e.t, indexAlertsStatusChangeTest(e, 1, []ts.LogicalAlertID{alerts[0].ID}, resolveFields))

	// The Insights hydro events fired
	require.Len(e.t, e.publisher.insightBatches, 2)
	require.Len(e.t, e.publisher.insightBatches[1].EntitiesUpdated, 1)

	expectedInsightsAlert := map[string]string{
		"closed":                 "true",
		"id":                     strconv.FormatUint(uint64(alerts[0].ID), 10),
		"present_on_default_ref": "true",
		"repository_id":          "1",
		"resolution":             "1",
		"rule_name":              "js/unused-local-variable",
		"rule_sarif_identifier":  "js/unused-local-variable",
		"severity":               "0",
		"tool_name":              "CodeQL",
		"number":                 "1",
		"has_autofix":            "false",
		"autofix_accepted":       "false",
	}

	actualInsightsAlert := stripTimestamps(e.publisher.insightBatches[1].EntitiesUpdated[0].Data)
	require.Equal(e.t, expectedInsightsAlert, actualInsightsAlert)

	// Bulk reopen both alerts
	err = e.as.ReopenLogicalAlerts(e.ctx, alerts, sqltime.Now())
	require.NoError(e.t, err)
	// Refresh index and sync manual changes to ES
	require.NoError(e.t, e.es.Refresh(e.ctx, ts.Index_OrgLevel))
	resolveFields = map[string]interface{}{
		"resolved":   false,
		"resolution": ts.AlertResolutionNone.String(),
		"updated_at": sqltime.Now(),
	}
	require.NoError(e.t, indexAlertsStatusChangeTest(e, 1, []ts.LogicalAlertID{alerts[0].ID, alerts[1].ID}, resolveFields))

	// The a single batch of two alerts fired
	require.Len(e.t, e.publisher.insightBatches, 3)
	require.Len(e.t, e.publisher.insightBatches[2].EntitiesUpdated, 2)
	// Both have closed set to false
	require.Equal(e.t, "false", e.publisher.insightBatches[2].EntitiesUpdated[0].Data["closed"])
	require.Equal(e.t, "false", e.publisher.insightBatches[2].EntitiesUpdated[1].Data["closed"])
}

// indexAlertsStatusChangeTest updates the alerts in ES and insights. It corresponds to the
// method `indexAlertsStatusChange“ in the resultResolver.
func indexAlertsStatusChangeTest(e *testEnv, repoID ts.RepositoryEID, ids []ts.LogicalAlertID, resolveFields map[string]interface{}) error {
	err := e.es.UpdateAlerts(e.ctx, repoID, ids, resolveFields)
	if err != nil {
		return err
	}

	indexJob := &jobs.AlertIndexing{
		Context:         "indexAlertsStatusChangeTest",
		RepositoryID:    repoID,
		LogicalAlertIDs: ids,
	}

	_, err = e.jobs.PerformLater(e.ctx, indexJob)
	if err != nil {
		return err
	}

	return nil
}

// stripTimestamps removes timestamps that are not available for this test.
func stripTimestamps(m map[string]string) map[string]string {
	m2 := map[string]string{}
	for k, v := range m {
		if k == "created_at" || k == "closed_at" || k == "source_time" || k == "updated_at" {
			continue
		}
		m2[k] = v
	}
	return m2
}
