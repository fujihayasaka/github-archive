package processor

import (
	"database/sql"
	"testing"
	"time"

	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/transforms"

	"github.com/SamuelTissot/sqltime"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/proto"
)

func TestOrgLevelIndexing(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	e.ctx = flipper.WithFeatureEnabled(e.ctx, "code_scanning_async_alert_indexing")

	// Load the repositories and analyses
	setUpScenario(e)

	// Require the index being correct for the default alerts
	requireCorrectCounts(e, e.es, false)
	requireCorrectAlerts(e, e.es)

	// Clear the ES index
	require.NoError(e.t, e.es.CreateIndex(e.ctx, ts.Index_OrgLevel, true))
	require.NoError(e.t, e.es.SetReadAlias(e.ctx, ts.Index_OrgLevel))

	// Index based on repos
	repo1 := &ts.Repository{}
	err := db.Model(ts.Repository{}).Where("repository_id = ?", 1).First(repo1).Error
	require.NoError(t, err)
	err = e.indexRepository(e.ctx, repo1)
	require.NoError(t, err)

	repo2 := &ts.Repository{}
	err = db.Model(ts.Repository{}).Where("repository_id = ?", 2).First(repo2).Error
	require.NoError(t, err)
	err = e.indexRepository(e.ctx, repo2)
	require.NoError(t, err)

	repo3 := &ts.Repository{}
	err = db.Where("repository_id = ?", 3).First(repo3).Error
	require.NoError(t, err)
	err = e.indexRepository(e.ctx, repo3)
	require.NoError(t, err)

	// Check results
	requireCorrectCounts(e, e.es, true)
	requireCorrectAlerts(e, e.es)
	requireCorrectTools(e, e.es)
	requireCorrectRepos(e, e.es)
	requireCorrectTags(e, e.es)
}

