package managedanalysis

import (
	"context"
	"testing"
	"time"

	"github.com/pkg/errors"

	"github.com/SamuelTissot/sqltime"
	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	ma "github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/workflows"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	gomock "go.uber.org/mock/gomock"
)

const (
	repoID                  = ts.RepositoryEID(1)
	actionsWorkflowRunID    = ts.WorkflowRunEID(123)
	executionID             = "123"
	workflowTemplateVersion = "version"
)

func TestWithTransaction(t *testing.T) {
	db, s, ctx := testSetup(t)

	dbtest.RequireCount(t, 0, db.Model(&ts.CodeqlSchedule{}))

	// Transaction is committed when no error is returned
	err := s.WithTransaction(func(tx ma.CodeqlDB) error {
		err := tx.CreateCodeqlSchedule(ctx, repoID, time.Now())
		require.NoError(t, err)

		return nil
	})
	require.NoError(t, err)
	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlSchedule{}))

	// Transaction is rolled back when an error is returned
	repoID2 := repoID + 1
	err = s.WithTransaction(func(tx ma.CodeqlDB) error {
		err := tx.CreateCodeqlSchedule(ctx, repoID2, time.Now())
		require.NoError(t, err)

		return errors.New("Error")
	})
	require.Error(t, err)
	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlSchedule{}))

	// Nested transaction works
	err = s.WithTransaction(func(tx ma.CodeqlDB) error {
		err := tx.WithTransaction(func(tx2 ma.CodeqlDB) error {
			_ = tx2.CreateCodeqlSchedule(ctx, repoID2, time.Now())
			return nil
		})

		return err
	})
	require.ErrorIs(t, err, ErrTransactionInProgress)
	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlSchedule{}))

	// WithTransaction works when a method with an internal transaction is called
	config := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:    repoID,
		CurrentConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)
	run := &ts.CodeqlRun{
		RepositoryID:   config.RepositoryID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  2,
	}
	dbtest.RequireCreate(t, db, run)

	err = s.WithTransaction(func(tx ma.CodeqlDB) error {
		return tx.DisableCodeqlConfigByRepo(ctx, repoID)
	})
	require.NoError(t, err)
	dbtest.RequireCount(t, 0, db.Model(&ts.CodeqlConfig{}).Where("TAG = ?", ts.CodeqlConfigTag_CURRENT))

	// Error from the internal transaction is returned correctly
	err = s.WithTransaction(func(tx ma.CodeqlDB) error {
		return tx.DisableCodeqlConfigByRepo(ctx, repoID2)
	})
	require.ErrorIs(t, err, ts.ErrCodeqlRepoNotFound)
}

func TestConsistency(t *testing.T) {
	db, s, ctx := testSetup(t)
	wfLibrary := workflows.NewLibrary()

	repoID := ts.RepositoryEID(1)
	wfRunId := 1

	// STEP1: Create codeql repo
	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID: repoID,
	}
	err := s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	var outRepo ts.CodeqlRepo
	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.CurrentConfigID)
	require.Nil(t, outRepo.StagedConfigID)
	require.Nil(t, outRepo.FailedConfigID)

	// STEP2: Onboard
	stagedTag := ts.CodeqlConfigTag_STAGED
	stagedConfig := &ts.CodeqlConfig{
		RepositoryID: repoID,
		Tag:          &stagedTag,
	}
	err = s.CreateStagedCodeqlConfig(ctx, stagedConfig)
	require.NoError(t, err)

	wf := wfLibrary.GetWorkflowTemplate(ctx, repoID)
	run, err := stagedConfig.SetUpForValidationRunWithAutoAdjust(ts.Ref("defaultRef"), ts.EmptySha, wf, ts.CodeqlRunTriggeringEvent_VALIDATION, ts.OwnerEID(1), ts.CodeqlPacks(""))
	require.NoError(t, err)
	run.WorkflowRunID = ts.WorkflowRunEID(wfRunId)
	wfRunId += 1
	err = s.CreateCodeqlRun(ctx, run)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.CurrentConfigID)
	require.Nil(t, outRepo.FailedConfigID)

	require.NotNil(t, outRepo.StagedConfigID) // Staged Config should be populated
	err = db.Where("id = ?", outRepo.StagedConfigID).First(&stagedConfig).Error
	require.NoError(t, err)
	require.Equal(t, stagedConfig.ID, *outRepo.StagedConfigID)

	// STEP3: Onboard validation fails
	failedStatus := ts.CodeqlRunStatus_FAILED
	err = s.DeprecateStagedCodeqlConfig(ctx, repoID, stagedConfig.ID, &failedStatus)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.CurrentConfigID)
	require.Nil(t, outRepo.StagedConfigID) // Staged should not be populated now

	var failedConfig ts.CodeqlConfig
	require.NotNil(t, outRepo.FailedConfigID) // Failed Config should be populated
	err = db.Where("id = ?", outRepo.FailedConfigID).First(&failedConfig).Error
	require.NoError(t, err)
	require.Equal(t, failedConfig.ID, *outRepo.FailedConfigID)

	// STEP4: New Onboard
	stagedConfig = &ts.CodeqlConfig{
		RepositoryID: repoID,
		Tag:          &stagedTag,
	}
	err = s.CreateStagedCodeqlConfig(ctx, stagedConfig)
	require.NoError(t, err)

	run, err = stagedConfig.SetUpForValidationRunWithAutoAdjust(ts.Ref("defaultRef"), ts.EmptySha, wf, ts.CodeqlRunTriggeringEvent_VALIDATION, ts.OwnerEID(1), ts.CodeqlPacks(""))
	require.NoError(t, err)
	run.WorkflowRunID = ts.WorkflowRunEID(wfRunId)
	wfRunId += 1
	err = s.CreateCodeqlRun(ctx, run)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.CurrentConfigID)

	require.NotNil(t, outRepo.StagedConfigID) // Staged Config should be populated
	err = db.Where("id = ?", outRepo.StagedConfigID).First(&stagedConfig).Error
	require.NoError(t, err)
	require.Equal(t, stagedConfig.ID, *outRepo.StagedConfigID)

	require.NotNil(t, outRepo.FailedConfigID) // Failed config should stay populated
	err = db.Where("id = ?", outRepo.FailedConfigID).First(&failedConfig).Error
	require.NoError(t, err)
	require.Equal(t, failedConfig.ID, *outRepo.FailedConfigID)

	// STEP5: New Onboard validation succeeds
	completed := ts.CodeqlRunStatus_COMPLETED
	err = s.PromoteCodeqlConfigToCurrent(ctx, stagedConfig, repoID, &completed)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)

	var currentConfig ts.CodeqlConfig
	require.NotNil(t, outRepo.CurrentConfigID) // Current config should be populated
	err = db.Where("id = ?", outRepo.CurrentConfigID).First(&currentConfig).Error
	require.NoError(t, err)
	require.Equal(t, currentConfig.ID, *outRepo.CurrentConfigID)

	require.Nil(t, outRepo.StagedConfigID)
	require.Nil(t, outRepo.FailedConfigID)

	// STEP6: Update
	stagedConfig = &ts.CodeqlConfig{
		RepositoryID: repoID,
		Tag:          &stagedTag,
	}
	err = s.CreateStagedCodeqlConfig(ctx, stagedConfig)
	require.NoError(t, err)

	run, err = stagedConfig.SetUpForValidationRunWithAutoAdjust(ts.Ref("defaultRef"), ts.EmptySha, wf, ts.CodeqlRunTriggeringEvent_VALIDATION, ts.OwnerEID(1), ts.CodeqlPacks(""))
	require.NoError(t, err)
	run.WorkflowRunID = ts.WorkflowRunEID(wfRunId)
	err = s.CreateCodeqlRun(ctx, run)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)

	require.NotNil(t, outRepo.CurrentConfigID) // Current config should be populated
	err = db.Where("id = ?", outRepo.CurrentConfigID).First(&currentConfig).Error
	require.NoError(t, err)
	require.Equal(t, currentConfig.ID, *outRepo.CurrentConfigID)

	require.NotNil(t, outRepo.StagedConfigID) // Staged Config should be populated
	err = db.Where("id = ?", outRepo.StagedConfigID).First(&stagedConfig).Error
	require.NoError(t, err)
	require.Equal(t, stagedConfig.ID, *outRepo.StagedConfigID)

	require.Nil(t, outRepo.FailedConfigID)

	// STEP7: Update validation fails
	err = s.DeprecateStagedCodeqlConfig(ctx, repoID, stagedConfig.ID, &failedStatus)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)

	require.NotNil(t, outRepo.CurrentConfigID) // Current config should be populated
	err = db.Where("id = ?", outRepo.CurrentConfigID).First(&currentConfig).Error
	require.NoError(t, err)
	require.Equal(t, currentConfig.ID, *outRepo.CurrentConfigID)

	require.Nil(t, outRepo.StagedConfigID)

	var outFailed ts.CodeqlConfig
	require.NotNil(t, outRepo.FailedConfigID) // Failed config should stay populated
	err = db.Where("id = ?", outRepo.FailedConfigID).First(&outFailed).Error
	require.NoError(t, err)
	require.Equal(t, outFailed.ID, *outRepo.FailedConfigID)

	// STEP8: Offboard
	err = s.DisableCodeqlConfigByRepo(ctx, repoID)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.CurrentConfigID)
	require.Nil(t, outRepo.StagedConfigID)
	require.Nil(t, outRepo.FailedConfigID)
}

