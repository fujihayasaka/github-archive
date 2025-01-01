package jobs_test

import (
	"context"
	"testing"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/botfetcher"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/mock"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/jobs"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/mocks"
	ma_mocks "github.com/github/turboscan/ts/mocks/managedanalyses"
	"github.com/github/turboscan/ts/workflows"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

const defaultRef = "refs/heads/main"

func setUpTest(t *testing.T) (context.Context, *gorm.DB, *aqueduct.TSServices, *mocks.MockDynamicWorkflowRunner, *mocks.MockManagedAnalysesAPI, *ma_mocks.MockStatusService) {
	t.Helper()

	exporter := mock.NewExporter(
		// noop
		func(ctx context.Context, data []byte) error {
			return nil
		},
	)

	r, err := exceptions.NewReporter(
		exceptions.WithApplication("my-app"), // Required by the exceptions pkg
		exceptions.WithExporter(exporter),
	)
	require.NoError(t, err)
	ctx := appctx.WithReporter(context.Background(), r)

	db := dbtest.RequireConnection(t)
	mockCtrl := gomock.NewController(t)
	mockLauncher := mocks.NewMockDynamicWorkflowRunner(mockCtrl)
	mockManagedAnalysesAPI := mocks.NewMockManagedAnalysesAPI(mockCtrl)
	mockESS := ma_mocks.NewMockStatusService(mockCtrl)

	maService := managedanalysis.NewService(db, hydroPublisherStub{})

	s := &aqueduct.TSServices{
		ManagedAnalyses: &maservice.ManagedAnalyses{
			DataService:          maService,
			GitHubTwirpApiClient: mockManagedAnalysesAPI,
			LaunchApiClient:      mockLauncher,
			WorkflowsLibrary:     workflows.NewLibrary(),
			EnabledStatusService: mockESS,
			GetBotActor:          botfetcher.Static(ts.ActorGRIDLogin{GRID: "bot", Login: "bot"}),
		},
	}

	return ctx, db, s, mockLauncher, mockManagedAnalysesAPI, mockESS
}

func baseCodeqlConfig() *ts.CodeqlConfig {
	return &ts.CodeqlConfig{
		RepositoryID: repoID,
	}
}

// createCodeqlRepo creates a codeql repo in the database, optionally
// setting the configurations.
func createCodeqlRepo(ctx context.Context, maDB managedanalyses.CodeqlDB,
	repoID ts.RepositoryEID, current *ts.CodeqlConfig, staged *ts.CodeqlConfig,
) (*ts.CodeqlRepo, error) {
	err := maDB.CreateCodeqlRepo(ctx, &ts.CodeqlRepo{RepositoryID: repoID})
	if err != nil {
		return nil, err
	}
	codeqlRepo, err := maDB.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return nil, err
	}

	if current != nil {
		codeqlRepo.CurrentConfigID = &current.ID
	}
	if staged != nil {
		codeqlRepo.StagedConfigID = &staged.ID
	}

	err = maDB.UpdateCodeqlRepo(ctx, codeqlRepo)
	if err != nil {
		return nil, err
	}
	return codeqlRepo, nil
}

func TestPerformSuccesfulTrigger(t *testing.T) {
	ctx, db, s, mockLauncher, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = false

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	// shouldn't get any error if MA isn't onboarded yet
	err := job.Perform(ctx, s)
	require.NoError(t, err)

	config := baseConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	}
	dbtest.RequireCreate(t, db, run)

	_, err = createCodeqlRepo(ctx, s.ManagedAnalyses.DataService, repoID, config, nil)
	require.NoError(t, err)

	codeqlPacks := ts.CodeqlPacks("myorg/mypack@1.2.3")
	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(true, nil, codeqlPacks, nil)
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			require.Equal(t, job.ActorLogin, run.ActorLogin)
			require.Equal(t, job.ActorGRID, run.ActorGRID)
			require.Equal(t, job.Sha, run.Sha)
			require.Equal(t, job.Ref, run.Ref)
			require.Equal(t, ts.CodeqlRunTriggeringEvent_PUSH, run.TriggeringEvent)
			// Side-effect from this call
			run.WorkflowRunID = 123
			return nil
		},
	)
	err = job.Perform(ctx, s)
	require.NoError(t, err)

	// should create an entry into ts_codeql_run
	run, err = s.ManagedAnalyses.DataService.GetCodeqlRunByShaAndRef(ctx, config.RepositoryID, job.Sha, job.Ref)
	require.NoError(t, err)
	require.Equal(t, job.Sha, run.Sha)
	require.Equal(t, ts.CodeqlRunTriggeringEvent_PUSH, run.TriggeringEvent)
	require.Equal(t, codeqlPacks, *run.CodeqlPacks)
}

