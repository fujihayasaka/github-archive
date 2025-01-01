package elasticsearch

import (
	"context"
	"strconv"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/stretchr/testify/require"
)

var allMigrationTestIndexes = []string{
	"org-migration-test-1",
	"org-migration-test-2",
}

// TestIndexMigration tests migration of ES indexes by using a simple document structure
// and swapping between different indexes.
// The general idea is that document N corresponds to alert number N for repository N,
// we then set the owner ID different to test that updates take effect.
func TestIndexMigration(t *testing.T) {
	// Start from index-1
	es := setUpInitialService(t)

	// Start migrating to index-2
	simulateStartMigration(t, es, "org-migration-test-2")

	// We can read the docs before the migration has run because we are using
	// an alias pointing to index-1
	assertAllDocs(t, es, "100", "100")

	// Migrate the first data to index-2
	simulateRunMigration(t, es)

	// Perform a variety of updates to the index, which should take effect in both,
	// even after the migration has run.
	performAlertUpdates(t, es)

	// At the moment these reads are powered by the index-1 (which should have gotten all the updates)
	assertAllDocs(t, es, "101", "100", "100", "104", "100")

	// Now complete the migration but do not delete the index
	simulateCompleteMigration(t, es, false)

	// All the updated docs should be in index-2 as well
	assertAllDocs(t, es, "101", "100", "100", "104", "100")

	// Perform an update - this should also affect index-1
	performSingleUpdate(t, es, 2, 102)
	assertAllDocs(t, es, "101", "102", "100", "104", "100")

	// New revert back to index-1
	simulateStartMigration(t, es, "org-migration-test-1")
	simulateCompleteMigration(t, es, false)

	// We can read the updated values from index-1
	assertAllDocs(t, es, "101", "102", "100", "104", "100")

	// Update again
	performSingleUpdate(t, es, 3, 103)
	assertAllDocs(t, es, "101", "102", "103", "104", "100")

	// Now try index-2 again
	simulateStartMigration(t, es, "org-migration-test-2")
	simulateCompleteMigration(t, es, false)

	// All updates have take effect
	assertAllDocs(t, es, "101", "102", "103", "104", "100")

	// Finally delete index-1
	simulateCompleteMigration(t, es, true)
	assertAllDocs(t, es, "101", "102", "103", "104", "100")
}

// setUpInitialService sets up ES service and puts the indexes and aliases in
// the right way. Furthermore it loads two alerts.
func setUpInitialService(t *testing.T) *Service {
	t.Helper()
	cfg, err := config.Load()
	require.NoError(t, err)
	ctx := context.Background()

	es, err := NewService(ctx, cfg.ESUsername, cfg.ESPassword, cfg.ESAddr, cfg.IndexSettings())
	require.NoError(t, err)

	// Remove all existing migration indexes
	indexesToDelete := []string{}
	for _, index := range allMigrationTestIndexes {
		exists, err := es.es.IndexExists(index).Do(ctx)
		require.NoError(t, err)
		if exists {
			indexesToDelete = append(indexesToDelete, index)
		}
	}
	if len(indexesToDelete) > 0 {
		_, err = es.es.DeleteIndex().Index(indexesToDelete).Do(ctx)
		require.NoError(t, err)
	}

	// Initial state is index-1 with a single read alias
	orgLevelIndex = &IndexConfig{
		name:        "org-migration-test-1",
		readAlias:   "org-migration-test-read",
		writeAlias:  "org-migration-test-write",
		mirrorAlias: "org-migration-test-mirror",
		mapping:     orglevelMapping,
	}
	err = es.CreateIndex(ctx, ts.Index_OrgLevel, false)
	require.NoError(t, err)
	_, err = es.es.Alias().
		Add("org-migration-test-1", "org-migration-test-read").
		Add("org-migration-test-1", "org-migration-test-write").
		Do(ctx)
	require.NoError(t, err)

	// Add two alerts to the initial state.
	err = es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			testDocument(1, "1", "100"),
			testDocument(2, "2", "100"),
		},
	)
	require.NoError(t, err)
	assertDoc(t, es, 1, "1", "100")
	assertDoc(t, es, 2, "2", "100")
	assertMigrationRequired(t, es, false)

	return es
}