// setupScenario sets up a test scenario with several alerts in different states
func setUpScenario(e *testEnv) {

	// Four repositories
	defaultRef := []byte("refs/heads/main")
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 1, OwnerID: 1, DefaultRef: defaultRef, SourceUpdatedAt: updatedAt, CodeScanningEnabled: true, Visibility: sql.NullString{String: "public", Valid: true}})
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 2, OwnerID: 1, DefaultRef: defaultRef, SourceUpdatedAt: updatedAt, CodeScanningEnabled: true, Visibility: sql.NullString{String: "private", Valid: true}})
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 3, OwnerID: 2, DefaultRef: defaultRef, SourceUpdatedAt: updatedAt, CodeScanningEnabled: true})
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 4, OwnerID: 2, DefaultRef: defaultRef, SourceUpdatedAt: updatedAt, CodeScanningEnabled: true})

	// We want 6 different logical alert states
	// 1. alert with single non-fixed physical alert
	// 2. alert with single fixed physical alert
	// 3. alert with two non-fixed physical alerts
	// 4. alert with one fixed and one non-fixed physical alerts
	// 5. alert with two fixed physical alerts
	// 6. alert without physical alerts in the specified configuration

	// We consider three different configurations
	main1 := testConfig{repositoryID: 1, ref: "refs/heads/main", analysisKey: "1", tool: "foo"}
	main2 := testConfig{repositoryID: 1, ref: "refs/heads/main", analysisKey: "2", tool: "bar"}
	develop := testConfig{repositoryID: 1, ref: "refs/heads/develop", tool: "foo"}

	// Set up main1 config
	e.deliverAlerts(main1, testAlert("1", "P1"), testAlert("2", "P2"), testAlert("3", "P3"), testAlert("4", "P4"), testAlert("5", "P5"))
	// 2 is fixed on main1, 5 is fixed on main1
	e.deliverAlerts(main1, testAlert("1", "P10"), testAlert("3", "P11"), testAlert("4", "P12"))
	// Perform an identical delivery on main1 to ensure that is ok
	e.deliverAlerts(main1, testAlert("1", "P17"), testAlert("3", "P18"), testAlert("4", "P19"))

	// Set main2 config
	e.deliverAlerts(main2, testAlert("3", "P6"), testAlert("4", "P7"), testAlert("5", "P8"))
	// 4 is fixed on main2, 5 is fixed on main2
	e.deliverAlerts(main2, testAlert("3", "P13"))

	// Set up develop branch
	// It contains an alert also on main, and a fresh alert
	e.deliverAlerts(develop, testAlert("1", "P20"), testAlert("6", "P9"))

	// We also want to test having alerts on other repositories
	mainRepo2 := testConfig{repositoryID: 2, ref: "refs/heads/main", tool: "foo"}
	mainRepo3 := testConfig{repositoryID: 3, ref: "refs/heads/main", tool: "foo"}
	e.deliverAlerts(mainRepo2, testAlert("R2", "P14"), testAlert("R22", "P15"))
	e.deliverAlerts(mainRepo3, testAlert("R3", "P16"))

	// One alert in repo 2 is manually resolved and the other is manually deleted
	var alerts []*ts.LogicalAlert
	err := e.db.Find(&alerts, "repository_id = 2").Error
	require.NoError(e.t, err)
	resolveTime := sqltime.Now()
	deleteTime := sqltime.Now()
	err = e.as.ResolveLogicalAlerts(e.ctx, alerts[0:1], ts.AlertResolutionFalsePositive, ts.UserEID(1), "", resolveTime)
	require.NoError(e.t, err)
	require.NoError(e.t, e.db.Model(&ts.LogicalAlert{}).Where("repository_id = ? AND number = ?", 2, alerts[1].Number).Update("soft_deleted_at", deleteTime).Error)

	// Refresh index and sync manual changes to ES
	require.NoError(e.t, e.es.Refresh(e.ctx, ts.Index_OrgLevel))
	resolveFields := map[string]interface{}{
		"resolved":    true,
		"resolution":  ts.AlertResolutionFalsePositive.String(),
		"resolver_id": "1",
		"resolved_at": resolveTime,
		"updated_at":  resolveTime,
	}
	require.NoError(e.t, e.es.UpdateAlerts(e.ctx, 1, []ts.LogicalAlertID{alerts[0].ID}, resolveFields))
	deleteFields := map[string]interface{}{
		"deleted":    true,
		"updated_at": deleteTime,
	}
	require.NoError(e.t, e.es.UpdateAlerts(e.ctx, 1, []ts.LogicalAlertID{alerts[1].ID}, deleteFields))

	// Lastly we also test empty deliveries
	mainRepo4 := testConfig{repositoryID: 4, ref: "refs/heads/main", tool: "foo"}
	e.deliverAlerts(mainRepo4)

	// Perform a GC to ensure collected alerts are handled
	e.performGC(ts.CleaningTypeAnalysisAssociations)
}

func requireCorrectCounts(e *testEnv, es *elasticsearch.Service, allDocs bool) {
	// Refresh index
	require.NoError(e.t, es.Refresh(e.ctx, ts.Index_OrgLevel))
	// All logical alerts are not indexed by analysis processing
	// only by the indexer jobs.
	if allDocs {
		docs, err := es.CountAllDocuments(e.ctx, ts.Index_OrgLevel)
		require.NoError(e.t, err)
		// 5 alerts on default for repo1 + 1 on non default + 2 for repo2 + 1 for repo3
		require.Equal(e.t, int64(9), docs)
	}

	allCount, err := es.CountOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{})
	require.NoError(e.t, err)
	// 5 alerts on default for repo1 + 1 for repo2 + 1 for repo3
	require.Equal(e.t, int64(7), allCount)

	multiOrgCount, err := es.CountOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1, 2}})
	require.NoError(e.t, err)
	// 5 alerts on default for repo1 + 1 for repo2 + 1 for repo3
	require.Equal(e.t, int64(7), multiOrgCount)

	totalCountOrg1, err := es.CountOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}})
	require.NoError(e.t, err)
	// 5 alerts on default for repo1 + 1 for repo2
	require.Equal(e.t, int64(6), totalCountOrg1)

	totalCountOrg2, err := es.CountOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{2}})
	require.NoError(e.t, err)
	// 1 for repo3
	require.Equal(e.t, int64(1), totalCountOrg2)

	openCount, err := es.CountOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN})
	require.NoError(e.t, err)
	// 3 open alerts for repo1
	require.Equal(e.t, int64(3), openCount)

	closedCount, err := es.CountOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED})
	require.NoError(e.t, err)
	// 2 fixed alerts for repo1 + 1 closed alert for repo2
	require.Equal(e.t, int64(3), closedCount)

	fixedCount, err := es.CountOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED})
	require.NoError(e.t, err)
	// 2 fixed alerts for repo1
	require.Equal(e.t, int64(2), fixedCount)

	requireCorrectCountsByRepositoryID(e, es)
}

