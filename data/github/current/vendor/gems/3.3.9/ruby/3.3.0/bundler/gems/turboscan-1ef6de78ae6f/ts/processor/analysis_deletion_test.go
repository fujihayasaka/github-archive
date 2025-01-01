package processor

import (
	"testing"

	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/archiver"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/proto"
)

var count int = 10000

func getUniqueRepositoryID() ts.RepositoryEID {
	count += 1
	return ts.RepositoryEID(count)
}

// captures the alerts defining an analysis delivery and whether it will subsequently be deleted.
type analysisT struct {
	delete bool         // indicates whether analysis will be deleted
	alerts []testAlertT // all the alerts for the analysis
}

// creates analyses for two different repos, one in which a subset of analyses are deleted
// and one where those same analyses were never delivered at all
func constructExpectedAndActualRepos(e *testEnv, analysesData []analysisT) (testConfig, testConfig) {

	// for the expected state we deliver only the analyses _not_ marked for deletion
	configExpected := testConfig{repositoryID: getUniqueRepositoryID(), ref: "main"}
	for _, data := range analysesData {
		if !data.delete {
			e.deliverAlerts(configExpected, data.alerts...)
		}
	}

	// for the actual state we deliver _all_ analyses, but store those that will subsequently be deleted
	configActual := testConfig{repositoryID: getUniqueRepositoryID(), ref: "main"}
	var analysesToDelete []*ts.Analysis
	for _, data := range analysesData {
		a := e.deliverAlerts(configActual, data.alerts...)
		if data.delete {
			analysesToDelete = append(analysesToDelete, a)
		}
	}
	for _, analysisToDelete := range analysesToDelete {
		_, err := e.as.SoftDeleteAnalysis(e.ctx, configActual.repositoryID, analysisToDelete.ID, false)
		require.NoError(e.t, err)
	}

	return configExpected, configActual
}

