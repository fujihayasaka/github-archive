package managedanalyses_test

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/enabled_status"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/jinzhu/gorm"
	"go.uber.org/mock/gomock"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mocks"
	"github.com/stretchr/testify/require"
)

const (
	workflowRunID = ts.WorkflowRunEID(123)
)

func NewEnabledStatusService(t *testing.T, db *gorm.DB, publisher enabled_status.Publisher, shouldPublish bool) *enabled_status.EnabledStatusService {
	t.Helper()
	alertService := alert.TestService(db)
	repoService := repository.NewService(db)
	mockCtrl := gomock.NewController(t)
	mockCodeQLRunPub := mocks.NewMockCodeqlRunPublisher(mockCtrl)
	managedAnalysisService := managedanalysis.NewService(db, mockCodeQLRunPub)

	return enabled_status.NewEnabledStatusService(db, alertService, repoService, managedAnalysisService, publisher, shouldPublish)
}

func TestUpsertCodeqlRunStatus_Success_NoCurrentConfig(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)

	config := baseConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, repo)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, config)
	require.NoError(t, err)

	// This published state is for a different repo, so shouldn't
	// affect whether we publish to Hydro
	p := &ts.PublishedEnabledState{
		RepositoryID: repoID + 1,
		Enabled:      true,
		Reason:       ts.EnablementReason_ENABLE_DEFAULT_SETUP,
	}
	dbtest.RequireCreate(t, db, p)

	// This published state is for the same repo, but `Enabled: false`.
	// So our `Enabled: true` state will be published to Hydro just the
	// same as if there was no published state stored for this repo.
	p = &ts.PublishedEnabledState{
		RepositoryID: repoID,
		Enabled:      false,
		Reason:       ts.EnablementReason_ENABLE_DEFAULT_SETUP,
	}
	dbtest.RequireCreate(t, db, p)

	runOut, err := ma.UpsertCodeqlRunStatus(ctx, repoID, workflowRunID, "sha", ts.CodeqlRunStatus_COMPLETED)
	require.NoError(t, err)
	require.Equal(t, runOut.ID, run.ID)

	// Reload from the DB
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	run = codeqlRepo.CurrentConfig.ValidationRun

	// Assert changes
	require.Equal(t, config.ID, *codeqlRepo.CurrentConfigID)
	require.Equal(t, ts.CodeqlRunStatus_COMPLETED, run.Status)
	require.Empty(t, run.Sha)
}

func TestUpsertCodeqlRunStatus_DisablePublish(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	mockPub := mocks.NewHydroEnabledStatusPublisher(mockCtrl)
	// MG: It is a bit silly that we are duplicating this test just to show that this does not publish to hydro
	e := NewEnabledStatusService(t, db, mockPub, false)
	ma.EnabledStatusService = e

	config := baseConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	_, err := createCodeqlRepo(ctx, ma.DataService, config.RepositoryID, nil, config)
	require.NoError(t, err)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, repo)

	// This shouldn't be called because we're not publishing to Hydro
	mockPub.EXPECT().EnablementEvent(gomock.Any(), gomock.Any()).Times(0)

	runOut, err := ma.UpsertCodeqlRunStatus(ctx, repoID, workflowRunID, "sha", ts.CodeqlRunStatus_COMPLETED)
	require.NoError(t, err)
	require.Equal(t, runOut.ID, run.ID)

	// Reload from the DB
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	run = codeqlRepo.CurrentConfig.ValidationRun

	// Assert changes
	require.Equal(t, config.ID, *codeqlRepo.CurrentConfigID)
	require.Equal(t, ts.CodeqlRunStatus_COMPLETED, run.Status)
	require.Empty(t, run.Sha)

	// No status information should be recorded in the DB, since we didn't actually publish
	dbtest.RequireCount(t, 0, db.Model(&ts.PublishedEnabledState{}))
}