func TestPerformFailedTrigger(t *testing.T) {
	ctx, db, s, mockLauncher, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = false

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	config := baseConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, s.ManagedAnalyses.DataService, repoID, config, nil)
	require.NoError(t, err)

	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(true, nil, ts.CodeqlPacks(""), nil)
	// make workflow trigger fail
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).Return(errors.New("failed to trigger dynamic workflow"))
	err = job.Perform(ctx, s)
	require.Error(t, err)

	// shouldn't create an entry into ts_codeql_run
	_, err = s.ManagedAnalyses.DataService.GetCodeqlRunByShaAndRef(ctx, config.RepositoryID, job.Sha, job.Ref)
	require.Error(t, err)
	require.True(t, errors.Is(err, ts.ErrCodeqlRunNotFound))
}

func TestPerformShouldTriggerOnce(t *testing.T) {
	ctx, db, s, _, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = false

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	config := baseConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)

	wt := s.ManagedAnalyses.WorkflowsLibrary.GetWorkflowTemplate(ctx, repo.RepositoryID)
	run, err := config.SetUpForValidationRun(job.Ref, job.Sha, wt, ts.CodeqlRunTriggeringEvent_VALIDATION, 0, ts.CodeqlPacks(""))
	require.NoError(t, err)
	run.WorkflowRunID = 123
	err = s.ManagedAnalyses.DataService.CreateCodeqlRun(ctx, run)
	require.NoError(t, err)

	// as run already exists, it shouldn't retrigger workflow run - or even check Actions is enabled!
	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Times(0)

	err = job.Perform(ctx, s)
	require.NoError(t, err)
}

func TestPerformWithDisabledRequiredServices(t *testing.T) {
	ctx, db, s, _, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = false

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	config := baseConfig().MakeCurrent()
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	}
	dbtest.RequireCreate(t, db, run)
	_, err := createCodeqlRepo(ctx, s.ManagedAnalyses.DataService, repoID, config, nil)
	require.NoError(t, err)

	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(false, nil, ts.CodeqlPacks(""), nil)

	err = job.Perform(ctx, s)
	require.NoError(t, err) // There should be no error
}

func TestConfigChanges_TriggerJITValidation(t *testing.T) {
	ctx, db, s, mockLauncher, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = true

	// shouldn't get any error even though MA isn't onboarded yet
	err := job.Perform(ctx, s)
	require.NoError(t, err)

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	// Create config
	config := baseConfig().MakeCurrent()
	config.TemplateVersion = "something different from the latest version"
	dbtest.RequireCreate(t, db, config)

	// Associate validation run
	run := &ts.CodeqlRun{
		RepositoryID:    config.RepositoryID,
		CodeqlConfigID:  config.ID,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	// Create codeql repo
	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:    job.RepoID,
		CurrentConfigID: &config.ID,
	}
	dbtest.RequireCreate(t, db, codeqlRepo)

	// check that a jit validation run is successfully created and triggered
	var triggeredRun *ts.CodeqlRun
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			triggeredRun = run
			run.WorkflowRunID = 123
			return nil
		},
	)
	codeqlPacks := ts.CodeqlPacks("myorg/mypack@1.2.3")
	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(true, nil, codeqlPacks, nil)

	// and now we're ready to perform the job for real
	err = job.Perform(ctx, s)
	require.NoError(t, err)
	// this confirms the run was triggered
	require.NotNil(t, triggeredRun)
	require.True(t, triggeredRun.Validation())

	// and now we check that the run was created in the db
	run, err = s.ManagedAnalyses.DataService.GetCodeqlRunByShaAndRef(ctx, config.RepositoryID, job.Sha, job.Ref)
	require.NoError(t, err)
	require.Equal(t, job.Sha, run.Sha)
	require.Equal(t, ts.CodeqlRunTriggeringEvent_PUSH, run.TriggeringEvent)
	require.True(t, run.Validation())
	require.Equal(t, triggeredRun.ID, run.ID)
	require.Equal(t, codeqlPacks, *run.CodeqlPacks)

	// should update CodeqlRepo and create a Staged config
	codeqlRepo = &ts.CodeqlRepo{}
	err = db.Preload("StagedConfig").First(&codeqlRepo, "repository_id = ?", repo.RepositoryID).Error
	require.NoError(t, err)
	require.NotNil(t, codeqlRepo.StagedConfig)
	require.True(t, codeqlRepo.StagedConfig.IsStaged())
	require.True(t, codeqlRepo.StagedConfig.IsEquivalent(config))
}