func requireCorrectCountsByRepositoryID(e *testEnv, es *elasticsearch.Service) {
	// Refresh index
	require.NoError(e.t, es.Refresh(e.ctx, ts.Index_OrgLevel))

	counts, allCount, err := es.CountOrgAlertsByRepositoryID(e.ctx, &ts.SearchByOrgsFilter{})
	require.NoError(e.t, err)
	// 5 alerts on default for repo1 + 1 for repo2 + 1 for repo3
	require.Equal(e.t, int64(7), allCount)
	require.Equal(e.t, map[ts.RepositoryEID]int64{1: 5, 2: 1, 3: 1}, counts)

	counts, multiOrgCount, err := es.CountOrgAlertsByRepositoryID(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1, 2}})
	require.NoError(e.t, err)
	// 5 alerts on default for repo1 + 1 for repo2 + 1 for repo3
	require.Equal(e.t, int64(7), multiOrgCount)
	require.Equal(e.t, map[ts.RepositoryEID]int64{1: 5, 2: 1, 3: 1}, counts)

	counts, totalCountOrg1, err := es.CountOrgAlertsByRepositoryID(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}})
	require.NoError(e.t, err)
	// 5 alerts on default for repo1 + 1 for repo2
	require.Equal(e.t, int64(6), totalCountOrg1)
	require.Equal(e.t, map[ts.RepositoryEID]int64{1: 5, 2: 1}, counts)

	counts, totalCountOrg2, err := es.CountOrgAlertsByRepositoryID(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{2}})
	require.NoError(e.t, err)
	// 1 for repo3
	require.Equal(e.t, int64(1), totalCountOrg2)
	require.Equal(e.t, map[ts.RepositoryEID]int64{3: 1}, counts)

	counts, openCount, err := es.CountOrgAlertsByRepositoryID(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN})
	require.NoError(e.t, err)
	// 3 open alerts for repo1
	require.Equal(e.t, int64(3), openCount)
	require.Equal(e.t, map[ts.RepositoryEID]int64{1: 3}, counts)

	counts, closedCount, err := es.CountOrgAlertsByRepositoryID(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED})
	require.NoError(e.t, err)
	// 2 fixed alerts for repo1 + 1 closed alert for repo2
	require.Equal(e.t, int64(3), closedCount)
	require.Equal(e.t, map[ts.RepositoryEID]int64{1: 2, 2: 1}, counts)

	counts, fixedCount, err := es.CountOrgAlertsByRepositoryID(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED})
	require.NoError(e.t, err)
	// 2 fixed alerts for repo1
	require.Equal(e.t, int64(2), fixedCount)
	require.Equal(e.t, map[ts.RepositoryEID]int64{1: 2}, counts)
}