func TestCreateCodeqlRepo(t *testing.T) {
	db, s, ctx := testSetup(t)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:        1,
		SupportedLanguages:  []string{"python", "ruby"},
		QuerySuite:          ts.QuerySuite_EXTENDED,
		ThreatModel:         ts.ThreatModel_REMOTE,
		EnabledByActorLogin: "actor",
		RepositoryGRID:      ts.RepositoryGRID("asdf"),
	}

	err := s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	var out ts.CodeqlRepo
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.Equal(t, 2, len(out.SupportedLanguages))
	require.Equal(t, ts.QuerySuite_EXTENDED, out.QuerySuite)
	require.Equal(t, ts.ThreatModel_REMOTE, out.ThreatModel)
	require.Equal(t, "actor", out.EnabledByActorLogin)
	require.Equal(t, codeqlRepo.RepositoryGRID, out.RepositoryGRID)
	require.True(t, out.UsingCombinedLanguages)

	// Check that the update logic works
	codeqlRepo.SupportedLanguages = []string{}
	codeqlRepo.QuerySuite = ts.QuerySuite_DEFAULT

	err = s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	var newOut ts.CodeqlRepo
	err = db.Where("repository_id = ?", repoID).First(&newOut).Error
	require.NoError(t, err)
	require.Equal(t, out.CreatedAt, newOut.CreatedAt)    // CreatedAt should not change
	require.NotEqual(t, out.EnabledAt, newOut.EnabledAt) // EnabledAt should reflect the new enablement
	require.Equal(t, 0, len(newOut.SupportedLanguages))
	require.Equal(t, ts.QuerySuite_DEFAULT, newOut.QuerySuite)

	// Check that the recreation of codeqlrepo works
	err = s.DeleteCodeqlRepo(ctx, out.RepositoryID)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&newOut).Error
	require.NoError(t, err)
	require.NotNil(t, newOut.SoftDeletedAt)

	err = s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&newOut).Error
	require.NoError(t, err)
	require.Nil(t, out.SoftDeletedAt)
	require.Equal(t, out.CreatedAt, newOut.CreatedAt)    // CreatedAt should not change
	require.NotEqual(t, out.EnabledAt, newOut.EnabledAt) // EnabledAt should reflect the new enablement
}

func TestCreateCodeqlRepoKeepsUsingCombinedLanguages(t *testing.T) {
	db, s, ctx := testSetup(t)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:        1,
		SupportedLanguages:  []string{"python", "ruby"},
		QuerySuite:          ts.QuerySuite_EXTENDED,
		ThreatModel:         ts.ThreatModel_REMOTE,
		EnabledByActorLogin: "actor",
		RepositoryGRID:      ts.RepositoryGRID("asdf"),
	}

	err := s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	var out ts.CodeqlRepo
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.True(t, out.UsingCombinedLanguages)

	// Update the value
	out.UsingCombinedLanguages = false
	err = db.Save(out).Error
	require.NoError(t, err)

	// Delete and recreate the repo
	err = s.DeleteCodeqlRepo(ctx, out.RepositoryID)
	require.NoError(t, err)

	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.NotNil(t, out.SoftDeletedAt)

	err = s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	// Check UsingCombinedLanguages hasn't changed
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.False(t, out.UsingCombinedLanguages)
}

func TestCreateStagedCodeqlConfig(t *testing.T) {
	db, s, ctx := testSetup(t)

	err := s.CreateCodeqlRepo(ctx, &ts.CodeqlRepo{RepositoryID: repoID})
	require.NoError(t, err)

	// we don't use baseCodeqlConfig() here because we want control over the
	// values given to all fields so we can check they were persisted correctly
	config := (&ts.CodeqlConfig{
		RepositoryID:         repoID,
		RepositoryGRID:       "123456",
		OnboardedByActorGRID: "123abc",
		CreatedByActorLogin:  "abc",
		Languages:            []string{"javascript"},
		InitialLanguages:     []string{"javascript"},
		TemplateVersion:      "v1",
		ThreatModel:          ts.ThreatModel_REMOTE_LOCAL,
	}).MakeStaged()

	err = s.CreateStagedCodeqlConfig(ctx, config)
	require.NoError(t, err)

	out := &ts.CodeqlConfig{}
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.True(t, out.IsStaged())
	require.Equal(t, config.RepositoryGRID, out.RepositoryGRID)
	require.Equal(t, config.OnboardedByActorGRID, out.OnboardedByActorGRID)
	require.Equal(t, "abc", out.CreatedByActorLogin)
	require.Equal(t, 1, len(out.Languages))
	require.Equal(t, 1, len(out.InitialLanguages))
	require.Equal(t, "v1", out.TemplateVersion)
	require.Equal(t, ts.ThreatModel_REMOTE_LOCAL, out.ThreatModel)
}

func TestCreateStagedCodeqlConfig_UpdatesCodeqlRepo(t *testing.T) {
	db, s, ctx := testSetup(t)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID: repoID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	config := baseCodeqlConfig().MakeStaged()
	err := s.CreateStagedCodeqlConfig(ctx, config)
	require.NoError(t, err)

	out := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.Equal(t, config.ID, *out.StagedConfigID)
}

func TestCreateStagedCodeqlConfig_FailNotEnabling(t *testing.T) {
	_, s, ctx := testSetup(t)

	configDeprecated := baseCodeqlConfig().Deprecate()

	configCurrent := baseCodeqlConfig().MakeCurrent()

	err := s.CreateStagedCodeqlConfig(ctx, configDeprecated)
	require.Error(t, err)

	err = s.CreateStagedCodeqlConfig(ctx, configCurrent)
	require.Error(t, err)
}

func TestCreateStagedCodeqlConfig_FailStagedExists(t *testing.T) {
	db, s, ctx := testSetup(t)

	err := s.CreateCodeqlRepo(ctx, &ts.CodeqlRepo{RepositoryID: repoID})
	require.NoError(t, err)

	config := baseCodeqlConfig().MakeStaged()
	err = s.CreateStagedCodeqlConfig(ctx, config)
	require.NoError(t, err)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   config.RepositoryID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})

	// After initial creation, the CodeqlConfigTag is STAGED. Trying to recreate will fail.
	require.True(t, config.IsStaged())
	err = s.CreateStagedCodeqlConfig(ctx, config)
	require.Error(t, err)

	// But creating as CURRENT will succeed.
	config.MakeCurrent()
	runStatus := ts.CodeqlRunStatus_COMPLETED
	err = s.PromoteCodeqlConfigToCurrent(ctx, config, config.RepositoryID, &runStatus)
	require.NoError(t, err)

	err = s.CreateStagedCodeqlConfig(ctx, config)
	require.Error(t, err)
}

