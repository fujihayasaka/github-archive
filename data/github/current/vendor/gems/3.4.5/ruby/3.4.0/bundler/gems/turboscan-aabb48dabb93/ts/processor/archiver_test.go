package processor

import (
	"testing"
	"time"

	"github.com/github/turboscan/ts/mysql/archiver"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/limits"
	"github.com/stretchr/testify/require"
)

// We do not promote to most_recent to allow everything to be archived
var defaultNoPromoteConfig = testConfig{repositoryID: testRepoID, commitBehavior: CommitBehaviorNoPromote}

var defaultArchiveTestOpts = archiver.ArchiveOpts{UploadOnly: true, StrictVerify: true}

func TestFullArchive(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	testSarifs := []string{
		"../sarif/testdata/empty.sarif",
		"../sarif/testdata/example.sarif",
		"../sarif/testdata/example3.sarif",
		"../sarif/testdata/classification.sarif",
		"../sarif/testdata/security-severity.sarif",
		"../sarif/testdata/snippets.sarif",
		"../sarif/testdata/rulesExtensions.sarif",
		"../sarif/testdata/combineExtensions.sarif",
		"../sarif/testdata/automation_id_multiple.sarif",
		"../sarif/testdata/example_query_uri.sarif",
		"../sarif/testdata/example-full-name-tool.sarif",
		"../sarif/testdata/example-suppressions.sarif",
		"../sarif/testdata/example-flow-no-region.sarif",
	}

	// deliver all analyses first because deliveries can affect previous analyses (e.g: most_recent).
	for _, sarifPath := range testSarifs {
		for _, a := range e.deliverSARIFMultiple(defaultNoPromoteConfig, sarifPath) {
			// Load analysis and run full validating archival.
			analysis, err := e.archiveService.LoadAnalysis(e.ctx, testRepoID, a.ID, true)
			require.NoError(t, err)
			expectedAlertCount := len(analysis.PhysicalAlerts)
			e.requirePhysicalAlertsForAnalysis(a.ID, expectedAlertCount)

			// Archive - upload only
			err = e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true})
			require.NoError(t, err)
			require.NoError(t, db.First(&a).Error)
			require.Equal(e.t, ts.ArchivalState_LIVE, a.ArchivalState)
			e.requirePhysicalAlertsForAnalysis(a.ID, expectedAlertCount)

			require.NoError(t, db.First(&a).Error)

			// Archive - skip delete
			err = e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{})
			require.NoError(t, err)
			require.NoError(t, db.First(&a).Error)
			require.Equal(e.t, ts.ArchivalState_SARIF_CREATED, a.ArchivalState)
			e.requirePhysicalAlertsForAnalysis(a.ID, expectedAlertCount)

			require.NoError(t, db.First(&a).Error)

			// Fully archive including deletions
			err = e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{Delete: true})
			require.NoError(t, err)
			require.NoError(t, db.First(&a).Error)
			require.Equal(e.t, ts.ArchivalState_ARCHIVED, a.ArchivalState)
			e.requirePhysicalAlertsForAnalysis(a.ID, 0)
		}
	}
}

func TestArchiveBuildSarifOpts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	a := e.deliverAndStoreSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif", nil)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true})
	require.NoError(t, err)

	require.NoError(t, db.First(&a).Error)

	sarif, err := e.ss.Download(e.ctx, a.ArchivalDataUrl)
	require.NoError(t, err)
	require.Contains(t, sarif.String(), "$repoHtmlUrl")
	require.Contains(t, sarif.String(), "$alertApiUrl")
}