// require that the alert state is the same for expected and actual configurations
func requireMatchingAlertState(e *testEnv, configExpected testConfig, configActual testConfig) {

	expectedOpen, err := e.as.Alerts(e.ctx, configExpected.repositoryID, ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN}, ts.AnalysisFilter{Refs: [][]byte{[]byte(configExpected.ref)}}, &ts.FindOptions{Preloads: []string{"PhysicalAlerts"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(e.t, err)

	expectedResolved, err := e.as.Alerts(e.ctx, configExpected.repositoryID, ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED}, ts.AnalysisFilter{Refs: [][]byte{[]byte(configExpected.ref)}}, &ts.FindOptions{Preloads: []string{"PhysicalAlerts"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(e.t, err)

	actualOpen, err := e.as.Alerts(e.ctx, configActual.repositoryID, ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN}, ts.AnalysisFilter{Refs: [][]byte{[]byte(configActual.ref)}}, &ts.FindOptions{Preloads: []string{"PhysicalAlerts"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(e.t, err)

	actualResolved, err := e.as.Alerts(e.ctx, configActual.repositoryID, ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED}, ts.AnalysisFilter{Refs: [][]byte{[]byte(configActual.ref)}}, &ts.FindOptions{Preloads: []string{"PhysicalAlerts"}, SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(e.t, err)

	// we require that the states are the same for open and resolved alerts
	e.requireLogicalAlerts(expectedOpen, actualOpen)
	e.requireLogicalAlerts(expectedResolved, actualResolved)
}

// deleted analysis was where alert was fixed
func TestAnalysisDeletion_CanDeleteMostRecent(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	config := testConfig{ref: "main"}

	e.deliverAlerts(config, testAlert("X", "P1"), testAlert("Y", "P2"))
	a := e.deliverAlerts(config, testAlert("X", "P3"), testAlert("Y", "P4"))

	_, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.NoError(t, err)
}

func TestAnalysisDeletion_CanDeleteNotMostRecentAndNotBaseline_FF_On(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	config := testConfig{ref: "main"}

	e.deliverAlerts(config, testAlert("X", "P1"), testAlert("Y", "P2"))
	a := e.deliverAlerts(config, testAlert("X", "P3"), testAlert("Y", "P4"))
	a.MostRecent = false
	db.Save(a)

	_, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.NoError(t, err)
}

func TestAnalysisDeletion_CanDeleteWhenBaselineOfIncomplete_FF_On(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	config := testConfig{ref: "main"}

	a1 := e.deliverAlerts(config, testAlert("X", "P1"), testAlert("Y", "P2"))
	a2 := e.deliverAlerts(config, testAlert("X", "P3"), testAlert("Y", "P4"))
	a2.AnalysisComplete = false
	a2.MostRecent = false
	db.Save(a2)

	db.Find(&a2, "id=?", a2.ID)
	_, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a1.ID, true)
	require.NoError(t, err)
}

// deleted analysis was only source of fixed alert
func TestAnalysisDeletion_CannotDeleteNotMostRecentAndBaseline(t *testing.T) {

	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	config := testConfig{ref: "main"}

	e.deliverAlerts(config, testAlert("X", "P1"), testAlert("Y", "P2"))
	a := e.deliverAlerts(config, testAlert("X", "P3"), testAlert("Y", "P4"))
	e.deliverAlerts(config, testAlert("X", "P5"), testAlert("Y", "P6"))

	_, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.EqualError(t, err, ts.ErrAnalysisIsNotDeletable.Error())
}

func TestAnalysisDeletion_ForceRequiredWhenNoBaseline(t *testing.T) {

	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	actualConfig := testConfig{ref: "main"}

	a := e.deliverAlerts(actualConfig, testAlert("X", "P1"), testAlert("Y", "P2"))

	_, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.EqualError(t, err, ts.ErrMissingDeletionConfirmation.Error())

	newMostRecent, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, true)
	require.NoError(t, err)
	require.Nil(t, newMostRecent)

	unusedConfig := testConfig{repositoryID: getUniqueRepositoryID(), ref: "main"}
	requireMatchingAlertState(e, unusedConfig, actualConfig)
}

func TestAnalysisDeletion_ForceRequiredForGCdAnalyses(t *testing.T) {
	// NB can't use the `requireAnalysisDeletionMatch` method when garbage collecting
	// as it aggresively removes all the non-latest, so we don't _expect_ the two repos
	// to match if the TIP is removed

	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	actualConfig := testConfig{ref: "main"}

	e.deliverAlerts(actualConfig, testAlert("X", "P1"), testAlert("Y", "P2"))
	a := e.deliverAlerts(actualConfig, testAlert("X", "P3"), testAlert("Y", "P4"))

	e.performGC(ts.CleaningTypeAnalysisAssociations)

	_, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.EqualError(t, err, ts.ErrMissingDeletionConfirmation.Error())

	_, err = e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, true)
	require.NoError(t, err)

	unusedConfig := testConfig{repositoryID: getUniqueRepositoryID(), ref: "main"}
	requireMatchingAlertState(e, unusedConfig, actualConfig)
}

func TestAnalysisDeletion_FindAnalysesRespectsDeletion(t *testing.T) {

	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	analysesData := []analysisT{
		{false, []testAlertT{testAlert("X", "P1")}},
		{false, []testAlertT{testAlert("X", "P2"), testAlert("Y", "P3")}},
		{true, []testAlertT{testAlert("X", "P4"), testAlert("Y", "P5")}},
	}

	configExpected, configActual := constructExpectedAndActualRepos(e, analysesData)

	expectedAnalyses, _ := e.as.FindAnalyses(e.ctx, ts.AnalysisFilter{
		RepositoryID: configExpected.repositoryID,
	}, nil)

	actualAnalyses, _ := e.as.FindAnalyses(e.ctx, ts.AnalysisFilter{
		RepositoryID: configActual.repositoryID,
	}, nil)

	require.EqualValues(t, len(expectedAnalyses), len(actualAnalyses))
}

func TestAnalysisDeletion_FindAnalysesRespectsDeletionWhenIDSpecified(t *testing.T) {

	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	actualConfig := testConfig{ref: "main"}

	e.deliverAlerts(actualConfig, testAlert("X", "P1"), testAlert("Y", "P2"))
	a := e.deliverAlerts(actualConfig, testAlert("X", "P2"), testAlert("Y", "P3"))

	analyses, _ := e.as.FindAnalyses(e.ctx, ts.AnalysisFilter{
		RepositoryID: testRepoID,
		AnalysisIDs:  []ts.AnalysisID{a.ID},
	}, nil)
	require.Len(t, analyses, 1)

	_, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.NoError(t, err)

	analyses, _ = e.as.FindAnalyses(e.ctx, ts.AnalysisFilter{
		RepositoryID: testRepoID,
		AnalysisIDs:  []ts.AnalysisID{a.ID},
	}, nil)
	require.Len(t, analyses, 0)
}

func TestAnalysisDeletion_RulesEndpointsDoNotRespectDeletion(t *testing.T) {

	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	config := testConfig{ref: "main"}

	e.deliverAlerts(config, testAlert("X", "P1"))
	e.deliverAlerts(config, testAlert("X", "P2"), testAlert("Y", "P3"))
	a := e.deliverAlerts(config, testAlert("X", "P4"), testAlert("Z", "P5"))

	ruleFilter := ts.RuleFilter{RepoID: testRepoID}
	ruleTagFilter := ts.RuleTagFilter{RepoID: testRepoID}

	// check 'before' state
	rules, err := e.as.AlertsRules(e.ctx, ruleFilter)
	require.NoError(t, err)
	require.Len(t, rules, 3)

	rulesTags, err := e.as.RulesTags(e.ctx, ruleTagFilter)
	require.NoError(t, err)
	require.Len(t, rulesTags, 3)

	// delete most recent analysis
	_, err = e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.NoError(t, err)

	// check 'after' state
	rules, err = e.as.AlertsRules(e.ctx, ruleFilter)
	require.NoError(t, err)
	require.Len(t, rules, 3)

	rulesTags, err = e.as.RulesTags(e.ctx, ruleTagFilter)
	require.NoError(t, err)
	require.Len(t, rulesTags, 3)
}

func TestAnalysisDeletion_UpdateBaselineStatus(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	cfg := testConfig{ref: "main"}

	a1 := e.deliverAlerts(cfg, testAlert("X", "P1"), testAlert("Y", "P2"))
	a2 := e.deliverAlerts(cfg, testAlert("X", "P3"), testAlert("Y", "P4"))
	a3 := e.deliverAlerts(cfg, testAlert("X", "P5"), testAlert("Y", "P6"))

	// Assume a3 superseeded a2
	a3.BaselineID = &a1.ID
	db.Save(a3)

	// Deletion should have succeeded
	baseline, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a2.ID, false)
	require.NoError(t, err)
	db.Find(&a2, "id=?", a2.ID)
	require.NotNil(t, a2.SoftDeletedAt)
	require.Equal(t, baseline.ID, a1.ID)

	// a3 should still be the most recent
	db.Find(&a3, "id=?", a3.ID)
	require.True(t, a3.MostRecent)
}

func TestAnalysisDeletion_CanDeleteOutdated(t *testing.T) {

	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	config := testConfig{ref: "main"}

	e.deliverAlerts(config, testAlert("X", "P1"), testAlert("Y", "P2"))
	e.deliverAlerts(config, testAlert("X", "P3"), testAlert("Y", "P4"))
	a := e.deliverAlerts(config, testAlert("X", "P5"), testAlert("Y", "P6"))
	a.IsOutdated = true
	db.Save(a)

	_, err := e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.NoError(t, err)
}

func TestAnalysisDeletion_PhysicalAlertsLastStateChangeUpdated(t *testing.T) {

	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	config := testConfig{ref: "main"}

	baseline := e.deliverAlerts(config, testAlert("X", "P1"), testAlert("Y", "P2"))

	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    baseline.RepositoryID,
		AnalysisIDs:     []ts.AnalysisID{baseline.ID},
		IncludeOutdated: true,
	}

	alertsBefore, err := e.as.PhysicalAlerts(e.ctx, baseline.RepositoryID, ts.AlertFilter{}, analysisFilter, &ts.FindOptions{})
	require.NoError(t, err)

	a := e.deliverAlerts(config, testAlert("X", "P3"), testAlert("Y", "P4"))
	// archive the baseline
	err = e.archiveService.FullArchive(e.ctx, baseline.RepositoryID, baseline.ID, archiver.ArchiveOpts{Delete: true})
	require.NoError(t, err)
	db.Model(ts.PhysicalAlert{}).Where("analysis_id = ? AND repository_id = ? ", baseline.ID, baseline.RepositoryID).Count(&count)
	require.Equal(t, 0, count)

	_, err = e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.NoError(t, err)

	alertsAfter, err2 := e.as.PhysicalAlerts(e.ctx, baseline.RepositoryID, ts.AlertFilter{}, analysisFilter, &ts.FindOptions{})
	require.NoError(t, err2)

	require.True(t, len(alertsBefore) > 0)
	require.Len(t, alertsAfter, len(alertsBefore))

	for i := 0; i < len(alertsBefore); i++ {
		require.NotEqual(t, alertsAfter[i].LastStateChangeAt, alertsBefore[i].LastStateChangeAt)
	}
}

func TestAnalysisDeletion_RevertsAlertStates(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	config := testConfig{ref: "main"}
	// Create 2 initial alerts
	initial := e.deliverAlerts(config, testAlert("A", "PA1"), testAlert("B", "PB1"))
	analysisFilter := ts.AnalysisFilter{
		RepositoryID: initial.RepositoryID,
		State:        ts.AnalysisStateFilterMostRecent,
	}
	initialAlerts, err := e.as.Alerts(e.ctx, initial.RepositoryID, ts.AlertFilter{}, analysisFilter, &ts.FindOptions{SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, initialAlerts, 2)
	require.False(t, *initialAlerts[0].IsFixed) // Alert A is open
	require.False(t, *initialAlerts[1].IsFixed) // Alert B is open

	// Fix the first alerts and create 2 new ones
	baseline := e.deliverAlerts(config, testAlert("C", "PC1"), testAlert("D", "PD1"))

	baselineAlerts, err := e.as.Alerts(e.ctx, baseline.RepositoryID, ts.AlertFilter{}, analysisFilter, &ts.FindOptions{SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, baselineAlerts, 4)
	require.True(t, *baselineAlerts[0].IsFixed)  // Alert A is fixed
	require.True(t, *baselineAlerts[1].IsFixed)  // Alert B is fixed
	require.False(t, *baselineAlerts[2].IsFixed) // Alert C is open
	require.False(t, *baselineAlerts[3].IsFixed) // Alert D is open

	// Create the target analysis which reopens alert "B", keeps alert "C", fixes "D", and adds alert "E"
	a := e.deliverAlerts(config, testAlert("B", "PB2"), testAlert("C", "PC2"), testAlert("E", "PE1"))

	alertsBefore, err := e.as.Alerts(e.ctx, baseline.RepositoryID, ts.AlertFilter{}, analysisFilter, &ts.FindOptions{SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, alertsBefore, 5)
	require.True(t, *alertsBefore[0].IsFixed)  // Alert A is fixed
	require.False(t, *alertsBefore[1].IsFixed) // Alert B is open
	require.False(t, *alertsBefore[2].IsFixed) // Alert C is open
	require.True(t, *alertsBefore[3].IsFixed)  // Alert D is fixed
	require.False(t, *alertsBefore[4].IsFixed) // Alert E is open

	// Archive the baseline
	err = e.archiveService.FullArchive(e.ctx, baseline.RepositoryID, baseline.ID, archiver.ArchiveOpts{Delete: true})
	require.NoError(t, err)
	// confirm we no longer have physical alerts associated with the baseline in the database
	var count int
	db.Model(ts.PhysicalAlert{}).Where("analysis_id = ? AND repository_id = ? ", baseline.ID, baseline.RepositoryID).Count(&count)
	require.Equal(t, 0, count)

	// Delete the target analysis
	_, err = e.as.SoftDeleteAnalysis(e.ctx, testRepoID, a.ID, false)
	require.NoError(t, err)

	db.Find(&baseline, "id=?", baseline.ID)
	require.True(t, baseline.MostRecent)

	// Make sure the alerts reverted to the baseline state
	alertsAfter, err := e.as.Alerts(e.ctx, baseline.RepositoryID, ts.AlertFilter{}, analysisFilter, &ts.FindOptions{SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING)})
	require.NoError(t, err)
	require.Len(t, alertsAfter, 4)
	require.True(t, *alertsAfter[0].IsFixed)  // Alert A is fixed
	require.True(t, *alertsAfter[1].IsFixed)  // Alert B is fixed
	require.False(t, *alertsAfter[2].IsFixed) // Alert C is open
	require.False(t, *alertsAfter[3].IsFixed) // Alert D is open
}