func TestDisableByRepo_OnlyCurrent(t *testing.T) {
	db, s, ctx := testSetup(t)

	config := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)
	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:    repoID,
		CurrentConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	err := s.DisableCodeqlConfigByRepo(ctx, repoID)
	require.NoError(t, err)

	// Check codeqlConfig
	out := &ts.CodeqlConfig{}
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.True(t, out.IsDeprecated())
	require.NotNil(t, out.DeprecatedAt)

	// Check codeqlRepo
	outRepo := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.CurrentConfigID)
	require.Nil(t, outRepo.FailedConfigID)
}

func TestDisableByRepo_OnlyStaged(t *testing.T) {
	db, s, ctx := testSetup(t)

	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:   repoID,
		StagedConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	err := s.DisableCodeqlConfigByRepo(ctx, repoID)
	require.NoError(t, err)

	// Check codeqlConfig
	out := &ts.CodeqlConfig{}
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.True(t, out.IsDeprecated())
	require.NotNil(t, out.DeprecatedAt)

	// Check codeqlRepo
	outRepo := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.StagedConfigID)
	require.Nil(t, outRepo.FailedConfigID)
}

func TestDisableByRepo_CurrentAndStaged(t *testing.T) {
	db, s, ctx := testSetup(t)

	currentConfig := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, currentConfig)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: currentConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})

	stagedConfig := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, stagedConfig)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: stagedConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  actionsWorkflowRunID,
	})

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:    repoID,
		CurrentConfigID: &currentConfig.ID,
		StagedConfigID:  &stagedConfig.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	err := s.DisableCodeqlConfigByRepo(ctx, repoID)
	require.NoError(t, err)

	// Check codeqlConfig
	out := &ts.CodeqlConfig{}
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.True(t, out.IsDeprecated())
	require.NotNil(t, out.DeprecatedAt)

	// Check codeqlRepo
	outRepo := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.CurrentConfigID)
	require.Nil(t, outRepo.StagedConfigID)
	require.Nil(t, outRepo.FailedConfigID)
}

func TestDisableByRepo_AlreadyDisabled(t *testing.T) {
	db, s, ctx := testSetup(t)

	config := baseCodeqlConfig().Deprecate()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)
	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID: repoID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	err := s.DisableCodeqlConfigByRepo(ctx, repoID)
	require.ErrorIs(t, ts.ErrCodeqlConfigNotFound, err)

	// Check codeqlConfig
	out := &ts.CodeqlConfig{}
	err = db.Where("repository_id = ?", repoID).First(&out).Error
	require.NoError(t, err)
	require.True(t, out.IsDeprecated())
	require.Equal(t, config.DeprecatedAt, out.DeprecatedAt)

	// Check codeqlRepo
	outRepo := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", repoID).First(&outRepo).Error
	require.NoError(t, err)
	require.Nil(t, outRepo.CurrentConfigID)
	require.Nil(t, outRepo.StagedConfigID)
	require.Nil(t, outRepo.FailedConfigID)
}

func TestPromoteCodeqlConfigToCurrent(t *testing.T) {
	db, s, ctx := testSetup(t)

	err := s.CreateCodeqlRepo(ctx, &ts.CodeqlRepo{RepositoryID: repoID})
	require.NoError(t, err)

	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})

	// first we test config promotion when there's no other config around for the repo
	runCompleted := ts.CodeqlRunStatus_COMPLETED
	err = s.PromoteCodeqlConfigToCurrent(ctx, config, repoID, &runCompleted)
	require.NoError(t, err)

	out, err := getCurrentConfig(ctx, s, repoID)
	require.NoError(t, err)

	require.Equal(t, config.ID, out.ID)
	require.True(t, out.IsCurrent())
	require.Equal(t, &runCompleted, out.ValidationRunStatus)
	require.NotNil(t, out.EnabledAt)
	require.Nil(t, out.DeprecatedAt)

	// and now a new config will take that place
	newConfig := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, newConfig)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: newConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	})

	err = s.PromoteCodeqlConfigToCurrent(ctx, newConfig, repoID, &runCompleted)
	require.NoError(t, err)

	out, err = getCurrentConfig(ctx, s, repoID)
	require.NoError(t, err)

	// we test the config promotion went as expected
	require.Equal(t, newConfig.ID, out.ID)
	require.True(t, out.IsCurrent())
	require.Equal(t, &runCompleted, out.ValidationRunStatus)
	require.NotNil(t, out.EnabledAt)
	require.Nil(t, out.DeprecatedAt)

	// and the deprecation of the previous config too
	out = &ts.CodeqlConfig{}
	err = db.Where("id = ?", config.ID).First(&out).Error
	require.NoError(t, err)
	require.True(t, out.IsDeprecated())
	// it has both enabled_at and deprecated_at
	require.NotNil(t, out.EnabledAt)
	require.NotNil(t, out.DeprecatedAt)
	require.True(t, out.EnabledAt.Time.Before(out.DeprecatedAt.Time))
}

func TestPromoteCodeqlConfigToCurrent_AfterOffboarding(t *testing.T) {
	db, s, ctx := testSetup(t)

	config := baseCodeqlConfig().Deprecate()
	dbtest.RequireCreate(t, db, config)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})
	err := s.CreateCodeqlRepo(ctx, &ts.CodeqlRepo{RepositoryID: repoID})
	require.NoError(t, err)

	err = s.PromoteCodeqlConfigToCurrent(ctx, config, repoID, nil)
	require.ErrorIs(t, ts.ErrCodeqlConfigNotFound, err)

	outConfig, err := getCurrentConfig(ctx, s, repoID)
	require.NoError(t, err)
	require.Nil(t, outConfig)
}

func TestPromoteCodeqlConfigToCurrent_UpdatesCodeqlRepo(t *testing.T) {
	db, s, ctx := testSetup(t)

	config := baseCodeqlConfig()
	config.QuerySuiteType = ts.ExtendedQuerySuiteType()
	config.ThreatModel = ts.ThreatModel_REMOTE_LOCAL
	config.MakeStaged()
	dbtest.RequireCreate(t, db, config)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:   repoID,
		QuerySuite:     ts.QuerySuite_DEFAULT,
		ThreatModel:    ts.ThreatModel_REMOTE,
		StagedConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	err := s.PromoteCodeqlConfigToCurrent(ctx, config, repoID, nil)
	require.NoError(t, err)

	// Check that the codeql repo was updated
	out := &ts.CodeqlRepo{}
	err = db.First(out, "repository_id = ?", codeqlRepo.RepositoryID).Error
	require.NoError(t, err)
	require.Equal(t, config.QuerySuiteType.Root(), out.QuerySuite)
	require.Equal(t, config.ThreatModel, out.ThreatModel)
	require.Equal(t, config.ID, *out.CurrentConfigID)
	require.Nil(t, out.StagedConfigID)
}

