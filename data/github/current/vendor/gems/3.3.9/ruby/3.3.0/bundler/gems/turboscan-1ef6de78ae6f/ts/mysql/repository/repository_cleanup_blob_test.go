package repository_test

import (
	"context"
	"strings"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func blobCleanupSetup(t *testing.T) (context.Context, *gorm.DB, store.SarifStore, *repository.RepositoryCleanupService) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	sarifStore := store.TestMemoryStore()
	es := elasticsearch.SetUpTestElasticSearchService(t)
	deleter := repository.NewDeletedRepositoryService(db, mocks.NewMockReposAuditsGetter(gomock.NewController(t)))
	return context.Background(), db, sarifStore, repository.NewRepositoryCleanupService(db, sarifStore, es, deleter)
}

func TestFindAnalysesForSARIFDeletion(t *testing.T) {
	ctx, db, _, s := blobCleanupSetup(t)

	// create analyses in DB
	repoID1 := ts.RepositoryEID(1)
	uncleanedWithSARIFURLAnalysis := &ts.Analysis{
		RepositoryID:       repoID1,
		SourceRepositoryID: repoID1,
		Environment:        ts.AnalysisEnv{},
		Ref:                []byte("refs/heads/aaa"),
		AnalysisName:       "analysis-1",
		SarifURL:           "my_url.sarif.zip",
		SarifID:            "sarif_id",
	}

	repoID2 := ts.RepositoryEID(2)
	uncleanedWithoutSARIFURLAnalysis := &ts.Analysis{
		RepositoryID:       repoID2,
		SourceRepositoryID: repoID2,
		Environment:        ts.AnalysisEnv{},
		Ref:                []byte("refs/heads/aaa"),
		AnalysisName:       "analysis-2",
	}

	repoID3 := ts.RepositoryEID(3)
	alreadyCleanedAnalysis := &ts.Analysis{
		RepositoryID:       repoID3,
		SourceRepositoryID: repoID3,
		Environment:        ts.AnalysisEnv{},
		Ref:                []byte("refs/heads/aaa"),
		AnalysisName:       "analysis-3",
		Cleaned:            true,
		SarifURL:           "my_url_2.sarif.zip",
		SarifID:            "sarif_id",
	}

	dbtest.RequireCreate(t, db, uncleanedWithoutSARIFURLAnalysis)
	dbtest.RequireCreate(t, db, uncleanedWithSARIFURLAnalysis)
	dbtest.RequireCreate(t, db, alreadyCleanedAnalysis)

	// fetch the analyses and ensure that only the analysis which is suitable for deletion is returned
	analyses, err := s.FindAnalysesForSARIFDeletion(ctx, repoID1, queryLimit)
	require.NoError(t, err)
	require.Equal(t, 1, len(analyses))
	require.Equalf(t, *uncleanedWithSARIFURLAnalysis, analyses[0], "the returned analysis should match the analysis that needs SARIF cleanup")

}

func TestDeleteSARIF(t *testing.T) {
	ctx, db, sarifStore, s := blobCleanupSetup(t)
	require.NoError(t, sarifStore.Open(ctx))

	// create analyses in DB
	repoID1 := ts.RepositoryEID(1)
	analysisToClean := &ts.Analysis{
		RepositoryID:       repoID1,
		SourceRepositoryID: repoID1,
		Environment:        ts.AnalysisEnv{},
		Ref:                []byte("refs/heads/aaa"),
		AnalysisName:       "analysis-1",
		SarifURL:           "my_url.sarif.zip",
		SarifID:            "sarif_id",
	}
	dbtest.RequireCreate(t, db, analysisToClean)

	// create SARIFs in storage bucket
	err := sarifStore.Upload(ctx, strings.NewReader("sarif data"), analysisToClean.SarifURL)
	require.NoError(t, err)
	sarifToCleanExists, err := sarifStore.Exists(ctx, analysisToClean.SarifURL)
	require.NoError(t, err)
	require.Truef(t, sarifToCleanExists, "sanity-check failed to ensure the file was created in storage")

	// fetch the analysis which is marked for deletion
	analyses, _ := s.FindAnalysesForSARIFDeletion(ctx, repoID1, queryLimit)
	require.Equalf(t, *analysisToClean, analyses[0], "the returned analysis should match the analysis that needs SARIF cleanup")

	// delete SARIF from storage and DB
	_, err = s.DeleteSARIF(ctx, *analysisToClean)
	require.NoError(t, err)

	// make sure that the analysisToClean was updated in DB so it's no longer returned as needing cleanup
	analyses, err = s.FindAnalysesForSARIFDeletion(ctx, repoID1, queryLimit)
	require.NoError(t, err)
	require.Empty(t, analyses)

	// make sure that the analysisToClean data was cleaned from storage
	exists, err := sarifStore.Exists(ctx, analysisToClean.SarifURL)
	require.NoError(t, err)
	require.False(t, exists)
}

func TestDeleteBlobData(t *testing.T) {
	ctx, db, sarifStore, s := blobCleanupSetup(t)
	require.NoError(t, sarifStore.Open(ctx))

	// create analyses in DB
	repoID1 := ts.RepositoryEID(1)
	analysis1 := &ts.Analysis{
		RepositoryID:       repoID1,
		SourceRepositoryID: repoID1,
		Environment:        ts.AnalysisEnv{},
		Ref:                []byte("refs/heads/aaa"),
		AnalysisName:       "analysis-1",
		SarifURL:           "sarif1.zip",
		SarifID:            "sarif_id",
	}
	dbtest.RequireCreate(t, db, analysis1)
	analysis2 := &ts.Analysis{
		RepositoryID:       repoID1,
		SourceRepositoryID: repoID1,
		Environment:        ts.AnalysisEnv{},
		Ref:                []byte("refs/heads/aaa"),
		AnalysisName:       "analysis-1",
		SarifURL:           "sarif2.zip",
		SarifID:            "sarif_id",
		ArchivalDataUrl:    "archive.zip",
	}
	dbtest.RequireCreate(t, db, analysis2)
	testSarifs := []string{analysis1.SarifURL, analysis2.SarifURL, analysis2.ArchivalDataUrl}

	// Create all SARIFs
	for _, sarif := range testSarifs {
		err := sarifStore.Upload(ctx, strings.NewReader("sarif data"), sarif)
		require.NoError(t, err)
		sarifToCleanExists, err := sarifStore.Exists(ctx, sarif)
		require.NoError(t, err)
		require.Truef(t, sarifToCleanExists, "sanity-check failed to ensure the file was created in storage")
	}

	// Create ts_deleted_repository object
	dbtest.RequireCreate(t, db, &ts.DeletedRepository{RepositoryID: repoID1})

	// Delete all data (3 blobs)
	err := s.BlobData(ctx, repoID1)
	require.NoError(t, err)

	// 3 blobs have been deleted
	var deleted ts.DeletedRepository
	err = db.First(&deleted, "repository_id = ?", repoID1).Error
	require.NoError(t, err)
	require.Equal(t, uint64(3), deleted.BlobsDeleted)

	// All SARIF files are gone
	// Create all SARIFs
	for _, sarif := range testSarifs {
		exists, err := sarifStore.Exists(ctx, sarif)
		require.NoError(t, err)
		require.False(t, exists)
	}
}