func requireCorrectAlerts(e *testEnv, es *elasticsearch.Service) {
	// We only assert non-filtered results and rely on the count test to assert the right filters
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)
	result, err := es.SearchOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{}, ts.Pagination{Limit: 10}, s)
	require.NoError(e.t, err)
	require.Equal(e.t, 7, len(result.AlertKeys))

	zeroTime := sqltime.Time{}

	docsWithZeroTimeUpdatedAt := transforms.Filter(result.Documents, func(document ts.SearchDocument) bool {
		updatedAt := *document.UpdatedAt
		return updatedAt.Equal(zeroTime.Time)
	})

	require.Empty(e.t, docsWithZeroTimeUpdatedAt)

	logicalAlerts, err := e.as.GetAlertsByKeys(e.ctx, result.AlertKeys)
	require.NoError(e.t, err)

	// Only alerts on default ref should be returned
	refs := []string{"refs/heads/main"}
	expected := []testAlertT{
		testAlert("1", "P17"), testAlert("2", "P2"), testAlert("3", "P13"), testAlert("4", "P7"), testAlert("5", "P8"), // repo 1
		testAlert("R2", "P14"), // repo 2
		testAlert("R3", "P16"), // repo 3
	}
	openIndexes := []int{0, 2, 3}
	fixedIndexes := []int{1, 4}

	e.requireAlerts(refs, expected, logicalAlerts)

	// Check that fixed alerts are returned as fixed and open as open
	for _, i := range openIndexes {
		l := logicalAlerts[i]
		require.False(e.t, *l.IsFixed, "Alert "+l.PhysicalAlerts[0].FilePath+" is not open")
		require.Nil(e.t, l.GetFixedAt(), "Alert "+l.PhysicalAlerts[0].FilePath+" has a fixed at date")
	}
	for _, i := range fixedIndexes {
		l := logicalAlerts[i]
		require.True(e.t, *l.IsFixed, "Alert "+l.PhysicalAlerts[0].FilePath+" is not fixed")
		require.NotNil(e.t, l.GetFixedAt(), "Alert "+l.PhysicalAlerts[0].FilePath+" does not have a fixed at date")
	}
	// Check that LastStateChangeAt in the logical alerts matches the `updated_at` field in the documents
	for i, l := range logicalAlerts {
		doc := result.Documents[i]
		require.NotNil(e.t, doc.UpdatedAt)
		require.NotNil(e.t, l.LastStateChangeAt)
		require.Equal(e.t, *l.LastStateChangeAt, *doc.UpdatedAt)
	}
}

func requireCorrectTools(e *testEnv, es *elasticsearch.Service) {

	// org with ID 1 has two tools across all repos
	tools, err := es.SearchOrgToolNames(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}})
	require.NoError(e.t, err)
	require.Equal(e.t, 2, len(tools))

	// restricting to just repoId 2 in org 1 should give us a single tool
	tools, err = es.SearchOrgToolNames(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, RepositoryIDs: []ts.RepositoryEID{2}})
	require.NoError(e.t, err)
	require.Equal(e.t, 1, len(tools))

	// org with ID 2 only has a single tool across all repos
	tools, err = es.SearchOrgToolNames(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{2}})
	require.NoError(e.t, err)
	require.Equal(e.t, 1, len(tools))

	// orgs 1 and 2 together have two tools across all repos
	tools, err = es.SearchOrgToolNames(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1, 2}})
	require.NoError(e.t, err)
	require.Equal(e.t, 2, len(tools))
}

func requireCorrectRepos(e *testEnv, es *elasticsearch.Service) {
	// org with ID 1 has two repos with alerts
	repositoryIDs, err := es.SearchOrgRepositoryIDs(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}})
	require.NoError(e.t, err)
	require.Equal(e.t, 2, len(repositoryIDs))

	// org with ID 2 has only has a single repo with alerts
	repositoryIDs, err = es.SearchOrgRepositoryIDs(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{2}})
	require.NoError(e.t, err)
	require.Equal(e.t, 1, len(repositoryIDs))

	// orgs 1 and 2 together have three repos with alerts
	repositoryIDs, err = es.SearchOrgRepositoryIDs(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1, 2}})
	require.NoError(e.t, err)
	require.Equal(e.t, 3, len(repositoryIDs))

	// org with ID 1 has only has a single repo that is private
	repositoryIDs, err = es.SearchOrgRepositoryIDs(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, RepositoryVisibilities: []string{"private"}})
	require.NoError(e.t, err)
	require.Equal(e.t, 1, len(repositoryIDs))
	require.Equal(e.t, uint64(2), repositoryIDs[0].RepositoryId)

	// org with ID 1 has only has a a private and a public repo
	repositoryIDs, err = es.SearchOrgRepositoryIDs(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, RepositoryVisibilities: []string{"private", "public"}})
	require.NoError(e.t, err)
	require.Equal(e.t, 2, len(repositoryIDs))
	require.Equal(e.t, uint64(1), repositoryIDs[0].RepositoryId)
	require.Equal(e.t, uint64(2), repositoryIDs[1].RepositoryId)
}