func TestPromoteCodeqlConfigToCurrent_UpdatesCodeqlRepoWithCurrentConfig(t *testing.T) {
	db, s, ctx := testSetup(t)

	// create other repo that should not change
	otherCurrentConfig := baseCodeqlConfig()
	otherCurrentConfig.RepositoryID = repoID + 1
	otherCurrentConfig.MakeCurrent()
	dbtest.RequireCreate(t, db, otherCurrentConfig)
	otherCodeqlRepo := &ts.CodeqlRepo{
		RepositoryID:    repoID + 1,
		QuerySuite:      ts.QuerySuite_DEFAULT,
		ThreatModel:     ts.ThreatModel_REMOTE,
		CurrentConfigID: &otherCurrentConfig.ID,
	}
	dbtest.RequireCreate(t, db, otherCodeqlRepo)

	// setup
	currentConfig := baseCodeqlConfig()
	currentConfig.MakeCurrent()
	dbtest.RequireCreate(t, db, currentConfig)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: currentConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	})

	stagedConfig := baseCodeqlConfig()
	stagedConfig.QuerySuiteType = ts.ExtendedQuerySuiteType()
	stagedConfig.ThreatModel = ts.ThreatModel_REMOTE_LOCAL
	stagedConfig.MakeStaged()
	dbtest.RequireCreate(t, db, stagedConfig)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: stagedConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:    repoID,
		QuerySuite:      ts.QuerySuite_DEFAULT,
		ThreatModel:     ts.ThreatModel_REMOTE,
		CurrentConfigID: &currentConfig.ID,
		StagedConfigID:  &stagedConfig.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	err := s.PromoteCodeqlConfigToCurrent(ctx, stagedConfig, repoID, nil)
	require.NoError(t, err)

	// Check that the codeql repo was updated
	out := &ts.CodeqlRepo{}
	err = db.First(out, "repository_id = ?", codeqlRepo.RepositoryID).Error
	require.NoError(t, err)
	require.Equal(t, stagedConfig.QuerySuiteType.Root(), out.QuerySuite)
	require.Equal(t, stagedConfig.ThreatModel, out.ThreatModel)
	require.Equal(t, stagedConfig.ID, *out.CurrentConfigID)
	require.Nil(t, out.StagedConfigID)
	require.Nil(t, out.FailedConfigID)

	// Check that otherRepo was not changed
	out2 := &ts.CodeqlRepo{}
	err = db.First(out2, "repository_id = ?", otherCodeqlRepo.RepositoryID).Error
	require.NoError(t, err)
	require.Equal(t, otherCodeqlRepo.CurrentConfigID, out2.CurrentConfigID)
	require.Equal(t, otherCodeqlRepo.StagedConfigID, out2.StagedConfigID)
}

func TestDeprecateStagedCodeqlConfig_RunFailed(t *testing.T) {
	db, s, ctx := testSetup(t)

	// Create the staged config and link it to the CodeqlRepo
	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})

	err := s.CreateCodeqlRepo(ctx, &ts.CodeqlRepo{RepositoryID: repoID})
	require.NoError(t, err)
	codeqlRepo, err := s.GetCodeqlRepo(ctx, repoID) // CreatCodeqlRepo does not set the ID, so we need to fetch it again.
	require.NoError(t, err)
	codeqlRepo.StagedConfigID = &config.ID
	err = s.UpdateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	runFailed := ts.CodeqlRunStatus_FAILED
	err = s.DeprecateStagedCodeqlConfig(ctx, repoID, config.ID, &runFailed)
	require.NoError(t, err)

	outConfig, err := getCurrentConfig(ctx, s, repoID)
	require.NoError(t, err)
	require.Nil(t, outConfig)

	out := &ts.CodeqlConfig{}
	err = db.Where("id = ?", config.ID).First(&out).Error
	require.NoError(t, err)
	require.Equal(t, &runFailed, out.ValidationRunStatus)
	require.NotNil(t, out.DeprecatedAt)
}

func TestDeprecateStagedCodeqlConfig_RunFailedUpdatesCodeqlRepo(t *testing.T) {
	db, s, ctx := testSetup(t)

	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	dbtest.RequireCreate(t, db, &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
	})

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:   repoID,
		QuerySuite:     ts.QuerySuite_DEFAULT,
		ThreatModel:    ts.ThreatModel_REMOTE,
		StagedConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	runFailed := ts.CodeqlRunStatus_FAILED
	err := s.DeprecateStagedCodeqlConfig(ctx, repoID, config.ID, &runFailed)
	require.NoError(t, err)

	outConfig, err := getCurrentConfig(ctx, s, repoID)
	require.NoError(t, err)
	require.Nil(t, outConfig)

	out := &ts.CodeqlConfig{}
	err = db.Where("id = ?", config.ID).First(&out).Error
	require.NoError(t, err)
	require.Equal(t, &runFailed, out.ValidationRunStatus)
	require.NotNil(t, out.DeprecatedAt)

	// Check that the codeql repo was updated
	outCodeqlRepo := &ts.CodeqlRepo{}
	err = db.First(outCodeqlRepo, "repository_id = ?", codeqlRepo.RepositoryID).Error
	require.NoError(t, err)
	require.Equal(t, config.ID, *outCodeqlRepo.FailedConfigID)
	require.Nil(t, outCodeqlRepo.StagedConfigID)
}

func TestCreateCodeqlRun(t *testing.T) {
	_, s, ctx := testSetup(t)

	run := &ts.CodeqlRun{
		RepositoryID:  repoID,
		ActorLogin:    "actor",
		Workflow:      "some workflow",
		Ref:           []byte("refs/heads/main"),
		WorkflowRunID: 123,
	}

	err := s.CreateCodeqlRun(ctx, run)
	require.NoError(t, err)
	require.True(t, run.ID > 0)

	// Only one CodeQlRun per WorkflowRunID. Trying to recreate the record should fail.
	run.ID = 0
	err = s.CreateCodeqlRun(ctx, run)
	require.Error(t, err)
}

func TestCreateCodeqlRunBelongsToConfig(t *testing.T) {
	db, s, ctx := testSetup(t)

	err := s.CreateCodeqlRepo(ctx, &ts.CodeqlRepo{RepositoryID: repoID})
	require.NoError(t, err)

	config := baseCodeqlConfig().MakeStaged()
	err = s.CreateStagedCodeqlConfig(ctx, config)
	require.NoError(t, err)

	config = &ts.CodeqlConfig{}
	err = db.Where("repository_id = ?", repoID).First(&config).Error
	require.NoError(t, err)

	run := &ts.CodeqlRun{
		RepositoryID:  repoID,
		ActorLogin:    "actor",
		Workflow:      "some workflow",
		Ref:           []byte("refs/heads/main"),
		WorkflowRunID: 123,
		Config:        config,
		RunType:       ts.CodeqlRunType_STEADY,
	}

	err = s.CreateCodeqlRun(ctx, run)
	require.NoError(t, err)
	require.True(t, run.ID > 0)

	var runs []*ts.CodeqlRun
	err = db.Where("repository_id = ? AND workflow_run_id = ?", repoID, run.WorkflowRunID).Preload("Config").Find(&runs).Error
	require.NoError(t, err)
	run = runs[0]
	require.Equal(t, config.ID, run.CodeqlConfigID)
	require.Equal(t, config.ID, run.Config.ID)
}

func TestGetCodelqlRun(t *testing.T) {
	db, s, ctx := testSetup(t)

	_, err := s.GetCodeqlRun(ctx, repoID, actionsWorkflowRunID)
	require.Error(t, err)
	require.ErrorIs(t, err, ts.ErrCodeqlRunNotFound)

	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)

	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		WorkflowRunID:  actionsWorkflowRunID,
		ExecutionID:    executionID,
		Status:         ts.CodeqlRunStatus_INPROGRESS,
		CodeqlConfigID: config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	run, err = s.GetCodeqlRun(ctx, repoID, actionsWorkflowRunID)
	require.NoError(t, err)
	require.Equal(t, repoID, run.RepositoryID)
	require.Equal(t, actionsWorkflowRunID, run.WorkflowRunID)
	require.NotNil(t, run.Config)
}

func TestGetCodeqlRunByShaAndRef(t *testing.T) {
	db, s, ctx := testSetup(t)

	_, err := s.GetCodeqlRunByShaAndRef(ctx, repoID, "unknown", []byte("foo"))
	require.Error(t, err)
	require.ErrorIs(t, err, ts.ErrCodeqlRunNotFound)

	run := &ts.CodeqlRun{
		RepositoryID:  repoID,
		WorkflowRunID: actionsWorkflowRunID,
		ExecutionID:   executionID,
		Status:        ts.CodeqlRunStatus_INPROGRESS,
		Sha:           "123456",
		Ref:           []byte("foo"),
	}
	dbtest.RequireCreate(t, db, run)

	run, err = s.GetCodeqlRunByShaAndRef(ctx, repoID, "123456", []byte("foo"))
	require.NoError(t, err)
	require.Equal(t, repoID, run.RepositoryID)
	require.Equal(t, ts.Sha("123456"), run.Sha)

	_, err = s.GetCodeqlRunByShaAndRef(ctx, repoID, "123456", []byte("other"))
	require.Error(t, err)
	require.ErrorIs(t, err, ts.ErrCodeqlRunNotFound)

	_, err = s.GetCodeqlRunByShaAndRef(ctx, repoID, "888888", []byte("foo"))
	require.Error(t, err)
	require.ErrorIs(t, err, ts.ErrCodeqlRunNotFound)
}

