package managedanalyses

import (
	"context"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/mocks"
	ma_mocks "github.com/github/turboscan/ts/mocks/managedanalyses"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/workflows"

	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"

	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

var botActor = &ts.ActorGRIDLogin{GRID: "actorGRID", Login: "actorLogin"}

func TestUpdateRepo_WhenDisabled(t *testing.T) {
	db, ctx, ma, _, _ := setup(t)

	newSelectedLanguages := ts.Languages{"ruby", "python"}
	newQuerySuite := ts.QuerySuite_DEFAULT
	newThreatModel := ts.ThreatModel_REMOTE

	// Try sending a nil codeqlRepo
	_, err := ma.updateRepo(
		ctx,
		nil,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		&ts.ActorGRIDLogin{GRID: "actorGRID", Login: "actorLogin"},
		"",
	)
	require.ErrorIs(t, err, ts.ErrCodeqlRepoNotEnabled)

	// Try sending a softDeleted codeqlRepo
	codeqlRepo := createCodeqlRepo(t, db, nil, nil)
	now := sqltime.Now()
	codeqlRepo.SoftDeletedAt = &now

	_, err = ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"",
	)
	require.ErrorIs(t, err, ts.ErrCodeqlRepoNotEnabled)
}

func TestUpdateRepo_WhenOnboarding(t *testing.T) {
	db, ctx, ma, _, _ := setup(t)

	stagedConfig := &ts.CodeqlConfig{
		RepositoryID:     1,
		Languages:        ts.Languages{"javascript-typescript"},
		InitialLanguages: ts.Languages{"javascript-typescript"},
		QuerySuiteType:   ts.ExtendedQuerySuiteType(),
		ThreatModel:      ts.ThreatModel_REMOTE,
	}
	codeqlRepo := createCodeqlRepo(t, db, nil, stagedConfig)

	// Test not equivalent values
	newSelectedLanguages := ts.Languages{"ruby", "python"}
	newQuerySuite := ts.QuerySuite_DEFAULT
	newThreatModel := ts.ThreatModel_REMOTE
	_, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"",
	)
	require.ErrorIs(t, err, ts.ErrCodeqlConfigConflict)

	// Test equivalent update
	newSelectedLanguages = ts.Languages{"javascript-typescript"}
	newQuerySuite = ts.QuerySuite_EXTENDED
	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"",
	)
	require.ErrorIs(t, err, ts.ErrNoChangeRequired)
	require.Equal(t, ts.WorkflowRunEID(5), wfID)
}

func TestUpdateRepo_WhenUpdating(t *testing.T) {
	db, ctx, ma, _, _ := setup(t)

	currentConfig := &ts.CodeqlConfig{
		RepositoryID:     1,
		Languages:        ts.Languages{"ruby"},
		InitialLanguages: ts.Languages{"ruby"},
		QuerySuiteType:   ts.DefaultQuerySuiteType(),
		ThreatModel:      ts.ThreatModel_REMOTE,
	}
	stagedConfig := &ts.CodeqlConfig{
		RepositoryID:     1,
		Languages:        ts.Languages{"javascript-typescript"},
		InitialLanguages: ts.Languages{"javascript-typescript"},
		QuerySuiteType:   ts.ExtendedQuerySuiteType(),
		ThreatModel:      ts.ThreatModel_REMOTE,
	}
	codeqlRepo := createCodeqlRepo(t, db, currentConfig, stagedConfig)

	// Test not equivalent update
	newSelectedLanguages := ts.Languages{"ruby", "python"}
	newQuerySuite := ts.QuerySuite_DEFAULT
	newThreatModel := ts.ThreatModel_REMOTE
	_, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"",
	)
	require.ErrorIs(t, err, ts.ErrCodeqlConfigConflict)

	// Test equivalent update
	newSelectedLanguages = ts.Languages{"javascript-typescript"}
	newQuerySuite = ts.QuerySuite_EXTENDED
	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"",
	)
	require.ErrorIs(t, err, ts.ErrNoChangeRequired)
	require.Equal(t, ts.WorkflowRunEID(5), wfID)
}