func requireCorrectTags(e *testEnv, es *elasticsearch.Service) {
	// org with ID 1 has six tags across all repos
	ruleTags, err := es.SearchOrgRuleTags(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}})
	require.NoError(e.t, err)
	require.Equal(e.t, 6, len(ruleTags))

	// restricting to just repoId 2 in org 1 should give us a single tag
	ruleTags, err = es.SearchOrgRuleTags(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, RepositoryIDs: []ts.RepositoryEID{2}})
	require.NoError(e.t, err)
	require.Equal(e.t, 1, len(ruleTags))

	// org with ID 2 only has a single tag across all repos
	ruleTags, err = es.SearchOrgRuleTags(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{2}})
	require.NoError(e.t, err)
	require.Equal(e.t, 1, len(ruleTags))

	// orgs 1 and 2 together have seven tags across all repos
	ruleTags, err = es.SearchOrgRuleTags(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1, 2}})
	require.NoError(e.t, err)
	require.Equal(e.t, 7, len(ruleTags))
}

func TestSeverity(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	defaultRef := []byte("refs/heads/main")
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 1, OwnerID: 1, DefaultRef: defaultRef, SourceUpdatedAt: updatedAt, CodeScanningEnabled: true})

	main := testConfig{repositoryID: 1, ref: "refs/heads/main"}
	e.deliverSARIF(main, "../sarif/testdata/security-severity.sarif")

	// Refresh index
	require.NoError(e.t, e.es.Refresh(e.ctx, ts.Index_OrgLevel))

	// 15 alerts total, default high, 4 overrides (critical, medium, low, error)
	requireSeverityCount(e, 15, proto.Severity_NO_SEVERITY)

	requireSeverityCount(e, 1, proto.Severity_SEVERITY_CRITICAL)
	requireSeverityCount(e, 11, proto.Severity_SEVERITY_HIGH)
	requireSeverityCount(e, 1, proto.Severity_SEVERITY_MEDIUM)
	requireSeverityCount(e, 1, proto.Severity_SEVERITY_LOW)
	requireSeverityCount(e, 1, proto.Severity_SEVERITY_ERROR)
}

func requireSeverityCount(e *testEnv, expectedCount int, severity proto.Severity) {
	actualCount, err := e.es.CountOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}, Severity: severity})
	require.NoError(e.t, err)
	require.Equal(e.t, int64(expectedCount), actualCount)
}