func TestFetchEligibleAnalyses(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)
	repoID := ts.RepositoryEID(1)

	now := time.Now()
	sqlNow := sqltime.Time{Time: now}
	sqlOneDayAgo := sqltime.Time{Time: now.AddDate(0, 0, -1)}
	sqlThirtyOneDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -31)}
	sqlThirtyTwoDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -32)}
	sqlThirtyThreeDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -33)}

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

	done := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		ArchivalState:      ts.ArchivalState_ARCHIVED,
		Ref:                []byte("refs/heads/done"),
		ToolID:             1,
	}
	done.CreatedAt = sqlOneDayAgo
	done.UpdatedAt = sqlOneDayAgo
	dbtest.RequireCreate(t, db, done)

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

	failed := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
		Failed:             true,
	}

	failed.CreatedAt = sqlThirtyThreeDaysAgo
	failed.UpdatedAt = sqlThirtyThreeDaysAgo
	dbtest.RequireCreate(t, db, failed)

	failedArchival := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/aaa"),
		ToolID:             1,
		ArchivalFailed:     true,
	}
	failedArchival.CreatedAt = sqlThirtyThreeDaysAgo
	failedArchival.UpdatedAt = sqlThirtyThreeDaysAgo
	dbtest.RequireCreate(t, db, failedArchival)

	// Trivial partitioning
	partitions := archiver.MakePartitions(1)
	require.Len(t, partitions, 1)
	partition := partitions[0]

	// fetch all older than 30 days
	analyses, err := e.archiveService.FetchEligibleAnalyses(e.ctx, 30, 1000, partition, 0, 0, false)
	require.NoError(t, err)
	require.Len(t, analyses, 2)

	// fetch all analyses that are 'archivable'
	analyses, err = e.archiveService.FetchEligibleAnalyses(e.ctx, 0, 1000, partition, 0, 0, false)
	require.NoError(t, err)
	require.Len(t, analyses, 3)

	// fetch with limit
	analyses, err = e.archiveService.FetchEligibleAnalyses(e.ctx, 30, 1, partition, 0, 0, false)
	require.NoError(t, err)
	require.Len(t, analyses, 1)

	sarifCreated := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         false,
		ArchivalState:      ts.ArchivalState_SARIF_CREATED,
		Category:           "sarif-created",
		Ref:                []byte("refs/heads/done"),
		ToolID:             1,
	}
	sarifCreated.CreatedAt = sqlThirtyTwoDaysAgo
	sarifCreated.UpdatedAt = sqlThirtyTwoDaysAgo
	dbtest.RequireCreate(t, db, sarifCreated)

	// fetch with limit
	analyses, err = e.archiveService.FetchEligibleAnalyses(e.ctx, 30, 1, partition, 0, 0, false)
	require.NoError(t, err)
	require.Len(t, analyses, 1)
	require.EqualValues(t, "sarif-created", analyses[0].Category)

	// fetch with limit
	analyses, err = e.archiveService.FetchEligibleAnalyses(e.ctx, 30, 2, partition, 0, 0, false)
	require.NoError(t, err)
	require.Len(t, analyses, 2)
	require.EqualValues(t, "sarif-created", analyses[0].Category)

	// fetch failed
	analyses, err = e.archiveService.FetchEligibleAnalyses(e.ctx, 30, 1, partition, 0, 0, true)
	require.NoError(t, err)
	require.Len(t, analyses, 1)

	// fetch multiple partitions
	testCounts := []int{1, 2, 3, 4}
	for _, count := range testCounts {
		allAnalyses := []*ts.Analysis{}
		for _, p := range archiver.MakePartitions(count) {
			analyses, err = e.archiveService.FetchEligibleAnalyses(e.ctx, 0, 1000, p, 0, 0, false)
			require.NoError(t, err)
			allAnalyses = append(allAnalyses, analyses...)
		}
		require.Len(t, allAnalyses, 4)
	}
}