func TestGetMostRecentFailedCodeqlRun_DeprecatedConfig(t *testing.T) {
	db, s, ctx := testSetup(t)

	config := baseCodeqlConfig().Deprecate()
	dbtest.RequireCreate(t, db, config)

	run1 := &ts.CodeqlRun{
		RepositoryID:  repoID,
		WorkflowRunID: 125,
		ExecutionID:   executionID,
		Status:        ts.CodeqlRunStatus_COMPLETED,
	}
	dbtest.RequireCreate(t, db, run1)

	run2 := &ts.CodeqlRun{
		RepositoryID:  repoID,
		WorkflowRunID: actionsWorkflowRunID,
		ExecutionID:   executionID,
		Status:        ts.CodeqlRunStatus_FAILED,
	}
	dbtest.RequireCreate(t, db, run2)

	run, err := s.GetMostRecentCodeqlRun(ctx, repoID, config)
	require.NoError(t, err)
	require.Equal(t, ts.CodeqlRunStatus_FAILED, run.Status)
	require.Equal(t, actionsWorkflowRunID, run.WorkflowRunID)

	run3 := &ts.CodeqlRun{
		RepositoryID:  repoID,
		WorkflowRunID: 126,
		ExecutionID:   executionID,
		Status:        ts.CodeqlRunStatus_INPROGRESS,
	}
	dbtest.RequireCreate(t, db, run3)

	run, err = s.GetMostRecentCodeqlRun(ctx, repoID, config)
	require.NoError(t, err)
	require.Equal(t, ts.CodeqlRunStatus_INPROGRESS, run.Status)
	require.Equal(t, ts.WorkflowRunEID(126), run.WorkflowRunID)
}

func TestGetMostRecentFailedCodeqlRun_CurrentConfig(t *testing.T) {
	db, s, ctx := testSetup(t)

	currentConfig := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, currentConfig)

	run1 := &ts.CodeqlRun{
		RepositoryID:   repoID,
		WorkflowRunID:  125,
		ExecutionID:    executionID,
		Status:         ts.CodeqlRunStatus_COMPLETED,
		CodeqlConfigID: currentConfig.ID,
	}
	dbtest.RequireCreate(t, db, run1)

	run2 := &ts.CodeqlRun{
		RepositoryID:  repoID,
		WorkflowRunID: actionsWorkflowRunID,
		ExecutionID:   executionID,
		Status:        ts.CodeqlRunStatus_FAILED,
	}
	dbtest.RequireCreate(t, db, run2)

	// even though run1 is not the overall latest it's returned
	// because we specified its config as an argument
	run, err := s.GetMostRecentCodeqlRun(ctx, repoID, currentConfig)
	require.NoError(t, err)
	require.Equal(t, run1.ID, run.ID)

	deprecatedConfig := baseCodeqlConfig().Deprecate()
	dbtest.RequireCreate(t, db, deprecatedConfig)

	run, err = s.GetMostRecentCodeqlRun(ctx, repoID, deprecatedConfig)
	require.NoError(t, err)
	require.Equal(t, run2.ID, run.ID)
}

func TestGetPotentiallyOnboardedRepositoryIDs(t *testing.T) {
	db, s, ctx := testSetup(t)

	out, _, err := s.GetPotentiallyOnboardedRepositoryIDs(ctx, nil)
	require.NoError(t, err)
	require.Empty(t, out)

	configs := []*ts.CodeqlConfig{
		(&ts.CodeqlConfig{RepositoryID: 1, Languages: ts.Languages{"javascript"}}).MakeCurrent(),
		(&ts.CodeqlConfig{RepositoryID: 2, Languages: ts.Languages{"javascript"}}).MakeStaged(),
		(&ts.CodeqlConfig{RepositoryID: 3, Languages: ts.Languages{"javascript"}}).Deprecate(),
		(&ts.CodeqlConfig{RepositoryID: 4, Languages: ts.Languages{"python", "java"}}).MakeCurrent(),
	}

	for _, config := range configs {
		config.InitialLanguages = config.Languages
		dbtest.RequireCreate(t, db, config)
		require.NoError(t, err)
	}
	minuteAgo := time.Now().Add(-1 * time.Minute).UTC()
	dbtest.RequireUpdatedAt(t, db.Model(&ts.CodeqlConfig{}), minuteAgo)

	out, updatedAt, err := s.GetPotentiallyOnboardedRepositoryIDs(ctx, nil)
	require.NoError(t, err)
	require.Equal(t, 3, len(out))
	require.Contains(t, out, ts.RepositoryEID(1))
	require.Contains(t, out, ts.RepositoryEID(4))
	// We need to deal with the MySQL truncation to the microsecond (us)
	require.Equal(t, minuteAgo.Truncate(sqltime.TruncateOff), *updatedAt)

	// Test filtering by updated_at
	dbtest.RequireUpdatedAt(t, db.Model(&ts.CodeqlConfig{}).Where("id=?", configs[0].ID), time.Now())

	since := minuteAgo.Add(1 * time.Second)
	out, updatedAt, err = s.GetPotentiallyOnboardedRepositoryIDs(ctx, &since)
	require.NoError(t, err)
	require.Equal(t, 1, len(out))
	require.Greater(t, *updatedAt, since)
}

func TestGetPotentiallyOnboardedRepositoryIDs_Pagination(t *testing.T) {
	db, s, ctx := testSetup(t)

	for i := 1; i < 22; i++ {
		dbtest.RequireCreate(t, db, (&ts.CodeqlConfig{RepositoryID: ts.RepositoryEID(i)}).MakeCurrent())
	}

	out, _, err := s.getPotentiallyOnboardedRepositoryIDs(ctx, nil, 10)
	require.NoError(t, err)
	require.Len(t, out, 21)

	out, _, err = s.getPotentiallyOnboardedRepositoryIDs(ctx, nil, 100)
	require.NoError(t, err)
	require.Len(t, out, 21)
}

func TestPreviousRunExists(t *testing.T) {
	db, s, ctx := testSetup(t)

	config := baseCodeqlConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)

	run := &ts.CodeqlRun{
		RepositoryID:  repoID,
		WorkflowRunID: 125,
		ExecutionID:   executionID,
		Sha:           "sha-123",
		Ref:           ts.Ref("refs/heads/main"),
	}

	exists, err := s.PreviousRunExists(ctx, run.RepositoryID, run.Sha, run.Ref)
	require.NoError(t, err)
	require.False(t, exists)

	// Create the run
	dbtest.RequireCreate(t, db, run)

	exists, err = s.PreviousRunExists(ctx, run.RepositoryID, run.Sha, run.Ref)
	require.NoError(t, err)
	require.True(t, exists)

	exists, err = s.PreviousRunExists(ctx, run.RepositoryID, run.Sha, ts.Ref("refs/heads/other"))
	require.NoError(t, err)
	require.False(t, exists)
}

func TestGetPendingRunsForRef(t *testing.T) {
	db, s, ctx := testSetup(t)

	repoID := ts.RepositoryEID(12)
	ref := []byte("ref")

	dbtest.RequireCreate(t, db,
		&ts.CodeqlRun{
			RepositoryID:  repoID,
			Ref:           ref,
			Sha:           "111",
			Status:        ts.CodeqlRunStatus_INPROGRESS,
			WorkflowRunID: 1,
			BaseModel: ts.BaseModel{
				CreatedAt: sqltime.Time{Time: time.Now().Add(-1 * time.Hour)},
			},
		},
	)
	dbtest.RequireCreate(t, db,
		&ts.CodeqlRun{
			RepositoryID:  repoID,
			Ref:           ref,
			Sha:           "222",
			Status:        ts.CodeqlRunStatus_INPROGRESS,
			WorkflowRunID: 2,
			BaseModel: ts.BaseModel{
				CreatedAt: sqltime.Time{Time: time.Now().Add(-5 * time.Minute)},
			},
		},
	)

	runs, err := s.GetPendingRunsForRef(ctx, repoID, ref, time.Now().Add(-10*time.Minute))
	require.NoError(t, err)
	require.Equal(t, 1, len(runs))
	require.Equal(t, ts.Sha("111"), runs[0].Sha)
}

