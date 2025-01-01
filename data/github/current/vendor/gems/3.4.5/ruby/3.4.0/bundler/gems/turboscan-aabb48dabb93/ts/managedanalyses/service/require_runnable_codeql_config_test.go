package managedanalyses_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/flipper"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestRequireRunnableCodeqlConfig_NoCodeqlRepo(t *testing.T) {
	_, ctx, ma, _, _, _ := setup(t)

	config, _, _, err := ma.RequireRunnableCodeqlConfig(ctx, repoID)
	require.Error(t, err)
	require.ErrorIs(t, err, ts.ErrCodeqlRepoNotFound)
	require.Nil(t, config)
}

func TestRequireRunnableCodeqlConfig_NotOnboarded(t *testing.T) {
	_, ctx, ma, _, _, _ := setup(t)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, nil)
	require.NoError(t, err)

	config, _, _, err := ma.RequireRunnableCodeqlConfig(ctx, repoID)
	require.Error(t, err)
	require.ErrorIs(t, err, ts.ErrNotOnboarded)
	require.Nil(t, config)
}

func TestRequireRunnableCodeqlConfig_RequiredServicesDisabled_FFoff(t *testing.T) {
	db, ctx, ma, _, _, mockManagedAnalysesAPI := setup(t)
	ctx = flipper.WithFeatureDisabled(ctx, flipper.CodeScanningSkipOffboardingOnMissingServices)

	config := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, config, nil)
	require.NoError(t, err)

	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repoID).Return(false, nil, ts.CodeqlPacks(""), nil)

	config, _, _, err = ma.RequireRunnableCodeqlConfig(ctx, repoID)
	require.Error(t, err)
	require.ErrorIs(t, err, maservice.ErrRequiredServicesNotEnabled)
	require.Nil(t, config)

	// The Status should now be offboarded
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	require.False(t, codeqlRepo.IsOnboarded())
}

func TestRequireRunnableCodeqlConfig_RequiredServicesDisabled_FFon(t *testing.T) {
	db, ctx, ma, _, _, mockManagedAnalysesAPI := setup(t)
	ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningSkipOffboardingOnMissingServices)

	config := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, config, nil)
	require.NoError(t, err)

	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repoID).Return(false, nil, ts.CodeqlPacks(""), nil)

	config, _, _, err = ma.RequireRunnableCodeqlConfig(ctx, repoID)
	require.Error(t, err)
	require.ErrorIs(t, err, maservice.ErrRequiredServicesNotEnabled)
	require.Nil(t, config)

	// The Status should still be onboarded
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	require.True(t, codeqlRepo.IsOnboarded())
}

func TestRequireRunnableCodeqlConfig_RequiredServicesSuccess(t *testing.T) {
	db, ctx, ma, _, _, mockManagedAnalysesAPI := setup(t)

	config := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, config, nil)
	require.NoError(t, err)

	expectedTenant := &ts.ProximaTenant{Slug: "avocado-corp", ID: 123}
	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repoID).Return(true, expectedTenant, ts.CodeqlPacks(""), nil)

	config, aTenant, _, err := ma.RequireRunnableCodeqlConfig(ctx, repoID)
	require.NoError(t, err)
	require.NotNil(t, config)
	require.Equal(t, "avocado-corp", aTenant.Slug)
	require.Equal(t, 123, int(aTenant.ID))
}

func TestRequireRunnableCodeqlConfig_UpdatedInstallationEID(t *testing.T) {
	db, ctx, ma, _, _, mockManagedAnalysesAPI := setup(t)

	config := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, config, nil)
	require.NoError(t, err)

	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repoID).Return(true, nil, ts.CodeqlPacks(""), nil)

	config, _, _, err = ma.RequireRunnableCodeqlConfig(ctx, repoID)
	require.NoError(t, err)
	require.NotNil(t, config)
}

func baseCodeqlConfig() *ts.CodeqlConfig {
	return &ts.CodeqlConfig{
		RepositoryID: repoID,
	}
}