func TestUpdateRepo_WhenWaiting_NoSelectedLanguages(t *testing.T) {
	db, ctx, ma, _, _ := setup(t)

	codeqlRepo := createCodeqlRepo(t, db, nil, nil)

	newSelectedLanguages := ts.Languages{}
	newQuerySuite := ts.QuerySuite_EXTENDED
	newThreatModel := ts.ThreatModel_REMOTE_LOCAL

	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"",
	)
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(0), wfID)

	out := &ts.CodeqlRepo{}
	err = db.First(out, "repository_id = ?", codeqlRepo.RepositoryID).Error
	require.NoError(t, err)

	require.True(t, out.IsWaiting())
	require.Equal(t, newQuerySuite, out.QuerySuite)
	require.Equal(t, newThreatModel, out.ThreatModel)
}

func TestUpdateRepo_WhenWaiting_SelectedLanguages(t *testing.T) {
	db, ctx, ma, _, mockLauncher := setup(t)

	codeqlRepo := createCodeqlRepo(t, db, nil, nil)

	// Test sending selected languages
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			// Side-effect from this call
			run.WorkflowRunID = 123
			return nil
		},
	)

	newSelectedLanguages := ts.Languages{"ruby"}
	newQuerySuite := ts.QuerySuite_EXTENDED
	newThreatModel := ts.ThreatModel_REMOTE_LOCAL
	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		codeqlRepo.RunnerLabel,
	)
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(123), wfID)

	out := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", codeqlRepo.RepositoryID).
		Preload("StagedConfig").
		First(&out).Error
	require.NoError(t, err)

	require.True(t, out.IsOnboarding())

	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlConfig{}))
	require.Equal(t, codeqlRepo.RunnerLabel, out.RunnerLabel)
	require.NotZero(t, out.CSharpExtractionOptions)
	require.NotZero(t, out.JavaExtractionOptions)
	require.NotZero(t, out.CppExtractionOptions)
}

func TestUpdateCodeqlRepoWhenStableNoSelectedLanguages(t *testing.T) {
	db, ctx, ma, _, _ := setup(t)

	currentConfig := &ts.CodeqlConfig{
		RepositoryID:     1,
		Languages:        ts.Languages{"ruby"},
		InitialLanguages: ts.Languages{"ruby"},
		QuerySuiteType:   ts.DefaultQuerySuiteType(),
		ThreatModel:      ts.ThreatModel_REMOTE,
	}
	currentConfig.MakeCurrent()
	codeqlRepo := createCodeqlRepo(t, db, currentConfig, nil)

	newSelectedLanguages := ts.Languages{}
	newQuerySuite := ts.QuerySuite_EXTENDED
	newThreatModel := ts.ThreatModel_REMOTE_LOCAL

	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"",
	)
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(0), wfID)

	out := &ts.CodeqlRepo{}
	err = db.First(out, "repository_id = ?", codeqlRepo.RepositoryID).Error
	require.NoError(t, err)

	require.True(t, out.IsWaiting())
	require.Equal(t, newQuerySuite, out.QuerySuite)
	require.Equal(t, newThreatModel, out.ThreatModel)
}

func TestUpdateCodeqlRepoWhenStableSelectedLanguages(t *testing.T) {
	db, ctx, ma, _, mockLauncher := setup(t)

	currentConfig := &ts.CodeqlConfig{
		RepositoryID:     1,
		Languages:        ts.Languages{"ruby"},
		InitialLanguages: ts.Languages{"ruby"},
		QuerySuiteType:   ts.DefaultQuerySuiteType(),
		ThreatModel:      ts.ThreatModel_REMOTE,
	}
	currentConfig.MakeCurrent()
	codeqlRepo := createCodeqlRepo(t, db, currentConfig, nil)

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			// Side-effect from this call
			run.WorkflowRunID = 123
			return nil
		},
	)

	newSelectedLanguages := ts.Languages{"javascript-typescript"}
	newQuerySuite := ts.QuerySuite_EXTENDED
	newThreatModel := ts.ThreatModel_REMOTE_LOCAL
	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"",
	)
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(123), wfID)

	out := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", codeqlRepo.RepositoryID).
		Preload("CurrentConfig").
		Preload("StagedConfig").
		First(&out).Error
	require.NoError(t, err)

	require.True(t, out.IsUpdating())

	// Config values should not change until the validation run succeeds
	require.Equal(t, codeqlRepo.QuerySuite, out.QuerySuite)
	require.Equal(t, codeqlRepo.ThreatModel, out.ThreatModel)
}