func TestUpsertCodeqlRunStatus_Success_AlreadyPublished(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	mockPub := mocks.NewHydroEnabledStatusPublisher(mockCtrl)
	e := NewEnabledStatusService(t, db, mockPub, true)
	ma.EnabledStatusService = e

	config := baseConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	_, err := createCodeqlRepo(ctx, ma.DataService, config.RepositoryID, nil, config)
	require.NoError(t, err)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, repo)

	p := &ts.PublishedEnabledState{
		RepositoryID: repoID,
		Enabled:      true,
		Reason:       ts.EnablementReason_ENABLE_DEFAULT_SETUP,
	}
	dbtest.RequireCreate(t, db, p)

	// This shouldn't be called because we've already published
	// the enabled:true status for this repo
	mockPub.EXPECT().EnablementEvent(gomock.Any(), gomock.Any()).Times(0)

	runOut, err := ma.UpsertCodeqlRunStatus(ctx, repoID, workflowRunID, "sha", ts.CodeqlRunStatus_COMPLETED)
	require.NoError(t, err)
	require.Equal(t, runOut.ID, run.ID)

	// Reload from the DB
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	run = codeqlRepo.CurrentConfig.ValidationRun

	// Assert changes
	require.Equal(t, config.ID, *codeqlRepo.CurrentConfigID)
	require.Equal(t, ts.CodeqlRunStatus_COMPLETED, run.Status)
	require.Empty(t, run.Sha)
}

func TestUpsertCodeqlRunStatus_Success_OldCurrentConfig(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	mockPub := mocks.NewHydroEnabledStatusPublisher(mockCtrl)
	e := NewEnabledStatusService(t, db, mockPub, true)
	ma.EnabledStatusService = e

	currentConfig := baseConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, currentConfig)

	newConfig := baseConfig().MakeStaged()
	dbtest.RequireCreate(t, db, newConfig)

	oldRun := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID - 1,
		Status:          ts.CodeqlRunStatus_COMPLETED,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  currentConfig.ID,
	}
	dbtest.RequireCreate(t, db, oldRun)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  newConfig.ID,
	}
	dbtest.RequireCreate(t, db, run)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, repo)
	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, currentConfig, newConfig)
	require.NoError(t, err)

	runOut, err := ma.UpsertCodeqlRunStatus(ctx, repoID, workflowRunID, "sha", ts.CodeqlRunStatus_COMPLETED)
	require.NoError(t, err)
	require.Equal(t, runOut.ID, run.ID)

	// Reload from the DB, we should get the newly promoted config
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	run = codeqlRepo.CurrentConfig.ValidationRun

	// Assert changes
	require.Equal(t, newConfig.ID, *codeqlRepo.CurrentConfigID)
	require.True(t, codeqlRepo.CurrentConfig.IsCurrent())
	require.Equal(t, ts.CodeqlRunStatus_COMPLETED, run.Status)
	require.Empty(t, run.Sha)
}

func TestUpsertCodeqlRunStatus_Failed(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	mockPub := mocks.NewHydroEnabledStatusPublisher(mockCtrl)
	e := NewEnabledStatusService(t, db, mockPub, true)
	ma.EnabledStatusService = e

	config := baseConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:   repoID,
		StagedConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	// Since the run failed, this shouldn't be called
	mockPub.EXPECT().EnablementEvent(gomock.Any(), gomock.Any()).Times(0)

	out, err := ma.UpsertCodeqlRunStatus(ctx, repoID, workflowRunID, "sha", ts.CodeqlRunStatus_FAILED)
	require.NoError(t, err)
	require.Equal(t, out.ID, run.ID)

	// Reload from the DB
	codeqlRepo, err = ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	run = codeqlRepo.FailedConfig.ValidationRun

	// Assert changes
	require.Equal(t, ts.CodeqlRunStatus_FAILED, run.Status)
	require.Empty(t, run.Sha)
	require.Nil(t, codeqlRepo.StagedConfigID)
	require.Equal(t, config.ID, *codeqlRepo.FailedConfigID)
	require.Nil(t, codeqlRepo.SoftDeletedAt)
}