func TestConfigChanges_TriggerNoJITValidation_StagedConfigExists(t *testing.T) {
	ctx, db, s, mockLauncher, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = true

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	configOldTemplate := baseConfig().MakeCurrent()
	configOldTemplate.TemplateVersion = "not the latest version"
	dbtest.RequireCreate(t, db, configOldTemplate)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: configOldTemplate.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	}
	dbtest.RequireCreate(t, db, run)

	// We create a staged config for this repo, so that it will prevent us from creating
	// a new staged config for the new TemplateVersion, so we won't create a JIT Validation
	// run but rather a steady run for the old config
	stagedConfig := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, stagedConfig)
	run2 := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: stagedConfig.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  2,
	}
	dbtest.RequireCreate(t, db, run2)

	_, err := createCodeqlRepo(ctx, s.ManagedAnalyses.DataService, repoID, configOldTemplate, stagedConfig)
	require.NoError(t, err)

	codeqlPacks := ts.CodeqlPacks("myorg/mypack@1.2.3")
	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(true, nil, codeqlPacks, nil)

	var steadyRun *ts.CodeqlRun
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			steadyRun = run
			run.WorkflowRunID = 123
			return nil
		},
	)
	err = job.Perform(ctx, s)
	require.NoError(t, err)
	require.NotNil(t, steadyRun)
	require.Equal(t, ts.CodeqlRunType_STEADY, steadyRun.RunType)
	require.Equal(t, configOldTemplate.ID, steadyRun.CodeqlConfigID)
	require.Equal(t, codeqlPacks, *steadyRun.CodeqlPacks)
}

func TestConfigChanges_AutoHealAfterJITValidationFailedEarlier(t *testing.T) {
	ctx, db, s, mockLauncher, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = true

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	configOldTemplate := baseCodeqlConfig().MakeCurrent()
	configOldTemplate.TemplateVersion = "TEST"
	dbtest.RequireCreate(t, db, configOldTemplate)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: configOldTemplate.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, s.ManagedAnalyses.DataService, repoID, configOldTemplate, nil)
	require.NoError(t, err)

	// simulate a staged config and failed jit run
	wt := s.ManagedAnalyses.WorkflowsLibrary.GetWorkflowTemplate(ctx, repo.RepositoryID)

	stagedConfigLatestTemplate := configOldTemplate.CopyForUpdate().MakeStaged()
	stagedConfigLatestTemplate.TemplateVersion = wt.Version
	dbtest.RequireCreate(t, db, stagedConfigLatestTemplate)
	run2 := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: stagedConfigLatestTemplate.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  2,
	}
	dbtest.RequireCreate(t, db, run2)

	run, err = stagedConfigLatestTemplate.SetUpForValidationRun([]byte(defaultRef), "", wt, ts.CodeqlRunTriggeringEvent_VALIDATION, 0, ts.CodeqlPacks(""))
	require.NoError(t, err)
	// make JIT run failed
	run.Status = ts.CodeqlRunStatus_FAILED
	run.TriggeringEvent = ts.CodeqlRunTriggeringEvent_PUSH
	dbtest.RequireCreate(t, db, run)

	// once jit validation is failed, deprecate config
	stagedConfigLatestTemplate.Deprecate()
	db.Save(stagedConfigLatestTemplate)

	// Because we already have a failed run for the latest template, when the job
	// finally runs it will just launch a normal, steady run for the old config.
	var steadyRun *ts.CodeqlRun
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			steadyRun = run
			run.WorkflowRunID = 123
			return nil
		},
	)
	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(true, nil, ts.CodeqlPacks(""), nil)
	err = job.Perform(ctx, s)
	require.NoError(t, err)
	require.NotNil(t, steadyRun)
	require.Equal(t, ts.CodeqlRunType_STEADY, steadyRun.RunType)
	require.Equal(t, configOldTemplate.ID, steadyRun.CodeqlConfigID)

	codeqlRepo := &ts.CodeqlRepo{}
	err = db.First(&codeqlRepo, "repository_id = ?", repo.RepositoryID).Error
	require.NoError(t, err)
	// no staged config should have been created
	require.Nil(t, codeqlRepo.StagedConfigID)
	// and the current config hasn't changed
	require.Equal(t, configOldTemplate.ID, *codeqlRepo.CurrentConfigID)
}

