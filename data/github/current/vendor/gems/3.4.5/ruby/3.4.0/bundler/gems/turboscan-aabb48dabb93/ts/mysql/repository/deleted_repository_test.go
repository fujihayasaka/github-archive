package repository_test

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts/mysql/repository"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/ghapi"
	"github.com/github/turboscan/ts/mocks"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
	_ "gocloud.dev/blob/memblob"
)

const (
	queryLimit = 10
)

func setup(t *testing.T) (context.Context, *gorm.DB, *mocks.MockReposAuditsGetter, *repository.DeletedRepositoryService) {
	t.Helper()

	db := dbtest.RequireConnection(t)

	reposAuditsInternalAPI := mocks.NewMockReposAuditsGetter(gomock.NewController(t))

	return context.Background(), db, reposAuditsInternalAPI, repository.NewDeletedRepositoryService(db, reposAuditsInternalAPI)
}

func TestDeleteRepositories(t *testing.T) {
	ctx, _, _, s := setup(t)
	repoID := ts.RepositoryEID(1)

	// We should be able to mark a fresh repo as deleted
	require.NoError(t, s.InsertRepositoryForDeletion(ctx, repoID))

	// Marking an already marked repo as deleted is fine as well
	require.NoError(t, s.InsertRepositoryForDeletion(ctx, repoID))

	// The repo is returned by find
	deletedRepos, err := s.FindRepositoriesForDeletion(ctx, ts.RepositoryEID(0), queryLimit)
	require.NoError(t, err)
	require.Len(t, deletedRepos, 1)
	require.Equal(t, uint64(0), deletedRepos[0].DbRowsDeleted)
	require.Equal(t, uint64(0), deletedRepos[0].EsDocsDeleted)
	require.Equal(t, uint64(0), deletedRepos[0].BlobsDeleted)
	require.Nil(t, deletedRepos[0].DeleteFinishedAt)

	// Now update the repo and its counts
	require.NoError(t, s.DeleteProgressMysql(ctx, repoID, 1))
	require.NoError(t, s.DeleteProgressES(ctx, repoID, 2))
	require.NoError(t, s.DeleteProgressBlobs(ctx, repoID, 3))

	// The repo is still returned by find
	deletedRepos, err = s.FindRepositoriesForDeletion(ctx, ts.RepositoryEID(0), queryLimit)
	require.NoError(t, err)
	require.Len(t, deletedRepos, 1)
	require.Equal(t, uint64(1), deletedRepos[0].DbRowsDeleted)
	require.Equal(t, uint64(2), deletedRepos[0].EsDocsDeleted)
	require.Equal(t, uint64(3), deletedRepos[0].BlobsDeleted)
	require.Nil(t, deletedRepos[0].DeleteFinishedAt)

	// Now mark the repos as completely deleted
	require.NoError(t, s.CompleteDeleteProgress(ctx, repoID))

	// The repo is no longer returned by find
	deletedRepos, err = s.FindRepositoriesForDeletion(ctx, ts.RepositoryEID(0), queryLimit)
	require.NoError(t, err)
	require.Empty(t, deletedRepos)
}

func TestFindRepositoriesForDeletion_WithRepoID(t *testing.T) {
	ctx, db, _, s := setup(t)

	now := sqltime.Now()
	reposForDeletion := []*ts.DeletedRepository{
		{ID: 1, RepositoryID: 1, BaseModel: ts.BaseModel{CreatedAt: now, UpdatedAt: now}},
		{ID: 2, RepositoryID: 2, BaseModel: ts.BaseModel{CreatedAt: now, UpdatedAt: now}},
		{ID: 3, RepositoryID: 3, BaseModel: ts.BaseModel{CreatedAt: now, UpdatedAt: now}},
	}
	for _, repo := range reposForDeletion {
		dbtest.RequireCreate(t, db, repo)
	}

	// make sure that fetching the repos for deletion with a repoID returns it as the result
	result, err := s.FindRepositoriesForDeletion(ctx, ts.RepositoryEID(2), queryLimit)
	require.NoError(t, err)
	require.Equal(t, 1, len(result), "only one result is expected to be returned when the repoID is provided")
	require.Equal(t, reposForDeletion[1], result[0], "the result should match the 2nd repo in the DB (repoID = 2)")

	// make sure that a low query limit does not interfere with fetching the requested repoID
	result, err = s.FindRepositoriesForDeletion(ctx, ts.RepositoryEID(2), 1)
	require.NoError(t, err)
	require.Equal(t, 1, len(result), "only one result is expected to be returned when the repoID is provided")
	require.Equal(t, reposForDeletion[1], result[0], "the result should match the 2nd repo in the DB (repoID = 2)")

	// make sure that a zero-value repoID does not filter the results
	result, err = s.FindRepositoriesForDeletion(ctx, 0, queryLimit)
	require.NoError(t, err)
	require.Equal(t, len(reposForDeletion), len(result), "zero-value repoID should not filter the results")

}

func TestDeletedRepositoriesOnDotcom_WithDeletedRepos(t *testing.T) {
	ctx, _, mockReposAPI, s := setup(t)

	repoIDs := []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(2)}
	apiResult := ghapi.RepoAuditsResponse{
		Results: []ghapi.RepoAudit{
			{RepositoryID: 1, Result: ghapi.RepoNotFound}, {RepositoryID: 2, Result: "active"},
		},
	}

	mockReposAPI.EXPECT().GetReposAudits(ctx, ghapi.RepoAuditsRequest{RepositoryIDs: repoIDs}).Return(apiResult, nil)

	result, err := s.DeletedRepositoriesOnDotcom(ctx, repoIDs)
	require.NoError(t, err)

	require.Equal(t, 1, len(result), "only one result is expected to be returned because only one repo was marked as 'not_found' as part of the returned result")
	require.Equal(t, repoIDs[0], result[0], "the result should match the repo in the 0 index as it's the that was marked as 'not_found' in the returned result")
}

func TestDeletedRepositoriesOnDotcom_WithoutDeleterRepos(t *testing.T) {
	ctx, _, mockReposAPI, s := setup(t)

	repoIDs := []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(2)}
	apiResult := ghapi.RepoAuditsResponse{
		Results: []ghapi.RepoAudit{{RepositoryID: 1, Result: "active"}, {RepositoryID: 2, Result: "active"}},
	}

	mockReposAPI.EXPECT().GetReposAudits(ctx, ghapi.RepoAuditsRequest{RepositoryIDs: repoIDs}).Return(apiResult, nil)

	result, err := s.DeletedRepositoriesOnDotcom(ctx, repoIDs)
	require.NoError(t, err)
	require.Equal(t, 0, len(result), "no results are expected because no repos were marked as 'not_found' as part of the returned result")
}

func TestDeletedRepositoriesOnDotcom_WithError(t *testing.T) {
	ctx, _, mockReposAPI, s := setup(t)

	repoIDs := []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(2)}

	expectedErr := errors.New("Some error from API")
	mockReposAPI.EXPECT().GetReposAudits(ctx, ghapi.RepoAuditsRequest{RepositoryIDs: repoIDs}).Return(ghapi.RepoAuditsResponse{}, expectedErr)

	result, err := s.DeletedRepositoriesOnDotcom(ctx, repoIDs)
	require.ErrorIs(t, err, expectedErr)
	require.Nil(t, result)
}