func TestGetStaleValidationRuns(t *testing.T) {
	db, s, ctx := testSetup(t)

	// No error should be returned if there are no stale runs
	runs, err := s.GetStaleValidationRuns(ctx, nil, 60*time.Minute, 100)
	require.NoError(t, err)
	require.Equal(t, 0, len(runs))

	// IN_PROGRESS validation run that hasn't been updated in the last hour => stale
	dbtest.RequireCreate(t, db,
		&ts.CodeqlRun{
			RepositoryID:  1,
			RunType:       ts.CodeqlRunType_VALIDATION,
			Status:        ts.CodeqlRunStatus_INPROGRESS,
			WorkflowRunID: 1,
			BaseModel: ts.BaseModel{
				UpdatedAt: sqltime.Time{Time: time.Now().Add(-61 * time.Minute)},
			},
		},
	)

	// FAILED run validation that hasn't been updated in the last hour => not stale
	dbtest.RequireCreate(t, db,
		&ts.CodeqlRun{
			RepositoryID:  2,
			RunType:       ts.CodeqlRunType_VALIDATION,
			Status:        ts.CodeqlRunStatus_FAILED,
			WorkflowRunID: 2,
			BaseModel: ts.BaseModel{
				UpdatedAt: sqltime.Time{Time: time.Now().Add(-120 * time.Minute)},
			},
		},
	)

	// PENDING validation run that has been updated in the last hour => not stale
	dbtest.RequireCreate(t, db,
		&ts.CodeqlRun{
			RepositoryID:  3,
			RunType:       ts.CodeqlRunType_VALIDATION,
			Status:        ts.CodeqlRunStatus_PENDING,
			WorkflowRunID: 3,
			BaseModel: ts.BaseModel{
				UpdatedAt: sqltime.Time{Time: time.Now().Add(-5 * time.Minute)},
			},
		},
	)

	// PENDING validation run that hasn't been updated in the last hour => stale
	dbtest.RequireCreate(t, db,
		&ts.CodeqlRun{
			RepositoryID:  3,
			RunType:       ts.CodeqlRunType_VALIDATION,
			Status:        ts.CodeqlRunStatus_PENDING,
			WorkflowRunID: 4,
			BaseModel: ts.BaseModel{
				UpdatedAt: sqltime.Time{Time: time.Now().Add(-120 * time.Minute)},
			},
		},
	)

	// PENDING non-validation run that hasn't been updated in the last hour => not stale
	dbtest.RequireCreate(t, db,
		&ts.CodeqlRun{
			RepositoryID:  3,
			RunType:       ts.CodeqlRunType_STEADY,
			Status:        ts.CodeqlRunStatus_PENDING,
			WorkflowRunID: 5,
			BaseModel: ts.BaseModel{
				UpdatedAt: sqltime.Time{Time: time.Now().Add(-120 * time.Minute)},
			},
		},
	)

	// Check that the limit is respected
	runs, err = s.GetStaleValidationRuns(ctx, nil, 60*time.Minute, 0)
	require.NoError(t, err)
	require.Equal(t, 0, len(runs))

	runs, err = s.GetStaleValidationRuns(ctx, nil, 60*time.Minute, 1)
	require.NoError(t, err)
	require.Equal(t, 1, len(runs))

	// Check that the correct runs are returned
	runs, err = s.GetStaleValidationRuns(ctx, nil, 60*time.Minute, 100)
	require.NoError(t, err)
	require.Equal(t, 2, len(runs))
	workflowIDs := []ts.WorkflowRunEID{runs[0].WorkflowRunID, runs[1].WorkflowRunID}
	require.Contains(t, workflowIDs, ts.WorkflowRunEID(1))
	require.Contains(t, workflowIDs, ts.WorkflowRunEID(4))

	// Check that the results are filtered by repoID when provided
	repoID := ts.RepositoryEID(3)
	runs, err = s.GetStaleValidationRuns(ctx, &repoID, 60*time.Minute, 100)
	require.NoError(t, err)
	require.Equal(t, 1, len(runs))
	require.Equal(t, ts.WorkflowRunEID(4), runs[0].WorkflowRunID)
}

func TestGetCodeqlRepo(t *testing.T) {
	db, s, ctx := testSetup(t)

	repoID := ts.RepositoryEID(1)

	// Repo was never enabled
	_, err := s.GetCodeqlRepo(ctx, repoID)
	require.ErrorIs(t, err, ts.ErrCodeqlRepoNotFound)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:        repoID,
		SupportedLanguages:  []string{"python", "ruby"},
		QuerySuite:          ts.QuerySuite_EXTENDED,
		ThreatModel:         ts.ThreatModel_REMOTE,
		EnabledByActorLogin: "actor",
		RepositoryGRID:      ts.RepositoryGRID("asdf"),
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	out, err := s.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	require.Equal(t, 2, len(out.SupportedLanguages))
	require.Equal(t, ts.QuerySuite_EXTENDED, out.QuerySuite)
	require.Equal(t, ts.ThreatModel_REMOTE, out.ThreatModel)

	// Disabled repo
	now := sqltime.Now()
	codeqlRepo.SoftDeletedAt = &now
	err = db.Save(codeqlRepo).Error
	require.NoError(t, err)

	_, err = s.GetCodeqlRepo(ctx, repoID)
	require.ErrorIs(t, err, ts.ErrCodeqlRepoNotFound)
}

func TestGetMostRecentCodeqlConfig_Preloading(t *testing.T) {
	db, s, ctx := testSetup(t)

	// Error if lacking a validation run - Staged
	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:   repoID,
		StagedConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	_, err := s.GetCodeqlRepo(ctx, repoID)
	require.Error(t, err)
	require.ErrorIs(t, err, ts.ErrCodeqlRunNotFound)

	// Error if lacking a validation run - Current
	config.MakeCurrent()
	require.NoError(t, db.Save(config).Error)
	codeqlRepo.CurrentConfigID = &config.ID
	codeqlRepo.StagedConfigID = nil
	require.NoError(t, db.Save(codeqlRepo).Error)

	_, err = s.GetCodeqlRepo(ctx, repoID)
	require.Error(t, err)
	require.ErrorIs(t, err, ts.ErrCodeqlRunNotFound)

	// Create a validation run for the config
	validationRun := &ts.CodeqlRun{
		RepositoryID:   repoID,
		WorkflowRunID:  1,
		CodeqlConfigID: config.ID,
		Status:         ts.CodeqlRunStatus_INPROGRESS,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, validationRun)

	steadyRun := &ts.CodeqlRun{
		RepositoryID:   repoID,
		WorkflowRunID:  2,
		CodeqlConfigID: config.ID,
		Status:         ts.CodeqlRunStatus_COMPLETED,
		RunType:        ts.CodeqlRunType_STEADY,
	}
	dbtest.RequireCreate(t, db, steadyRun)

	// Check for staged
	config.MakeStaged()
	require.NoError(t, db.Save(config).Error)
	codeqlRepo.StagedConfigID = &config.ID
	codeqlRepo.CurrentConfigID = nil
	require.NoError(t, db.Save(codeqlRepo).Error)

	repo, err := s.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	require.Equal(t, validationRun.ID, repo.StagedConfig.ValidationRun.ID)

	// Check for current
	config.MakeCurrent()
	require.NoError(t, db.Save(config).Error)
	codeqlRepo.CurrentConfigID = &config.ID
	codeqlRepo.StagedConfigID = nil
	require.NoError(t, db.Save(codeqlRepo).Error)

	repo, err = s.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	require.Equal(t, validationRun.ID, repo.CurrentConfig.ValidationRun.ID)
}