func TestConfigChanges_OnActionsFailure(t *testing.T) {
	ctx, db, s, mockLauncher, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = true

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	configOldTemplate := baseCodeqlConfig().MakeCurrent()
	configOldTemplate.TemplateVersion = "TEST"
	dbtest.RequireCreate(t, db, configOldTemplate)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: configOldTemplate.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, s.ManagedAnalyses.DataService, repoID, configOldTemplate, nil)
	require.NoError(t, err)

	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(true, nil, ts.CodeqlPacks(""), nil)

	// We fail to call launch
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).Return(errors.New("some error"))

	err = job.Perform(ctx, s)
	require.Error(t, err)

	codeqlRepo := &ts.CodeqlRepo{}
	err = db.First(&codeqlRepo, "repository_id = ?", repo.RepositoryID).Error
	require.NoError(t, err)
	// no staged config should have been created
	require.Nil(t, codeqlRepo.StagedConfigID)
	// and the current config hasn't changed
	require.Equal(t, configOldTemplate.ID, *codeqlRepo.CurrentConfigID)
}

func TestPush_TriggerJITValidation(t *testing.T) {
	ctx, db, s, mockLauncher, mockManagedAnalysesAPI, _ := setUpTest(t)

	job := runCodeqlOnPushJob()
	job.InDefaultBranch = true

	repo := baseRepo()
	dbtest.RequireCreate(t, db, repo)

	// make sure managed analysis is enabled but not on the latest
	// workflow template version
	config := baseConfig().MakeCurrent()
	config.TemplateVersion = "something different from the latest version"
	dbtest.RequireCreate(t, db, config)
	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		CodeqlConfigID: config.ID,
		RunType:        ts.CodeqlRunType_VALIDATION,
		WorkflowRunID:  1,
	}
	dbtest.RequireCreate(t, db, run)
	_, err := createCodeqlRepo(ctx, s.ManagedAnalyses.DataService, repoID, config, nil)
	require.NoError(t, err)

	// check that a candidate config jit validation run is successfully created and triggered
	var attemptedConfig1 *ts.CodeqlConfig
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			run.WorkflowRunID = 123 // if we don't set this the run won't be saved
			attemptedConfig1 = run.Config
			return nil
		},
	).Times(1)
	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(true, nil, ts.CodeqlPacks(""), nil).AnyTimes()
	// and now we're ready to perform the job for real
	err = job.Perform(ctx, s)
	require.NoError(t, err)
	// this confirms the config was attempted
	require.NotNil(t, attemptedConfig1)

	// now we mark it as failed
	attemptedConfig1.Deprecate()
	failedRunStatus := ts.CodeqlRunStatus_FAILED
	attemptedConfig1.ValidationRunStatus = &failedRunStatus
	require.NoError(t, db.Save(attemptedConfig1).Error)

	// this time a steady run for the CURRENT config will be launched (no JIT validation as the previously
	// failed is too recent)
	var triggeredRun *ts.CodeqlRun
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			triggeredRun = run
			run.WorkflowRunID = 456
			return nil
		},
	).Times(1)
	// and now we're ready to perform the job for real
	job.Sha = "456" // this is enough make the job feel like new
	err = job.Perform(ctx, s)
	require.NoError(t, err)
	require.False(t, triggeredRun.Validation())
	require.Equal(t, config.ID, triggeredRun.Config.ID)

	// now we will age attemptedConfig1 a bit, so new one gets attempted
	attemptedConfig1.CreatedAt = sqltime.Date(2000, 01, 01, 00, 00, 00, 00, time.UTC)
	require.NoError(t, db.Save(attemptedConfig1).Error)

	// and now a new config and validation run will be created
	var attemptedConfig2 *ts.CodeqlConfig
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			attemptedConfig2 = run.Config
			run.WorkflowRunID = 789
			return nil
		},
	).Times(1)
	job.Sha = "789"
	err = job.Perform(ctx, s)
	require.NoError(t, err)
	require.NotNil(t, attemptedConfig2)

	// after this, even if it ages, we won't reattempt a config for the latest template workflow version
	attemptedConfig2.CreatedAt = sqltime.Date(2000, 01, 01, 00, 00, 00, 00, time.UTC)
	require.NoError(t, db.Save(attemptedConfig2).Error)

	triggeredRun = nil
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			triggeredRun = run
			run.WorkflowRunID = 101
			return nil
		},
	).Times(1)
	job.Sha = "101"
	err = job.Perform(ctx, s)
	require.NoError(t, err)
	require.False(t, triggeredRun.Validation())
	require.Equal(t, config.ID, triggeredRun.Config.ID)
}

func baseRepo() *ts.Repository {
	repo := &ts.Repository{
		RepositoryID:    1,
		OwnerID:         1,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte(defaultRef),
	}
	return repo
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

func runCodeqlOnPushJob() *jobs.RunCodeqlOnPush {
	return &jobs.RunCodeqlOnPush{
		RepoID:     1,
		Ref:        []byte(defaultRef),
		Sha:        "123",
		ActorLogin: "push_user",
		ActorGRID:  "ngid123",
	}
}
