package managedanalyses_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

func TestSkipCheckForPR(t *testing.T) {
	db, ctx, ma, _, _, mockManagedAnalysesAPI := setup(t)

	currentConfig := &ts.CodeqlConfig{
		RepositoryID: repoID,
	}
	currentConfig.MakeCurrent()
	dbtest.RequireCreate(t, db, currentConfig)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: currentConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})
	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, currentConfig, nil)
	require.NoError(t, err)

	mockManagedAnalysesAPI.EXPECT().SkipCheckForPR(ctx, repoID, uint64(1)).Return(nil)

	err = ma.SkipCheckForPR(ctx, repoID, 1)
	require.NoError(t, err)

	// Check codeqlRepo
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	require.True(t, codeqlRepo.IsOnboarded())
}

func TestSkipCheckForPR_OffboardsRepo(t *testing.T) {
	db, ctx, ma, _, _, mockManagedAnalysesAPI := setup(t)

	currentConfig := &ts.CodeqlConfig{
		RepositoryID: repoID,
	}
	currentConfig.MakeCurrent()
	dbtest.RequireCreate(t, db, currentConfig)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: currentConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})
	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, currentConfig, nil)
	require.NoError(t, err)

	mockManagedAnalysesAPI.EXPECT().SkipCheckForPR(ctx, repoID, uint64(1)).Return(ts.ErrGHASDisabled)

	err = ma.SkipCheckForPR(ctx, repoID, 1)
	require.NoError(t, err)

	// Check codeqlRepo
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	require.False(t, codeqlRepo.IsOnboarded())
}
