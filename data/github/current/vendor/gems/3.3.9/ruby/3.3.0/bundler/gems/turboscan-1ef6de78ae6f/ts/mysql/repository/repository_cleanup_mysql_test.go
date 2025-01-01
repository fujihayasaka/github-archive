package repository_test

import (
	"bytes"
	"context"
	"os/exec"
	"testing"

	"github.com/github/turboscan/ts/mysql/repository"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/mocks"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

const idOfRepoToDelete = ts.RepositoryEID(1)
const idOfRepoToKeep = ts.RepositoryEID(2)
const idNotUsed = ts.RepositoryEID(999)

// tableNamesToIgnore lists tables that have been explicitly ignored from deletion.
func tableNamesToIgnore() []string {
	return []string{
		"ts_deleted_repositories", // this keeps a record of deleted repositories
	}
}

func mysqlCleanupSetup(t *testing.T) (context.Context, *gorm.DB, *repository.RepositoryCleanupService) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	es := elasticsearch.SetUpTestElasticSearchService(t)
	reposAuditsInternalAPI := mocks.NewMockReposAuditsGetter(gomock.NewController(t))
	deleter := repository.NewDeletedRepositoryService(db, reposAuditsInternalAPI)
	return context.Background(), db, repository.NewRepositoryCleanupService(db, nil, es, deleter)
}

// TestDeletedTablesCoverEverything tests that `tablesToDelete` covers
// all tables in the database and that we havent forgotten to add new tables.
func TestDeletedTablesCoverEverything(t *testing.T) {
	db := dbtest.RequireConnection(t)

	var tableNamesInDB []string
	err := db.Table("information_schema.columns").
		Where("table_schema = 'turboscan_development'").
		Where("column_name = 'repository_id'").
		Where("table_name NOT IN (?)", tableNamesToIgnore()). // Ignore tables that should not be deleted
		Pluck("distinct table_name", &tableNamesInDB).Error
	require.NoError(t, err)

	// If we are running in the CI check that ensures that a PR's database changes are safe on main then we
	// should relax this test to allow new tables.
	// Any tables that have been deleted without also removing them from tablesToDelete should cause an error.
	git, err := exec.LookPath("git")
	require.NoError(t, err)
	branch, err := exec.Command(git, "branch", "--show-current").CombinedOutput()
	require.NoError(t, err)
	if bytes.Equal(bytes.TrimSpace(branch), []byte("main")) {
		assert.Subset(t, tableNamesInDB, repository.TablesToDelete())
		return
	}

	assert.ElementsMatch(
		t, tableNamesInDB, repository.TablesToDelete(),
		`Tables found with repository_id column whose models aren't returned by tablesToDelete or sequenceTableNames`,
	)
}

// TestAlertTablesCoverEverything tests that `AlertTablesToDelete` covers
// all tables in the database and that reference alert data.
func TestAlertTablesCoverEverything(t *testing.T) {
	db := dbtest.RequireConnection(t)

	// Main alert tables
	mainAlertTables := []string{
		"ts_logical_alerts",
		"ts_physical_alerts",
		"ts_code_flows_documents",
		"ts_snippets",
		"ts_suggested_fixes",
	}

	// These columns link to an alert table
	mainAlertTableColumnNames := []string{
		"logical_alert_id",
		"logical_alert_number",
		"physical_alert_id",
		"code_flows_document_id",
		"snippet_id",
		"suggested_fix_id",
	}

	var tableNamesInDB []string
	err := db.Table("information_schema.columns").
		Where("table_schema = 'turboscan_development'").
		Where("column_name IN (?) OR table_name IN (?)", mainAlertTableColumnNames, mainAlertTables).
		Where("table_name NOT IN (?)", tableNamesToIgnore()). // Ignore tables that should not be deleted
		Pluck("distinct table_name", &tableNamesInDB).Error
	require.NoError(t, err)

	// If we are running in the CI check that ensures that a PR's database changes are safe on main then we
	// should relax this test to allow new tables.
	// Any tables that have been deleted without also removing them from AlertTablesToDelete should cause an error.
	git, err := exec.LookPath("git")
	require.NoError(t, err)
	branch, err := exec.Command(git, "branch", "--show-current").CombinedOutput()
	require.NoError(t, err)
	if bytes.Equal(bytes.TrimSpace(branch), []byte("main")) {
		assert.Subset(t, tableNamesInDB, repository.AlertTablesToDelete())
		return
	}

	assert.ElementsMatch(
		t, tableNamesInDB, repository.AlertTablesToDelete(),
		`Tables found with an alert id column whose models aren't returned by tablesToDelete or sequenceTableNames`,
	)
}