func TestCreateCodeqlSchedule(t *testing.T) {
	db, s, ctx := testSetup(t)

	time1 := sqltime.Now()
	err := s.CreateCodeqlSchedule(ctx, repoID, time1.Time)
	require.NoError(t, err)

	var schedule ts.CodeqlSchedule
	err = db.Where("repository_id = ?", repoID).First(&schedule).Error
	require.NoError(t, err)
	require.Equal(t, time1, schedule.NextRunAt)

	// CreateCodeqlSchedule should update the nextRunAt if an entry already exists
	time2 := sqltime.Time{Time: sqltime.Now().Add(time.Minute * time.Duration(5))}
	err = s.CreateCodeqlSchedule(ctx, repoID, time2.Time)
	require.NoError(t, err)

	var schedule2 ts.CodeqlSchedule
	err = db.Where("repository_id = ?", repoID).First(&schedule2).Error
	require.NoError(t, err)
	require.Equal(t, time2, schedule2.NextRunAt)
}

func TestGetRunnableCodeqlSchedules(t *testing.T) {
	db, s, ctx := testSetup(t)

	repo1ID := repoID
	repo2ID := repoID + 1
	repo3ID := repoID + 2
	repo4ID := repoID + 3
	currentTag := ts.CodeqlConfigTag_CURRENT

	var data = []struct {
		RepoID    ts.RepositoryEID
		ConfigTag *ts.CodeqlConfigTag
		NextRunAt sqltime.Time
	}{
		{repo1ID, &currentTag, sqltime.Time{Time: time.Now().Add(time.Minute * time.Duration(-1))}},  // First repo, just a current config
		{repo2ID, &currentTag, sqltime.Time{Time: time.Now().Add(time.Minute * time.Duration(-10))}}, // Second repo, older nextRunAt
		{repo3ID, nil, sqltime.Time{Time: time.Now().Add(time.Minute * time.Duration(-1))}},          // Third repo, no active config
		{repo4ID, &currentTag, sqltime.Time{Time: time.Now().Add(time.Minute * time.Duration(10))}},  // Forth repo, not yet runnable
	}

	for _, entry := range data {
		config := &ts.CodeqlConfig{
			RepositoryID:         entry.RepoID,
			RepositoryGRID:       "123456",
			OnboardedByActorGRID: "123abc",
			CreatedByActorLogin:  "abc",
			Languages:            []string{"ruby"},
			InitialLanguages:     []string{"ruby"},
			TemplateVersion:      workflowTemplateVersion,
			Tag:                  entry.ConfigTag,
		}
		dbtest.RequireCreate(t, db, config)

		schedule := &ts.CodeqlSchedule{
			RepositoryID: entry.RepoID,
			NextRunAt:    entry.NextRunAt,
		}
		dbtest.RequireCreate(t, db, schedule)
	}

	schedules, err := s.GetRunnableCodeqlSchedules(ctx)
	require.NoError(t, err)
	require.Equal(t, 2, len(schedules))
	require.Equal(t, repo2ID, schedules[0].RepositoryID) // Repo2 should be first as it is "older"
	require.Equal(t, repo1ID, schedules[1].RepositoryID)
}

func TestHadNonScheduledRunsAfter(t *testing.T) {
	db, s, ctx := testSetup(t)
	deadline := time.Now()
	repo1ID := repoID
	repo2ID := repoID + 1

	var data = []struct {
		RepoID    ts.RepositoryEID
		CreatedAt time.Time
		Event     ts.CodeqlRunTriggeringEvent
	}{
		// Repo 1 had only a scheduled run after the deadline
		{repo1ID, deadline.Add(5 * time.Hour), ts.CodeqlRunTriggeringEvent_SCHEDULED},
		{repo1ID, deadline.Add(-5 * time.Hour), ts.CodeqlRunTriggeringEvent_PUSH},
		// Repo 2 had only a validation run after the deadline
		{repo2ID, deadline.Add(5 * time.Hour), ts.CodeqlRunTriggeringEvent_VALIDATION},
	}

	for idx, entry := range data {
		run := &ts.CodeqlRun{
			RepositoryID:    entry.RepoID,
			TriggeringEvent: entry.Event,
			WorkflowRunID:   ts.WorkflowRunEID(idx),
		}
		dbtest.RequireCreate(t, db, run)
		query := db.Table("ts_codeql_runs").Where("id = ?", run.ID)
		err := query.UpdateColumn("created_at", sqltime.Time{Time: entry.CreatedAt}).Error
		require.NoError(t, err)
	}

	isActive, err := s.HadNonScheduledRunsAfter(ctx, []ts.RepositoryEID{repo1ID, repo2ID}, deadline)
	require.NoError(t, err)
	require.Equal(t, 1, len(isActive))

	// Repo 1 should return false as it had only a scheduled run after the deadline
	require.False(t, isActive[repo1ID])
	// Repo 2 should return true as it had a non-scheduled run after the deadline
	require.True(t, isActive[repo2ID])
}

func TestCanAttemptJITValidation(t *testing.T) {
	db, s, ctx := testSetup(t)

	failedStatus := ts.CodeqlRunStatus_FAILED
	recencyWindow := time.Hour * 48
	overallLimit := 2

	ok, err := s.CanAttemptJITValidation(ctx, repoID, workflowTemplateVersion, overallLimit, recencyWindow)
	require.NoError(t, err)
	require.True(t, ok)

	// if there is a validation run in progress we return false
	config := baseCodeqlConfig().MakeStaged()
	config.ValidationRunStatus = nil
	dbtest.RequireCreate(t, db, config)
	ok, err = s.CanAttemptJITValidation(ctx, repoID, workflowTemplateVersion, overallLimit, recencyWindow)
	require.NoError(t, err)
	require.False(t, ok)

	// cancelled runs are not counted here
	config = config.Deprecate()
	cancelledStatus := ts.CodeQlRunStatus_CANCELLED
	config.ValidationRunStatus = &cancelledStatus
	require.NoError(t, db.Save(config).Error)
	ok, err = s.CanAttemptJITValidation(ctx, repoID, workflowTemplateVersion, overallLimit, recencyWindow)
	require.NoError(t, err)
	require.True(t, ok)

	// now we create a config with a failed validation run
	failed_config := baseCodeqlConfig().Deprecate()
	failed_config.ValidationRunStatus = &failedStatus
	dbtest.RequireCreate(t, db, failed_config)

	// this fails because the new config (failed_config) is in the recency window
	ok, err = s.CanAttemptJITValidation(ctx, repoID, workflowTemplateVersion, overallLimit, recencyWindow)
	require.NoError(t, err)
	require.False(t, ok)

	// the template version must match
	ok, err = s.CanAttemptJITValidation(ctx, repoID, "a different version", overallLimit, recencyWindow)
	require.NoError(t, err)
	require.True(t, ok)

	// also the repository
	ok, err = s.CanAttemptJITValidation(ctx, repoID+1, workflowTemplateVersion, overallLimit, recencyWindow)
	require.NoError(t, err)
	require.True(t, ok)

	// the window is taken into account
	smallerWindow := time.Millisecond * 1
	ok, err = s.CanAttemptJITValidation(ctx, repoID, workflowTemplateVersion, overallLimit, smallerWindow)
	require.NoError(t, err)
	require.True(t, ok)

	// and the overall limit too
	smallerLimit := 1
	ok, err = s.CanAttemptJITValidation(ctx, repoID, workflowTemplateVersion, smallerLimit, smallerWindow)
	require.NoError(t, err)
	require.False(t, ok)
}