func TestUpdateCodeqlRepoWithValidationRunAndRunnerLabel(t *testing.T) {
	db, ctx, ma, _, mockLauncher := setup(t)

	currentConfig := &ts.CodeqlConfig{
		RepositoryID:     1,
		Languages:        ts.Languages{"ruby"},
		InitialLanguages: ts.Languages{"ruby"},
		QuerySuiteType:   ts.DefaultQuerySuiteType(),
		ThreatModel:      ts.ThreatModel_REMOTE,
		RunnerLabel:      "code-scanning",
	}
	currentConfig.MakeCurrent()
	codeqlRepo := createCodeqlRepo(t, db, currentConfig, nil, func(cr *ts.CodeqlRepo) *ts.CodeqlRepo {
		cr.RunnerLabel = "code-scanning"
		return cr
	})

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			// Side-effect from this call
			run.WorkflowRunID = 123
			return nil
		},
	)

	newSelectedLanguages := ts.Languages{"javascript-typescript"}
	newQuerySuite := ts.QuerySuite_EXTENDED
	newThreatModel := ts.ThreatModel_REMOTE_LOCAL
	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&newSelectedLanguages,
		&newQuerySuite,
		&newThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"not-code-scanning",
	)
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(123), wfID)

	out := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", codeqlRepo.RepositoryID).
		Preload("CurrentConfig").
		Preload("StagedConfig").
		First(&out).Error
	require.NoError(t, err)

	require.True(t, out.IsUpdating())

	// The codeql_repo doesn't reflect the new value at this point because the
	// update after a validation run happens once workflowsvc receives the workflow completion information
	require.Equal(t, "code-scanning", out.RunnerLabel)
	require.Equal(t, "not-code-scanning", out.StagedConfig.RunnerLabel)
}

func TestUpdateRunnerLabelOnlyInCodeqlRepoOutdatedTemplateVersion(t *testing.T) {
	db, ctx, ma, _, mockLauncher := setup(t)

	currentConfig := &ts.CodeqlConfig{
		RepositoryID:     1,
		Languages:        ts.Languages{"ruby"},
		InitialLanguages: ts.Languages{"ruby"},
		QuerySuiteType:   ts.DefaultQuerySuiteType(),
		ThreatModel:      ts.ThreatModel_REMOTE,
		RunnerLabel:      "code-scanning",
		TemplateVersion:  "v32", // should be a version lower than the current version
	}
	currentConfig.MakeCurrent()
	codeqlRepo := createCodeqlRepo(t, db, currentConfig, nil, func(cr *ts.CodeqlRepo) *ts.CodeqlRepo {
		cr.RunnerLabel = "code-scanning"
		return cr
	})

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			// Side-effect from this call
			run.WorkflowRunID = 123
			return nil
		},
	)

	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&currentConfig.Languages,
		&codeqlRepo.QuerySuite,
		&codeqlRepo.ThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"not-code-scanning",
	)
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(123), wfID)

	out := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", codeqlRepo.RepositoryID).
		Preload("CurrentConfig").
		Preload("StagedConfig").
		First(&out).Error
	require.NoError(t, err)

	require.Equal(t, "code-scanning", out.RunnerLabel)
	require.Equal(t, "not-code-scanning", out.StagedConfig.RunnerLabel)
}

func TestUpdateRunnerLabelOnlyInCodeqlRepo(t *testing.T) {
	db, ctx, ma, _, _ := setup(t)

	currentConfig := &ts.CodeqlConfig{
		RepositoryID:     1,
		Languages:        ts.Languages{"ruby"},
		InitialLanguages: ts.Languages{"ruby"},
		QuerySuiteType:   ts.DefaultQuerySuiteType(),
		ThreatModel:      ts.ThreatModel_REMOTE,
		RunnerLabel:      "code-scanning",
		TemplateVersion:  "v35", // This needs to be the latest version
	}
	currentConfig.MakeCurrent()
	codeqlRepo := createCodeqlRepo(t, db, currentConfig, nil, func(cr *ts.CodeqlRepo) *ts.CodeqlRepo {
		cr.RunnerLabel = "code-scanning"
		return cr
	})

	// We don't expect the launch mock to receive any calls to RunDynamicWorkflow
	wfID, err := ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		ts.Languages{},
		&currentConfig.Languages,
		&codeqlRepo.QuerySuite,
		&codeqlRepo.ThreatModel,
		[]byte("defaultRef"),
		ts.OwnerEID(1),
		ts.CodeqlPacks(""),
		botActor,
		"not-code-scanning",
	)
	require.ErrorIs(t, err, ts.ErrNoChangeRequired)
	require.Equal(t, ts.WorkflowRunEID(0), wfID)

	out := &ts.CodeqlRepo{}
	err = db.Where("repository_id = ?", codeqlRepo.RepositoryID).
		Preload("CurrentConfig").
		Preload("StagedConfig").
		First(&out).Error
	require.NoError(t, err)

	require.True(t, out.IsStable())

	require.Equal(t, "not-code-scanning", out.RunnerLabel)
	require.Equal(t, "not-code-scanning", out.CurrentConfig.RunnerLabel)
	require.NotEmpty(t, out.CurrentConfig.Workflow)
}

