package managedanalyses_test

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestOnboardRepo(t *testing.T) {
	db, ctx, ma, _, mockLauncher, _ := setup(t)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, nil)
	require.NoError(t, err)

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			// Side-effect from this call
			run.WorkflowRunID = 123
			return nil
		},
	)

	wfID, err := ma.OnboardRepo(ctx, repoID, ts.Languages{"ruby"}, ts.QuerySuite_DEFAULT, ts.ThreatModel_REMOTE, botActor, []byte("main"), ts.OwnerEID(1), ts.CodeqlPacks(""), false, "")
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(123), wfID)

	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlRepo{}))
	out := &ts.CodeqlRepo{}
	err = db.First(out, "repository_id = ?", repoID).Error
	require.NoError(t, err)
	require.NotNil(t, out.StagedConfigID)
}

func TestOnboardRepoNotRecreatesCodeqlRepo(t *testing.T) {
	db, ctx, ma, _, mockLauncher, _ := setup(t)

	repoID := ts.RepositoryEID(1)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:        repoID,
		EnabledByActorLogin: "enabledLogin",
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			// Side-effect from this call
			run.WorkflowRunID = 123
			return nil
		},
	)

	wfID, err := ma.OnboardRepo(ctx, repoID, ts.Languages{"ruby"}, ts.QuerySuite_DEFAULT, ts.ThreatModel_REMOTE, botActor, []byte("main"), ts.OwnerEID(1), ts.CodeqlPacks(""), false, "")
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(123), wfID)

	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlRepo{}))

	out := &ts.CodeqlRepo{}
	err = db.First(out, "repository_id = ?", repoID).Error
	require.NoError(t, err)
	require.Equal(t, codeqlRepo.EnabledByActorLogin, out.EnabledByActorLogin)
	require.NotNil(t, out.StagedConfigID)
}

func TestOnboardRepo_AppliesCodeScanningLabelIfPresent(t *testing.T) {
	db, ctx, ma, _, mockLauncher, _ := setup(t)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
		OwnerID:         1,
	}
	dbtest.RequireCreate(t, db, repo)

	codeqlRepo, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, nil)
	require.NoError(t, err)

	codeqlRepo.UsingCSRunnerLabel = true
	err = ma.DataService.UpdateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	ownerID := ts.OwnerEID(1)
	languages := ts.Languages{"java"}

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			run.WorkflowRunID = 101
			return nil
		},
	).Times(1)

	// Make the onboard request
	_, err = ma.OnboardRepo(ctx, repoID, languages, ts.QuerySuite_DEFAULT, ts.ThreatModel_REMOTE, botActor, []byte("main"), ownerID, ts.CodeqlPacks(""), true, "")
	require.NoError(t, err)

	// A CodeqlConfig was stored
	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlConfig{}))

	var config ts.CodeqlConfig
	err = db.First(&config).Error
	require.NoError(t, err)
	// The flag is set in the db
	require.Equal(t, true, config.UsingCSRunnerLabel)
}

func TestOnboard_RepoDoesNotApplyCodeScanningLabelIfFalse(t *testing.T) {
	db, ctx, ma, _, mockLauncher, _ := setup(t)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
		OwnerID:         1,
	}
	dbtest.RequireCreate(t, db, repo)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, nil)
	require.NoError(t, err)

	ownerID := ts.OwnerEID(1)
	languages := ts.Languages{"java"}

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			run.WorkflowRunID = 101
			return nil
		},
	).Times(1)

	// Make the onboard request
	_, err = ma.OnboardRepo(ctx, repoID, languages, ts.QuerySuite_DEFAULT, ts.ThreatModel_REMOTE, botActor, []byte("main"), ownerID, ts.CodeqlPacks(""), false, "")
	require.NoError(t, err)

	// A CodeqlConfig was stored
	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlConfig{}))

	var config ts.CodeqlConfig
	err = db.First(&config).Error
	require.NoError(t, err)
	// The flag is not set in the db
	require.Equal(t, false, config.UsingCSRunnerLabel)
}