// TestFixedAt tests the value of the dynamically computed "FixedAt" property of the logical alert.
func TestFixedAt(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	// Just single repository
	defaultRef := "refs/heads/main"
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 1, OwnerID: 1, DefaultRef: []byte(defaultRef), SourceUpdatedAt: updatedAt, CodeScanningEnabled: true, Visibility: sql.NullString{String: "public", Valid: true}})

	// We consider three different configurations
	main1 := testConfig{repositoryID: 1, ref: defaultRef, analysisKey: "1"}
	main2 := testConfig{repositoryID: 1, ref: defaultRef, analysisKey: "2"}
	develop := testConfig{repositoryID: 1, ref: "refs/heads/develop"}

	// Deliver a single (unfixed alert)
	e.deliverAlerts(main1, testAlert("1", "P1"))
	requireFixedCanonical(e, e.es, nil, "P1")
	// The Insights hydro events fired
	require.Len(e.t, e.publisher.insightBatches, 1)

	// Fix the alert
	a := e.deliverAlerts(main1)
	requireFixedCanonical(e, e.es, &a.CreatedAt, "P1")
	// The Insights hydro events fired
	require.Len(e.t, e.publisher.insightBatches, 2)

	// Open alert on another branch  - still fixed on default
	e.deliverAlerts(develop, testAlert("1", "P2"))
	requireFixedCanonical(e, e.es, &a.CreatedAt, "P1")
	// No new Insights event because the alert is not on the main branch
	require.Len(e.t, e.publisher.insightBatches, 2)

	// Fix alert on develop - still original fix on main that matters
	e.deliverAlerts(develop)
	requireFixedCanonical(e, e.es, &a.CreatedAt, "P1")
	// The Insights hydro events did not fire
	require.Len(e.t, e.publisher.insightBatches, 2)

	// Open the alert on main with a different category
	e.deliverAlerts(main2, testAlert("1", "P3"))
	requireFixedCanonical(e, e.es, nil, "P3")
	// The Insights hydro events fired
	require.Len(e.t, e.publisher.insightBatches, 3)

	// Another push to the first category
	// NOTE: this updates the canonical alert, but it actually is imprecise as we
	// should not have updated the canonical alert because created_at is newer
	// for P3. However we are not able to distinguish between the two in
	// Elasticsearch, so for now we accept this imprecision.
	// See https://github.com/github/code-scanning/issues/15548.
	e.deliverAlerts(main1)
	requireFixedCanonical(e, e.es, nil, "P1")
	// The Insights hydro events did not fire
	require.Len(e.t, e.publisher.insightBatches, 3)

	// Now fix the alert on the second category - this should fix the alert, and the fix time
	// should be the most recent fix
	a = e.deliverAlerts(main2)
	requireFixedCanonical(e, e.es, &a.CreatedAt, "P3")
	// The Insights hydro events fired
	require.Len(e.t, e.publisher.insightBatches, 4)
}

// Require a specific fixed at time and canonical alert
func requireFixedCanonical(e *testEnv, es *elasticsearch.Service,
	expectedFixedAt *sqltime.Time, expectedCanonical string) {
	require.NoError(e.t, es.Refresh(e.ctx, ts.Index_OrgLevel))
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)
	result, err := es.SearchOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{}, ts.Pagination{Limit: 10}, s)
	require.NoError(e.t, err)
	require.Equal(e.t, 1, len(result.AlertKeys))

	logicalAlerts, err := e.as.GetAlertsByKeys(e.ctx, result.AlertKeys)
	require.NoError(e.t, err)
	require.Equal(e.t, 1, len(logicalAlerts))
	require.Equal(e.t, 1, len(logicalAlerts[0].PhysicalAlerts))

	require.Equal(e.t, expectedFixedAt, logicalAlerts[0].GetFixedAt())
	require.Equal(e.t, e.paGuids[expectedCanonical], *logicalAlerts[0].PhysicalAlerts[0].GUID)
}