// TestArchiveToolGUID tests that archive/unarchive handles the case
// where the internal tool GUID is different from the generated one
func TestArchiveToolGUID(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif")
	// Change the GUID of the tool
	require.NoError(t, e.db.Table("ts_tools").Where("id = ?", a.ToolID).Update("guid", "new-guid").Error)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

// TestArchiveMissingToolVersions tests that archive/unarchive handles the case
// where the tool version table is empty because it was never populated.
func TestArchiveMissingToolVersions(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif")
	// Remove all tool versions mappings
	require.NoError(t, e.db.Delete(&ts.AnalysisToolVersion{}, "analysis_id = ?", a.ID).Error)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

// TestArchiveClassifications tests that archive/unarchive handles the case
// where the file classifications changed after the SARIF was read.
// See https://github.com/github/code-scanning/issues/6746.
func TestArchiveClassifications(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	a := e.deliverAndStoreSARIF(defaultNoPromoteConfig, "../sarif/testdata/classification.sarif", nil)
	// Change the classifications of all alerts
	require.NoError(t, e.db.Table("ts_physical_alerts").Where("analysis_id = ?", a.ID).Update("file_classification", ts.FileClassification{}).Error)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

func TestArchiveLimits(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that archival still works for severely reduced limits.
	// See https://github.com/github/code-scanning/issues/6787 for example.
	cfg := defaultNoPromoteConfig
	reducedLimits := limits.LimitsDefault()
	reducedLimits.StepsPerResLimit = 10
	cfg.limitSelector = limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{testRepoID: reducedLimits}, true)
	a := e.deliverSARIF(cfg, "../sarif/testdata/example2.sarif")

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

func TestArchiveOldTool(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that archival works for for old un-renamed tools.
	// See https://github.com/github/code-scanning/issues/6914 for example.
	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/empty.sarif")
	// Change the name of the tool to the pre-renamed one.
	require.NoError(t, e.db.Table("ts_tools").Update("canonical_name", "CodeQL command-line toolchain").Error)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

func TestArchiveOldAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that archival works for for old alerts that have wrong security severity
	// See https://github.com/github/code-scanning/issues/7103.
	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/security-severity-small.sarif")
	// Change the alerts to not have security severity.
	require.NoError(t, e.db.Table("ts_physical_alerts").Update("security_severity", nil).Error)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

func TestURLEncoding(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that archival works for filepaths that have been URL encoded
	// See https://github.com/github/code-scanning/issues/7343.
	// Note that there is a wide range of URL issues, and so far we
	// have only addressed a subset of those.
	// I expect to extend this test as we decide what route to take.
	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/example-encoding.sarif")

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

func TestArchiveRenamedTool(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that archival works for for tools that have changed capitalization.
	// See https://github.com/github/code-scanning/issues/7568.
	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif")
	// Change the capitalization of the tool
	require.NoError(t, e.db.Table("ts_tools").Update("canonical_name", "CODEQL").Error)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

func TestArchiveEmptyMessage(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that archival works for old alerts that do not have a message.
	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif")
	// Change the message to be empty
	require.NoError(t, e.db.Table("ts_physical_alerts").Update("message", "").Error)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}

func TestArchiveEmptyFilepath(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// Test that archival works for old alerts that do not have filepath.
	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif")
	// Change the file_path to be empty
	require.NoError(t, e.db.Table("ts_physical_alerts").Update("file_path", "").Error)

	// As there are very few alerts without file_path, we just allow archival to fail.
	// We could later fix this by migrating the old data and change the options
	// to be `defaultArchiveTestOpts`
	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true, StrictVerify: false})
	require.NoError(t, err)
}

func TestSarifRecreation(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	a := e.deliverAndStoreSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif", nil)
	db.First(&a)

	// check that the processed SARIF has been created
	require.NotEmpty(t, a.ArchivalDataUrl)
	firstUpdate := a.UpdatedAt

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true, StrictVerify: false})
	require.NoError(t, err)
	db.First(&a)
	// archiving should not have updated the analysis
	require.Equal(t, firstUpdate, a.UpdatedAt)

	// we should re-archive if the previous archiving attempt failed
	a.ArchivalFailed = true
	db.Save(&a)
	err = e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true, StrictVerify: false})
	require.NoError(t, err)
	db.First(&a)
	require.NotEqual(t, firstUpdate, a.UpdatedAt)
}

func TestArchiveWithFailedVerification(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif")
	// Change the file_path to be empty. This will cause the verification to fail.
	require.NoError(t, e.db.Table("ts_physical_alerts").Update("file_path", "").Error)

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true, StrictVerify: false})
	require.NoError(t, err)
	db.First(&a)

	// If we skip verification, we should be able to archive the analysis
	err = e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true, StrictVerify: false, SkipVerification: true})
	require.NoError(t, err)
	db.First(&a)
	require.False(t, a.ArchivalFailed)
	require.NotEmpty(t, a.ArchivalDataUrl)
}

func TestRearchive(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/example.sarif")

	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true})
	require.NoError(t, err)
	db.First(&a)
	require.NotEmpty(t, a.ArchivalDataUrl)
	oldUpdatedAt := a.UpdatedAt

	// the analysis shouldn't be updated if the SARIF file has already been created
	err = e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true})
	require.NoError(t, err)
	db.First(&a)
	require.NotEmpty(t, a.ArchivalDataUrl)
	require.Equal(t, oldUpdatedAt, a.UpdatedAt)

	// the analysis is updated if we set the rearchive flag
	err = e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, archiver.ArchiveOpts{UploadOnly: true, Rearchive: true})
	require.NoError(t, err)
	db.First(&a)
	require.NotEmpty(t, a.ArchivalDataUrl)
	require.NotEqual(t, oldUpdatedAt, a.UpdatedAt)
}

func TestArchiveQuerySuites(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	// archiving succeeds when default queries are disabled
	a := e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/codeql_config.sarif")

	require.True(t, *a.DefaultQueriesDisabled)
	require.Equal(t, 3, len(a.AnalysisQuerySuites))
	err := e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)

	// archiving succeeds when default queries are enabled
	a = e.deliverSARIF(defaultNoPromoteConfig, "../sarif/testdata/tool-status-notification-with-single-language-extracted-but-sublanguage.sarif")

	require.False(t, *a.DefaultQueriesDisabled)
	require.Equal(t, 0, len(a.AnalysisQuerySuites))
	err = e.archiveService.FullArchive(e.ctx, testRepoID, a.ID, defaultArchiveTestOpts)
	require.NoError(t, err)
}