func TestUpsertCodeqlRunStatus_FailedToWaitingState(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	mockPub := mocks.NewHydroEnabledStatusPublisher(mockCtrl)
	e := NewEnabledStatusService(t, db, mockPub, true)
	ma.EnabledStatusService = e

	config := baseConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:   repoID,
		StagedConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	// Since the run failed, this shouldn't be called
	mockPub.EXPECT().EnablementEvent(gomock.Any(), gomock.Any()).Times(0)

	out, err := ma.UpsertCodeqlRunStatus(ctx, repoID, workflowRunID, "sha", ts.CodeqlRunStatus_FAILED)
	require.NoError(t, err)
	require.Equal(t, out.ID, run.ID)

	// Reload from the DB
	codeqlRepo, err = ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)

	// Assert changes
	require.Nil(t, codeqlRepo.SoftDeletedAt)
	require.Equal(t, ts.OnboardingStatus_WAITING, codeqlRepo.OnboardingStatus())
}

func TestUpsertCodeqlRunStatus_RepositoryMetadataUpdate(t *testing.T) {
	db, ctx, ma, _, _, _ := setup(t)
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	mockPub := mocks.NewHydroEnabledStatusPublisher(mockCtrl)
	e := NewEnabledStatusService(t, db, mockPub, true)
	ma.EnabledStatusService = e

	updateRepositoryCalled := false
	updateRepository := func(context.Context, ts.RepositoryEID) error { updateRepositoryCalled = true; return nil }
	ma.UpdateRepoMetadata = updateRepository

	config := baseConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, config)
	require.NoError(t, err)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, repo)

	out, err := ma.UpsertCodeqlRunStatus(ctx, repoID, workflowRunID, "sha", ts.CodeqlRunStatus_COMPLETED)
	require.NoError(t, err)
	require.Equal(t, out.ID, run.ID)

	// Assert that the updateRepository function was called
	require.True(t, updateRepositoryCalled)

	// Only update the BPRs if the run is a validation run
	newWorkflowRunID := workflowRunID + 1
	run = &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   newWorkflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_PUSH,
	}
	dbtest.RequireCreate(t, db, run)

	// Since this isn't a validation run, this shouldn't be called
	mockPub.EXPECT().EnablementEvent(gomock.Any(), gomock.Any()).Times(0)
	updateRepositoryCalled = false
	out, err = ma.UpsertCodeqlRunStatus(ctx, repoID, newWorkflowRunID, "sha", ts.CodeqlRunStatus_COMPLETED)
	require.NoError(t, err)
	require.Equal(t, out.ID, run.ID)

	// Assert that the updateRepository function was NOT called
	require.False(t, updateRepositoryCalled)

	// Don't update repo metadata if the validation status isn't final
	newWorkflowRunID = workflowRunID + 2
	run = &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   newWorkflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	mockPub.EXPECT().EnablementEvent(gomock.Any(), gomock.Any()).Times(0)
	updateRepositoryCalled = false
	out, err = ma.UpsertCodeqlRunStatus(ctx, repoID, newWorkflowRunID, "sha", ts.CodeqlRunStatus_INPROGRESS)
	require.NoError(t, err)
	require.Equal(t, out, run)

	// Assert that the updateRepository function was NOT called
	require.False(t, updateRepositoryCalled)

	// Don't update repo metadata if the validation failed
	newWorkflowRunID = workflowRunID + 3
	run = &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   newWorkflowRunID,
		Status:          ts.CodeqlRunStatus_INPROGRESS,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	mockPub.EXPECT().EnablementEvent(gomock.Any(), gomock.Any()).Times(0)
	updateRepositoryCalled = false
	out, err = ma.UpsertCodeqlRunStatus(ctx, repoID, newWorkflowRunID, "sha", ts.CodeQlRunStatus_CANCELLED)
	require.NoError(t, err)
	require.Equal(t, out.ID, run.ID)

	// Assert that the updateRepository function was NOT called
	require.False(t, updateRepositoryCalled)
}

func baseConfig() *ts.CodeqlConfig {
	return &ts.CodeqlConfig{
		RepositoryID:           repoID,
		Languages:              ts.Languages{"javascript"},
		Workflow:               "test",
		CreatedByActorLogin:    "foobar",
		RepositoryGRID:         "g123",
		OnboardedByActorGRID:   "a123",
		QuerySuiteType:         ts.ExtendedQuerySuiteType(),
		ThreatModel:            ts.ThreatModel_REMOTE_LOCAL,
		UsingCombinedLanguages: true,
	}
}