func TestIsEnabled(t *testing.T) {
	db, s, ctx := testSetup(t)

	repoID := ts.RepositoryEID(1)

	// No entries in the DB
	enabled, err := s.IsEnabled(ctx, repoID)
	require.NoError(t, err)
	require.False(t, enabled)

	// Waiting state
	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID: repoID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	enabled, err = s.IsEnabled(ctx, repoID)
	require.NoError(t, err)
	require.True(t, enabled)

	// Onboarding
	stagedTag := ts.CodeqlConfigTag_STAGED
	config := &ts.CodeqlConfig{
		RepositoryID: repoID,
		Tag:          &stagedTag,
	}
	dbtest.RequireCreate(t, db, config)
	codeqlRepo.StagedConfigID = &config.ID
	err = db.Save(codeqlRepo).Error
	require.NoError(t, err)

	enabled, err = s.IsEnabled(ctx, repoID)
	require.NoError(t, err)
	require.True(t, enabled)

	// Stable
	currentTag := ts.CodeqlConfigTag_CURRENT
	config.Tag = &currentTag
	err = db.Save(config).Error
	require.NoError(t, err)

	codeqlRepo.CurrentConfigID = &config.ID
	codeqlRepo.StagedConfigID = nil
	err = db.Save(codeqlRepo).Error
	require.NoError(t, err)

	enabled, err = s.IsEnabled(ctx, repoID)
	require.NoError(t, err)
	require.True(t, enabled)

	// Offboarded
	config.Tag = nil
	err = db.Save(config).Error
	require.NoError(t, err)

	codeqlRepo.CurrentConfigID = nil
	err = db.Save(codeqlRepo).Error
	require.NoError(t, err)

	enabled, err = s.IsEnabled(ctx, repoID)
	require.NoError(t, err)
	require.True(t, enabled)

	// Disabled
	err = s.DeleteCodeqlRepo(ctx, repoID)
	require.NoError(t, err)

	enabled, err = s.IsEnabled(ctx, repoID)
	require.NoError(t, err)
	require.False(t, enabled)
}

func TestGetDisabledTime(t *testing.T) {
	db, s, ctx := testSetup(t)

	repoID := ts.RepositoryEID(1)

	// No entries in the DB
	disabledTime, err := s.GetDisabledTime(ctx, repoID)
	require.NoError(t, err)
	require.Nil(t, disabledTime)

	// Enabled codeqlRepo
	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID: repoID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	disabledTime, err = s.GetDisabledTime(ctx, repoID)
	require.NoError(t, err)
	require.Nil(t, disabledTime)

	// Disabled codeqlRepo
	codeqlRepo.SoftDeletedAt = &sqltime.Time{Time: time.Now().UTC().Truncate(sqltime.TruncateOff)}
	err = db.Save(codeqlRepo).Error
	require.NoError(t, err)

	disabledTime, err = s.GetDisabledTime(ctx, repoID)
	require.NoError(t, err)
	require.Equal(t, codeqlRepo.SoftDeletedAt.Time, *disabledTime)
}

func TestCreateCodeqlRepo_SkipAssociations(t *testing.T) {
	db, s, ctx := testSetup(t)
	config := baseCodeqlConfig()
	dbtest.RequireCreate(t, db, config)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID: 1,
	}
	// Setting any ID fails
	codeqlRepo.CurrentConfigID = &config.ID
	err := s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.Error(t, err)

	codeqlRepo.CurrentConfigID = nil
	codeqlRepo.StagedConfigID = &config.ID
	err = s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.Error(t, err)

	codeqlRepo.StagedConfigID = nil
	codeqlRepo.FailedConfigID = &config.ID
	err = s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.Error(t, err)

	// Setting any association fails
	codeqlRepo.CurrentConfig = config
	err = s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.Error(t, err)

	codeqlRepo.CurrentConfig = nil
	codeqlRepo.StagedConfig = config
	err = s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.Error(t, err)

	codeqlRepo.StagedConfig = nil
	codeqlRepo.FailedConfig = config
	err = s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.Error(t, err)
}

func TestOmitUsingCombinedLanguages(t *testing.T) {
	_, s, ctx := testSetup(t)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:           1,
		UsingCombinedLanguages: false,
	}
	err := s.CreateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	// This should have been saved with UsingCombinedLanguages set to true
	outRepo1, err := s.GetCodeqlRepo(ctx, codeqlRepo.RepositoryID)
	require.NoError(t, err)
	require.True(t, outRepo1.UsingCombinedLanguages)

	// Also calling update should not change the value
	codeqlRepo.UsingCombinedLanguages = false
	err = s.UpdateCodeqlRepo(ctx, codeqlRepo)
	require.NoError(t, err)

	outRepo2, err := s.GetCodeqlRepo(ctx, codeqlRepo.RepositoryID)
	require.NoError(t, err)
	require.True(t, outRepo2.UsingCombinedLanguages)
}

func TestGetRepositoriesDisabledBetween(t *testing.T) {
	db, s, ctx := testSetup(t)

	repo1 := &ts.CodeqlRepo{
		RepositoryID:  repoID,
		SoftDeletedAt: nil,
	}
	dbtest.RequireCreate(t, db, repo1)

	beforeNow := sqltime.Time{Time: sqltime.Now().Add(-1 * time.Hour)}
	repo2 := &ts.CodeqlRepo{
		RepositoryID:  repoID + 1,
		SoftDeletedAt: &beforeNow,
	}
	dbtest.RequireCreate(t, db, repo2)

	afterNow := sqltime.Time{Time: sqltime.Now().Add(1 * time.Hour)}
	repo3 := &ts.CodeqlRepo{
		RepositoryID:  repoID + 2,
		SoftDeletedAt: &afterNow,
	}
	dbtest.RequireCreate(t, db, repo3)

	afterT2 := sqltime.Time{Time: sqltime.Now().Add(24 * time.Hour)}
	repo4 := &ts.CodeqlRepo{
		RepositoryID:  repoID + 3,
		SoftDeletedAt: &afterT2,
	}
	dbtest.RequireCreate(t, db, repo4)

	out, err := s.GetRepositoriesDisabledBetween(ctx, time.Now(), time.Now().Add(time.Hour*2))
	require.NoError(t, err)
	require.Equal(t, 1, len(out))
	require.Equal(t, repo3.RepositoryID, out[0].RepositoryID)
	require.Equal(t, *repo3.SoftDeletedAt, out[0].DisabledAt)
}

func TestCodeQLRunEventPublishedOnCreateAndUpdate(t *testing.T) {
	db, _, ctx := testSetup(t)

	mockCtrl := gomock.NewController(t)
	pub := mocks.NewMockCodeqlRunPublisher(mockCtrl)
	s := NewService(db, pub)

	run := &ts.CodeqlRun{
		RepositoryID:  repoID,
		ActorLogin:    "actor",
		Workflow:      "some workflow",
		Ref:           []byte("refs/heads/main"),
		WorkflowRunID: 123,
	}

	expectedEvent := &oldtshydro.CodeqlRun{
		RepositoryId:    uint64(repoID),
		ActorLogin:      "actor",
		Workflow:        "some workflow",
		Ref:             []byte("refs/heads/main"),
		WorkflowRunId:   uint64(123),
		Status:          oldtshydro.CodeqlRun_STATUS_PENDING,
		TriggeringEvent: oldtshydro.CodeqlRun_VALIDATION,
		Type:            oldtshydro.CodeqlRun_TYPE_STEADY,
	}

	pub.EXPECT().CodeqlRunEvent(gomock.Any(), expectedEvent).Times(1)

	err := s.CreateCodeqlRun(ctx, run)
	require.NoError(t, err)

	expectedEvent.ActorLogin = "updated-actor"
	pub.EXPECT().CodeqlRunEvent(gomock.Any(), expectedEvent).Times(1)

	run.ActorLogin = "updated-actor"
	err = s.UpdateCodeqlRun(ctx, run)
	require.NoError(t, err)
}

type hydroPublisherStub struct{}

func (h hydroPublisherStub) CodeqlRunEvent(ctx context.Context, run *oldtshydro.CodeqlRun) error {
	return nil
}

func testSetup(t *testing.T) (*gorm.DB, *Service, context.Context) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	s := NewService(db, hydroPublisherStub{})
	ctx := context.Background()
	return db, s, ctx
}

func baseCodeqlConfig() *ts.CodeqlConfig {
	return &ts.CodeqlConfig{
		RepositoryID:         repoID,
		RepositoryGRID:       "123456",
		OnboardedByActorGRID: "123abc",
		CreatedByActorLogin:  "abc",
		Languages:            []string{"javascript"},
		InitialLanguages:     []string{"javascript"},
		TemplateVersion:      workflowTemplateVersion,
	}
}

func getCurrentConfig(ctx context.Context, s *Service, repoID ts.RepositoryEID) (*ts.CodeqlConfig, error) {
	codeqlRepo, err := s.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return nil, err
	}

	return codeqlRepo.CurrentConfig, nil
}
