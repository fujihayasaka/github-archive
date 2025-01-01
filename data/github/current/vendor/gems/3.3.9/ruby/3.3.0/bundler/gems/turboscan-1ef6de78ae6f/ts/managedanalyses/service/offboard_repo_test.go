package managedanalyses_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

func TestOffboardRepo(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)

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

	err = ma.OffboardRepo(ctx, repoID)
	require.NoError(t, err)
}

func TestOffboardRepo_NotDeletesCodeqlRepo(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)

	// Setup DB
	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID: repoID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)
	currentConfig := &ts.CodeqlConfig{
		RepositoryID: repoID,
	}
	currentConfig.MakeCurrent()
	dbtest.RequireCreate(t, db, currentConfig)

	err := ma.OffboardRepo(ctx, ts.RepositoryEID(1))
	require.NoError(t, err)

	// Check codeqlRepo
	out := &ts.CodeqlRepo{}
	err = db.First(out, "repository_id = ?", repoID).Error
	require.NoError(t, err)
	require.Nil(t, out.SoftDeletedAt)
}

func TestOffboardRepo_NoChangeRequired(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)

	deprecatedConfig := &ts.CodeqlConfig{
		RepositoryID: repoID,
	}
	deprecatedConfig.Deprecate()
	dbtest.RequireCreate(t, db, deprecatedConfig)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: deprecatedConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, deprecatedConfig, nil)
	require.NoError(t, err)

	err = ma.OffboardRepo(ctx, repoID)
	require.ErrorIs(t, err, ts.ErrNoChangeRequired)
}