// TestNoSoftDeletedTables check whether there are any tables where
// gorm would only do a "soft delete"
// See https://v1.gorm.io/docs/delete.html#Soft-Delete
func TestNoSoftDeletedTables(t *testing.T) {
	_, db, _, _ := setup(t)
	var softDeleteTables []string
	err := db.Table("information_schema.columns").
		Where("table_schema = 'turboscan_development'").
		Where("column_name = 'deleted_at'").
		Where("table_name NOT IN (?)", tableNamesToIgnore()). // Ignore tables that should not be deleted
		Pluck("distinct table_name", &softDeleteTables).Error
	require.NoError(t, err)

	assert.Empty(
		t, softDeleteTables,
		`Tables found that would be soft deleted instead of proper deleted`,
	)
}

// Most of these tests just test deletion of a single model type (Analysis). This
// is sufficient because the deletion logic loops over a list of tables and the
// completeness of that list is tested separately (see TestDeletedTablesCoverEverything).

func TestDeleteNoDataDoesNothing(t *testing.T) {
	ctx, _, s := mysqlCleanupSetup(t)
	err := s.MySQLData(ctx, ts.RepositoryEID(1))
	require.NoError(t, err)
	err = s.AlertData(ctx, ts.RepositoryEID(1))
	require.NoError(t, err)
}

func TestDeleteAbsentIDDoesNothing(t *testing.T) {
	ctx, db, s := mysqlCleanupSetup(t)
	createSampleModels(t, db, 1)

	err := s.MySQLData(ctx, idNotUsed)

	require.NoError(t, err)
	dbtest.RequireCount(t, 2, db.Table("ts_analyses"))
}

func TestCanDeleteOneModel(t *testing.T) {
	ctx, db, s := mysqlCleanupSetup(t)
	createSampleModels(t, db, 1)

	err := s.MySQLData(ctx, idOfRepoToDelete)

	require.NoError(t, err)
	validateCorrectRowsRemaining(t, db, 1)
}

func TestDeletedRowsConsidersMultipleModelTypes(t *testing.T) {
	ctx, db, s := mysqlCleanupSetup(t)
	config := (&ts.CodeqlConfig{
		RepositoryID: idOfRepoToDelete,
	}).MakeCurrent()

	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       idOfRepoToDelete,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
	})
	dbtest.RequireCreate(t, db, config)

	err := s.MySQLData(ctx, idOfRepoToDelete)
	require.NoError(t, err)
}

func TestCanDeleteSeveralOfAModel(t *testing.T) {
	ctx, db, s := mysqlCleanupSetup(t)
	createSampleModels(t, db, 3)

	err := s.MySQLData(ctx, idOfRepoToDelete)

	require.NoError(t, err)
	validateCorrectRowsRemaining(t, db, 3)
}

func TestCanDeleteSeveralAlerts(t *testing.T) {
	ctx, db, s := mysqlCleanupSetup(t)
	createAlertSamples(t, db, 3)

	err := s.AlertData(ctx, idOfRepoToDelete)

	require.NoError(t, err)
	validateCorrectAlertsRemaining(t, db, 3)
}