func TestHasLinks(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	// Set up single repo with some alerts
	defaultRef := []byte("refs/heads/main")
	fix1Ref := []byte("refs/heads/fix1")
	fix2and3Ref := []byte("refs/heads/fix2and3")
	repoID := ts.RepositoryEID(1)

	config := testConfig{repositoryID: repoID, ref: "refs/heads/main", analysisKey: "1", tool: "foo"}

	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: repoID, OwnerID: 1, DefaultRef: defaultRef, SourceUpdatedAt: updatedAt, CodeScanningEnabled: true})

	analysis := e.deliverAlerts(config, testAlert("1", "P1"), testAlert("2", "P2"), testAlert("3", "P3"), testAlert("4", "P4"), testAlert("5", "P5"))
	l1 := analysis.PhysicalAlerts[0].LogicalAlert
	l2 := analysis.PhysicalAlerts[1].LogicalAlert
	l3 := analysis.PhysicalAlerts[2].LogicalAlert

	// Refresh index
	require.NoError(e.t, e.es.Refresh(e.ctx, ts.Index_OrgLevel))

	// Create alert links)
	err := e.al.CreateAlertLinks(e.ctx, repoID, []*ts.LogicalAlert{l1}, 0, fix1Ref)
	require.NoError(t, err)

	err = e.al.CreateAlertLinks(e.ctx, repoID, []*ts.LogicalAlert{l2, l3}, 0, fix2and3Ref)
	require.NoError(t, err)

	// Refresh index
	require.NoError(e.t, e.es.Refresh(e.ctx, ts.Index_OrgLevel))

	// Get alerts
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)
	result, err := e.es.SearchOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}}, ts.Pagination{Limit: 10}, s)
	require.NoError(e.t, err)
	require.Equal(e.t, 5, len(result.AlertKeys))

	// Check that the documents have the correct hasLinks value
	withLinks := 0
	for _, doc := range result.Documents {
		if doc.AlertID == uint64(l1.ID) || doc.AlertID == uint64(l2.ID) || doc.AlertID == uint64(l3.ID) {
			require.True(e.t, doc.HasLinks)
			withLinks++
		} else {
			require.False(e.t, doc.HasLinks)
		}
	}
	// Make sure the IDs actually matched
	require.Equal(e.t, 3, withLinks)
}

func TestAutofixMetadata(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	// Set up single repo with some alerts
	defaultRef := []byte("refs/heads/main")
	repoID := ts.RepositoryEID(1)
	config := testConfig{repositoryID: repoID, ref: "refs/heads/main", tool: "CodeQL"}
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	repo := &ts.Repository{RepositoryID: repoID, OwnerID: 1, DefaultRef: defaultRef, SourceUpdatedAt: updatedAt, CodeScanningEnabled: true}
	dbtest.RequireCreate(e.t, e.db, repo)

	analysis := e.deliverAlerts(config, testAlert("foo/bar", "abc"), testAlert("rb/unsafe-code-construction", "def"))
	l1 := analysis.PhysicalAlerts[0].LogicalAlert
	l2 := analysis.PhysicalAlerts[1].LogicalAlert

	// Write a suggested fix for the second alert to the DB
	fixTime := sqltime.Now()
	sf := &ts.SuggestedFixAlert{
		RepositoryID:       1,
		LogicalAlertNumber: l2.Number,
		State:              ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:     fixTime,
		RefBytes:           []byte("refs/heads/main"),
		RequestedAt:        sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, sf)

	// TODO: Remove this once suggested fixes are written to the index directly
	require.NoError(e.t, e.indexRepository(e.ctx, repo))

	// Refresh index
	require.NoError(e.t, e.es.Refresh(e.ctx, ts.Index_OrgLevel))

	// Get alerts
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)
	result, err := e.es.SearchOrgAlerts(e.ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{1}}, ts.Pagination{Limit: 10}, s)
	require.NoError(e.t, err)
	require.Equal(e.t, 2, len(result.AlertKeys))

	// Check that the documents have the correct autofix values
	for _, doc := range result.Documents {
		if doc.AlertID == uint64(l1.ID) {
			require.False(e.t, doc.AutofixEligible)
			require.Empty(e.t, doc.AutofixState)
			require.Nil(e.t, doc.AutofixStateUpdatedAt)
		} else {
			require.True(e.t, doc.AutofixEligible)
			require.Equal(e.t, ts.SuggestedFixAlertStateValid.DBString(), doc.AutofixState)
			require.NotNil(e.t, doc.AutofixStateUpdatedAt)
			require.Equal(e.t, fixTime, *doc.AutofixStateUpdatedAt)
		}
	}
}