type hydroPublisherStub struct{}

func (h hydroPublisherStub) CodeqlRunEvent(ctx context.Context, run *oldtshydro.CodeqlRun) error {
	return nil
}

func newManagedAnalysisService(t *testing.T, db *gorm.DB) *managedanalysis.Service {
	t.Helper()

	return managedanalysis.NewService(db, hydroPublisherStub{})
}

func setup(t *testing.T) (*gorm.DB, context.Context, *ManagedAnalyses, *ma_mocks.MockStatusService, *mocks.MockDynamicWorkflowRunner) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	maService := newManagedAnalysisService(t, db)
	mockCtrl := gomock.NewController(t)
	mockLauncher := mocks.NewMockDynamicWorkflowRunner(mockCtrl)
	mockESS := ma_mocks.NewMockStatusService(mockCtrl)
	ma := &ManagedAnalyses{
		DataService:          maService,
		LaunchApiClient:      mockLauncher,
		WorkflowsLibrary:     workflows.NewLibrary(),
		EnabledStatusService: mockESS,
		Scheduler:            managedanalyses.NewScheduler(true),
	}

	return db, ctx, ma, mockESS, mockLauncher
}

type codeqlRepoOpt func(*ts.CodeqlRepo) *ts.CodeqlRepo

func createCodeqlRepo(t *testing.T, db *gorm.DB, currentConfig *ts.CodeqlConfig, stagedConfig *ts.CodeqlConfig, opts ...codeqlRepoOpt) *ts.CodeqlRepo {
	t.Helper()

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:            ts.RepositoryEID(1),
		RepositoryGRID:          ts.RepositoryGRID("repo1"),
		SupportedLanguages:      ts.Languages{"ruby"},
		QuerySuite:              ts.QuerySuite_DEFAULT,
		ThreatModel:             ts.ThreatModel_REMOTE,
		CSharpExtractionOptions: ts.CSharpExtractionOptions_BUILDLESS,
		JavaExtractionOptions:   ts.JavaExtractionOptions_BUILDLESS,
		CppExtractionOptions:    ts.CppExtractionOptions_BUILDLESS,
	}

	if currentConfig != nil {
		dbtest.RequireCreate(t, db, currentConfig)
		codeqlRepo.CurrentConfigID = &currentConfig.ID
		codeqlRepo.CurrentConfig = currentConfig

		validationRun := &ts.CodeqlRun{
			RepositoryID:   1,
			WorkflowRunID:  4,
			CodeqlConfigID: currentConfig.ID,
			RunType:        ts.CodeqlRunType_VALIDATION,
		}
		dbtest.RequireCreate(t, db, validationRun)
		currentConfig.ValidationRun = validationRun
	}

	if stagedConfig != nil {
		dbtest.RequireCreate(t, db, stagedConfig)
		codeqlRepo.StagedConfigID = &stagedConfig.ID
		codeqlRepo.StagedConfig = stagedConfig

		validationRun := &ts.CodeqlRun{
			RepositoryID:   1,
			WorkflowRunID:  5,
			CodeqlConfigID: stagedConfig.ID,
			RunType:        ts.CodeqlRunType_VALIDATION,
		}
		dbtest.RequireCreate(t, db, validationRun)
		stagedConfig.ValidationRun = validationRun
	}

	for _, opt := range opts {
		codeqlRepo = opt(codeqlRepo)
	}
	dbtest.RequireCreate(t, db, codeqlRepo)
	return codeqlRepo
}