func TestCanDeleteSeveralModelsInBatches(t *testing.T) {
	ctx, db, s := mysqlCleanupSetup(t)
	createSampleModels(t, db, 3)

	// Although batch size is 1, all 3 should still be deleted
	err := s.MySQLData(repository.WithMySQLDataBatchSize(ctx, 1), idOfRepoToDelete)

	require.NoError(t, err)
	validateCorrectRowsRemaining(t, db, 3)
}

func TestCanDeleteSeveralAlertsInBatches(t *testing.T) {
	ctx, db, s := mysqlCleanupSetup(t)
	createAlertSamples(t, db, 3)

	// Although batch size is 1, all 3 should still be deleted
	err := s.AlertData(repository.WithMySQLDataBatchSize(ctx, 1), idOfRepoToDelete)

	require.NoError(t, err)
	validateCorrectAlertsRemaining(t, db, 3)
}

// createSampleModels creates 1 Analysis with a RepositoryID of `idOfKeepRepo`
// and numWithDeleteId Analyses with a RepositoryID of `idOfDeleteRepo`.
//
// See note above about why a single model is usually enough.
func createSampleModels(t *testing.T, db *gorm.DB, numWithDeleteId int) {
	t.Helper()

	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       idOfRepoToKeep,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
	})

	for i := 0; i < numWithDeleteId; i++ {
		dbtest.RequireCreate(t, db, &ts.Analysis{
			RepositoryID:       idOfRepoToDelete,
			SourceRepositoryID: 1,
			Ref:                []byte("refs/heads/main"),
		})
	}

	// Check expected number have been created
	dbtest.RequireCount(t, numWithDeleteId+1, db.Table("ts_analyses"))
	// Create ts_deleted_repository entry
	dbtest.RequireCreate(t, db, &ts.DeletedRepository{RepositoryID: idOfRepoToDelete})
}

// createAlertSamples creates 1 LogicalAlert with a RepositoryID of `idOfKeepRepo`
// and numWithDeleteId LogicalAlerts with a RepositoryID of `idOfDeleteRepo`.
func createAlertSamples(t *testing.T, db *gorm.DB, numWithDeleteId int) {
	t.Helper()

	dbtest.RequireCreate(t, db, &ts.LogicalAlert{
		RepositoryID:          idOfRepoToKeep,
		Number:                uint32(1),
		StableAlertIdentifier: []byte{1},
	})

	for i := 0; i < numWithDeleteId; i++ {
		dbtest.RequireCreate(t, db, &ts.LogicalAlert{
			RepositoryID:          idOfRepoToDelete,
			Number:                uint32(i),
			StableAlertIdentifier: []byte{byte(i)},
		})
	}

	// Check expected number have been created
	dbtest.RequireCount(t, numWithDeleteId+1, db.Table("ts_logical_alerts"))
}

func validateCorrectRowsRemaining(t *testing.T, db *gorm.DB, numWithDeleteId int) {
	t.Helper()

	dbtest.RequireCount(t, 0, db.Table("ts_analyses").Where("repository_id = ?", idOfRepoToDelete))
	dbtest.RequireCount(t, 1, db.Table("ts_analyses").Where("repository_id = ?", idOfRepoToKeep))

	var deleted ts.DeletedRepository
	require.NoError(t, db.First(&deleted, "repository_id = ?", idOfRepoToDelete).Error)
	require.Equal(t, uint64(numWithDeleteId), deleted.DbRowsDeleted)
}

func validateCorrectAlertsRemaining(t *testing.T, db *gorm.DB, numWithDeleteId int) {
	t.Helper()

	dbtest.RequireCount(t, 0, db.Table("ts_logical_alerts").Where("repository_id = ?", idOfRepoToDelete))
	dbtest.RequireCount(t, 1, db.Table("ts_logical_alerts").Where("repository_id = ?", idOfRepoToKeep))
}
