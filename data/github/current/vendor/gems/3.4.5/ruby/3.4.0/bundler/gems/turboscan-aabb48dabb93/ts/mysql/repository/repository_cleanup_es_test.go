package repository_test

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts/mysql/repository"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestDeleteElasticSearchData(t *testing.T) {
	db := dbtest.RequireConnection(t)
	sarifStore := store.TestMemoryStore()
	es := elasticsearch.SetUpTestElasticSearchService(t)
	reposAuditsInternalAPI := mocks.NewMockReposAuditsGetter(gomock.NewController(t))
	deleter := repository.NewDeletedRepositoryService(db, reposAuditsInternalAPI)
	s := repository.NewRepositoryCleanupService(db, sarifStore, es, deleter)
	ctx := context.Background()

	// The actual delete is already tested in the ElasticSearch package. This test just
	// asserts that the progress is correctly written.
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

	dbtest.RequireCreate(t, db, &ts.DeletedRepository{RepositoryID: ts.RepositoryEID(1)})
	require.NoError(t, s.ElasticSearchData(ctx, ts.RepositoryEID(1)))
	// One document should be deleted
	var deleted ts.DeletedRepository
	err = db.First(&deleted, "repository_id = ?", ts.RepositoryEID(1)).Error
	require.NoError(t, err)
	require.Equal(t, uint64(1), deleted.EsDocsDeleted)
}
