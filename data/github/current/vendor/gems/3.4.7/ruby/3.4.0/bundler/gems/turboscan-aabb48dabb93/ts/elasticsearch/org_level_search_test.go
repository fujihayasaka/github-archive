package elasticsearch

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func TestDeleteByRepoNoData(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	assertCount(ctx, t, es, 0)
	deleted, err := es.DeleteByRepo(ctx, ts.RepositoryEID(12394823), 60*1000)
	require.NoError(t, err)
	require.Equal(t, int64(0), deleted)
	assertCount(ctx, t, es, 0)
}

func TestDeleteByRepoDoesNotDeleteForNonExistentID(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "2",
				AlertID:         43,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	assertCount(ctx, t, es, 2)
	deleted, err := es.DeleteByRepo(ctx, ts.RepositoryEID(3), 60*1000)
	require.NoError(t, err)
	require.Equal(t, int64(0), deleted)
	assertCount(ctx, t, es, 2)
}

func TestDeleteByRepoDeletesForExistingID(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "2",
				AlertID:         43,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	assertCount(ctx, t, es, 2)
	deleted, err := es.DeleteByRepo(ctx, ts.RepositoryEID(2), 60*1000)
	require.NoError(t, err)
	require.Equal(t, int64(1), deleted)
	assertCount(ctx, t, es, 1)
}

func TestDeleteByRepoDeletesMultipleForExistingId(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "1",
				AlertID:         44,
				FullDescription: "XSS is very bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "2",
				AlertID:         43,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			},
		},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	assertCount(ctx, t, es, 3)
	deleted, err := es.DeleteByRepo(ctx, ts.RepositoryEID(1), 60*1000)
	require.NoError(t, err)
	require.Equal(t, int64(2), deleted)
	assertCount(ctx, t, es, 1)
}

func TestDeleteMigrationOngoing(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "1",
				AlertID:         44,
				FullDescription: "XSS is very bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "2",
				AlertID:         43,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			},
		},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))
	assertCount(ctx, t, es, 3)

	// Simulate on ongoing migration
	orgLevelIndex.readAlias = "test-new-read"
	migrationRequired, err := es.MigrationRequired(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.True(t, migrationRequired)

	deleted, err := es.DeleteByRepo(ctx, ts.RepositoryEID(1), 60*1000)
	require.ErrorIs(t, err, ErrMigrationOngoing)
	// Nothing was deleted
	require.Equal(t, int64(0), deleted)
	assertCount(ctx, t, es, 3)
}

// assertCount checks that the total count of documents in the org-level index is as expected.
func assertCount(ctx context.Context, t *testing.T, es *Service, expected int64) {
	t.Helper()
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))
	count, err := es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, expected, count)
}