// TestSoftDeleted tests that soft deleted alerts are not returned.
func TestSoftDeleted(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)
	// Just single repository
	defaultRef := "refs/heads/main"
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(e.t, e.db, &ts.Repository{RepositoryID: 1, OwnerID: 1, DefaultRef: []byte(defaultRef), SourceUpdatedAt: updatedAt, CodeScanningEnabled: true, Visibility: sql.NullString{String: "public", Valid: true}})
	main := testConfig{repositoryID: 1, ref: defaultRef}

	// Deliver a single alert
	analysis := e.deliverAlerts(main, testAlert("1", "P1"))
	alert := analysis.PhysicalAlerts[0]

	// The alert is returned by GetAlertsByKeys
	isFixed := false
	keys := []ts.ESAlertKey{{LogicalAlertID: alert.LogicalAlertID, PhysicalAlertID: alert.ID, IsFixed: &isFixed}}
	alerts, err := e.as.GetAlertsByKeys(e.ctx, keys)
	require.NoError(t, err)
	require.Len(t, alerts, 1)
	require.Equal(t, alert.LogicalAlert.Number, alerts[0].Number) // Just check the number is correct.
	require.Len(t, alerts[0].PhysicalAlerts, 1)
	require.Equal(t, alert.FilePath, alerts[0].FilePath) // Just check the filepath is correct.

	// Now soft delete the analysis
	now := sqltime.Now()
	analysis.SoftDeletedAt = &now
	analysis.MostRecent = false
	err = db.Save(analysis).Error
	require.NoError(t, err)

	// The alert should no longer be returned by GetAlertsByKeys
	alerts, err = e.as.GetAlertsByKeys(e.ctx, keys)
	require.NoError(t, err)
	require.Empty(t, alerts)
}

func TestSecurityCampaignAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	// Set up single repo with some alerts
	defaultRef := []byte("refs/heads/main")
	repoID := ts.RepositoryEID(1)
	config := testConfig{repositoryID: repoID, ref: "refs/heads/main", tool: "CodeQL"}
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	repo := &ts.Repository{RepositoryID: repoID, OwnerID: 1, DefaultRef: defaultRef, SourceUpdatedAt: updatedAt, CodeScanningEnabled: true}
	dbtest.RequireCreate(e.t, e.db, repo)

	analysis := e.deliverAlerts(config, testAlert("1", "P1"), testAlert("2", "P2"), testAlert("3", "P3"))
	l1 := analysis.PhysicalAlerts[0].LogicalAlert
	l2 := analysis.PhysicalAlerts[1].LogicalAlert
	l3 := analysis.PhysicalAlerts[2].LogicalAlert

	// Create security campaign alerts for the first two alerts
	dbtest.RequireCreate(t, db, &ts.SecurityCampaignAlert{
		RepositoryID:       repoID,
		LogicalAlertID:     l1.ID,
		SecurityCampaignID: 1,
	})
	dbtest.RequireCreate(t, db, &ts.SecurityCampaignAlert{
		RepositoryID:       repoID,
		LogicalAlertID:     l2.ID,
		SecurityCampaignID: 1,
	})
	dbtest.RequireCreate(t, db, &ts.SecurityCampaignAlert{
		RepositoryID:       repoID,
		LogicalAlertID:     l2.ID,
		SecurityCampaignID: 2,
	})

	// Index campaign alerts
	require.NoError(e.t, e.indexRepository(e.ctx, repo))
	require.NoError(e.t, e.es.Refresh(e.ctx, ts.Index_OrgLevel))

	// Check documents
	doc1, err := e.es.GetDocument(e.ctx, ts.Index_OrgLevel, uint64(l1.ID))
	require.NoError(e.t, err)
	require.Len(e.t, doc1.SecurityCampaignIDs, 1)
	require.Equal(e.t, "1", doc1.SecurityCampaignIDs[0])

	doc2, err := e.es.GetDocument(e.ctx, ts.Index_OrgLevel, uint64(l2.ID))
	require.NoError(e.t, err)
	require.Len(e.t, doc2.SecurityCampaignIDs, 2)
	require.Equal(e.t, "1", doc2.SecurityCampaignIDs[0])
	require.Equal(e.t, "2", doc2.SecurityCampaignIDs[1])

	doc3, err := e.es.GetDocument(e.ctx, ts.Index_OrgLevel, uint64(l3.ID))
	require.NoError(e.t, err)
	require.Empty(e.t, doc3.SecurityCampaignIDs)
}