// performAlertUpdates adds 3 new alerts, and does two different kinds of updates
// to the alerts afterwards. This makes sure everything is mirrored correctly.
func performAlertUpdates(t *testing.T, es *Service) {
	t.Helper()
	ctx := context.Background()
	// All write operations should populate both indexes, so we add extra alerts.
	err := es.indexDocument(ctx, orgLevelIndex, testDocument(3, "3", "100"))
	require.NoError(t, err)
	err = es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			testDocument(4, "4", "100"),
			testDocument(5, "5", "100"),
		},
	)
	require.NoError(t, err)
	refreshAll(t, es) // We need to refresh to be able to update one of these documents
	// And we also update existing alerts.
	err = es.UpdateRepositoryMetadata(ctx, ts.Repository{RepositoryID: 1, OwnerID: 101})
	require.NoError(t, err)
	updates := map[string]interface{}{
		"owner_id":   "104",
		"updated_at": sqltime.Now(),
	}
	err = es.UpdateAlerts(ctx, 4, []ts.LogicalAlertID{4}, updates)
	require.NoError(t, err)
}

// performSingleUpdate does a single update of the document with the specified repo ID updating it to
// the new owner ID.
func performSingleUpdate(t *testing.T, es *Service, repoID ts.RepositoryEID, newOwnerID ts.OwnerEID) {
	t.Helper()
	ctx := context.Background()
	refreshAll(t, es)
	err := es.UpdateRepositoryMetadata(ctx, ts.Repository{RepositoryID: repoID, OwnerID: newOwnerID})
	require.NoError(t, err)
}

// simulateStartMigration simulates starting a migration for the specified index name.
func simulateStartMigration(t *testing.T, es *Service, indexName string) {
	t.Helper()
	ctx := context.Background()

	// Now simulate a migration scenario where the index-number is bumped
	orgLevelIndex = &IndexConfig{
		name:        indexName,
		readAlias:   "org-migration-test-read",
		writeAlias:  "org-migration-test-write",
		mirrorAlias: "org-migration-test-mirror",
		mapping:     orglevelMapping,
	}
	err := es.CreateIndex(ctx, ts.Index_OrgLevel, false)
	require.NoError(t, err)
	assertMigrationRequired(t, es, true)

	// Simulate starting the migration
	_, err = es.StartMigration(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
}

// simulateRunMigration simuluates running a migration of data.
func simulateRunMigration(t *testing.T, es *Service) {
	t.Helper()
	ctx := context.Background()
	// Technically we do not copy from one index to the other,
	// we reindex all data, but it is easy to do the copying here
	es.SetSkipMirroring(true)
	for i := 1; i <= 10; i++ {
		doc, err := es.GetDocument(ctx, ts.Index_OrgLevel, uint64(i))
		require.NoError(t, err)
		if doc == nil {
			break
		}
		err = es.indexDocument(ctx, orgLevelIndex, doc)
		require.NoError(t, err)
	}
	es.SetSkipMirroring(false)
}

// simulateCompleteMigration simulates completing the migration.
func simulateCompleteMigration(t *testing.T, es *Service, allowDeletes bool) {
	t.Helper()
	ctx := context.Background()
	err := es.CompleteMigration(ctx, ts.Index_OrgLevel, allowDeletes)
	require.NoError(t, err)
	assertMigrationRequired(t, es, !allowDeletes)
}

// refreshAll refreshes all indexes in the test.
func refreshAll(t *testing.T, es *Service) {
	t.Helper()
	ctx := context.Background()
	_, err := es.es.Refresh(allMigrationTestIndexes...).Do(ctx)
	require.NoError(t, err)
}

// testDocument creates a simple test document
func testDocument(alertID uint64, repositoryID string, ownerID string) *ts.SearchDocument {
	return &ts.SearchDocument{
		AlertID:      alertID,
		RepositoryID: repositoryID,
		OwnerID:      ownerID,
	}
}

// assertDoc test that the document has the expected alert ID, repository ID and owner ID.
func assertDoc(t *testing.T, es *Service, alertID uint64, repositoryID string, ownerID string) {
	t.Helper()
	ctx := context.Background()

	doc, err := es.GetDocument(ctx, ts.Index_OrgLevel, alertID)
	require.NoError(t, err)
	require.NotNil(t, doc, "Could not find doc %d", alertID)
	require.Equal(t, alertID, doc.AlertID)
	require.Equal(t, repositoryID, doc.RepositoryID)
	require.Equal(t, ownerID, doc.OwnerID)
}

// assertAllDocs asserts that the documents are in the expected format and have the
// expected ownerIDs
func assertAllDocs(t *testing.T, es *Service, ownerIDs ...string) {
	t.Helper()
	for i, ownerID := range ownerIDs {
		assertDoc(t, es, uint64(i+1), strconv.Itoa(i+1), ownerID)
	}
}

// assertMigrationRequired asserts that the system expects a certain migration status.
func assertMigrationRequired(t *testing.T, es *Service, expectedMigrationRequired bool) {
	t.Helper()
	ctx := context.Background()

	actualMigrationRequired, err := es.MigrationRequired(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, expectedMigrationRequired, actualMigrationRequired)
}
