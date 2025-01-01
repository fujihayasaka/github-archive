package managedanalyses_test

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/botfetcher"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/jobs"
	ma_ "github.com/github/turboscan/ts/managedanalyses"
	managedanalyses "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/mocks"
	ma_mocks "github.com/github/turboscan/ts/mocks/managedanalyses"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/workflows"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

const (
	repoID                  = ts.RepositoryEID(1)
	workflowTemplateVersion = "version"
)

var botActor = &ts.ActorGRIDLogin{Login: "CSBot", GRID: "1"}

func setup(t *testing.T) (*gorm.DB, context.Context, *managedanalyses.ManagedAnalyses, *ma_mocks.MockStatusService, *mocks.MockDynamicWorkflowRunner, *mocks.MockManagedAnalysesAPI) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	maService := newManagedAnalysisService(t, db)
	mockCtrl := gomock.NewController(t)
	mockLauncher := mocks.NewMockDynamicWorkflowRunner(mockCtrl)
	mockESS := ma_mocks.NewMockStatusService(mockCtrl)
	mockManagedAnalysesAPI := mocks.NewMockManagedAnalysesAPI(mockCtrl)
	ma := &managedanalyses.ManagedAnalyses{
		DataService:          maService,
		LaunchApiClient:      mockLauncher,
		WorkflowsLibrary:     workflows.NewLibrary(),
		EnabledStatusService: mockESS,
		GitHubTwirpApiClient: mockManagedAnalysesAPI,
		GetBotActor:          botfetcher.Static(*botActor),
		Scheduler:            ma_.NewScheduler(false),
		UpdateRepoMetadata: func(ctx context.Context, repoID ts.RepositoryEID) error {
			return nil
		},
	}

	return db, ctx, ma, mockESS, mockLauncher, mockManagedAnalysesAPI
}

func TestLatestWorkflowTemplate(t *testing.T) {
	ma := &managedanalyses.ManagedAnalyses{
		WorkflowsLibrary: workflows.NewLibrary(),
	}
	ctx := context.Background()
	wt := ma.WorkflowsLibrary.GetWorkflowTemplate(ctx, 1)

	require.Equal(t, "v35", wt.Version)
}

func TestRunOnSchedule(t *testing.T) {
	db, ctx, ma, _, mockLauncher, mockManagedAnalysesAPI := setup(t)
	repoService := repository.NewService(db)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
		OwnerID:         1,
	}
	dbtest.RequireCreate(t, db, repo)

	config := &ts.CodeqlConfig{
		RepositoryID:         repoID,
		RepositoryGRID:       "123456",
		OnboardedByActorGRID: "123abc",
		CreatedByActorLogin:  "abc",
		Languages:            []string{"javascript"},
		TemplateVersion:      workflowTemplateVersion,
	}
	config.MakeCurrent()
	dbtest.RequireCreate(t, db, config)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   1,
		Status:          ts.CodeqlRunStatus_COMPLETED,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, config, nil)
	require.NoError(t, err)

	schedule := &ts.CodeqlSchedule{
		RepositoryID: repoID,
		NextRunAt:    sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, schedule)

	codeqlPacks := ts.CodeqlPacks("myorg/mypack@1.2.3")
	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repo.RepositoryID).Return(true, nil, codeqlPacks, nil)
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			run.WorkflowRunID = 101
			return nil
		},
	).Times(1)

	err = ma.RunOnSchedule(ctx, repoService)
	require.NoError(t, err)

	var newRun ts.CodeqlRun
	err = db.Where("triggering_event = ?", ts.CodeqlRunTriggeringEvent_SCHEDULED).First(&newRun).Error
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(101), newRun.WorkflowRunID)
	require.Equal(t, codeqlPacks, *newRun.CodeqlPacks)

	var newSchedule ts.CodeqlSchedule
	err = db.Where("repository_id = ?", repoID).First(&newSchedule).Error
	require.NoError(t, err)
	require.NotEqual(t, schedule.NextRunAt, newSchedule.NextRunAt)
	require.True(t, newSchedule.NextRunAt.Time.After(schedule.NextRunAt.Time))
}

func TestRunOnSchedule_DiscardDormantRepositories(t *testing.T) {
	db, ctx, ma, _, _, mockManagedAnalysesAPI := setup(t)
	repoService := repository.NewService(db)
	days := 30
	ma.DormantRepoDays = &days

	config := &ts.CodeqlConfig{
		RepositoryID:         repoID,
		RepositoryGRID:       "123456",
		OnboardedByActorGRID: "123abc",
		CreatedByActorLogin:  "abc",
		Languages:            []string{"javascript"},
		TemplateVersion:      workflowTemplateVersion,
	}
	config.MakeCurrent()
	dbtest.RequireCreate(t, db, config)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   1,
		Status:          ts.CodeqlRunStatus_COMPLETED,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	// Set the run to be 1 year old, so we consider the repo dormant
	run.CreatedAt = sqltime.Time{Time: sqltime.Now().AddDate(-1, 0, 0)}
	dbtest.RequireCreate(t, db, run)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, config, nil)
	require.NoError(t, err)

	schedule := &ts.CodeqlSchedule{
		RepositoryID: repoID,
		NextRunAt:    sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, schedule)

	mockManagedAnalysesAPI.EXPECT().
		AreRequiredServicesEnabled(gomock.Any(), repoID).
		Return(true, nil, ts.CodeqlPacks(""), nil).
		// This is only if we consider the repo as active.
		// So we require it is never called.
		Times(0)

	repo := &ts.Repository{
		RepositoryID:    repoID,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      []byte("refs/heads/main"),
		OwnerID:         1,
	}
	dbtest.RequireCreate(t, db, repo)

	err = ma.RunOnSchedule(ctx, repoService)
	require.NoError(t, err)

}

// TestAdjust_SteadyState checks that the steady state run after an adjustment does respect
// the changes in the adjustment.
// Specifically, we test that we removed Javascript as a language and we do not have it in the
// run workflow file.
func TestAdjust_SteadyState(t *testing.T) {
	_, ctx, ma, _, mockLauncher, mockManagedAnalysesAPI := setup(t)

	repoID := ts.RepositoryEID(1)
	ownerID := ts.OwnerEID(1)
	allLanguages := ts.Languages{"javascript", "ruby"}
	onlyRuby := ts.Languages{"ruby"}

	workflowRunID := ts.WorkflowRunEID(101)

	// First onboard the repo
	//
	// This should call launch
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).Times(1).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			run.WorkflowRunID = workflowRunID
			return nil
		},
	).Times(1)

	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, nil)
	require.NoError(t, err)

	_, err = ma.OnboardRepo(ctx, repoID, allLanguages, ts.QuerySuite_DEFAULT, ts.ThreatModel_REMOTE, botActor, []byte("main"), ownerID, ts.CodeqlPacks(""), "")
	require.NoError(t, err)

	// Then call the adjust method
	err = ma.AdjustRepo(ctx, repoID, onlyRuby, workflowRunID)
	require.NoError(t, err)

	// Now we can mark the codeqlRepo as current
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	status := ts.CodeqlRunStatus_COMPLETED
	err = ma.DataService.PromoteCodeqlConfigToCurrent(ctx, codeqlRepo.StagedConfig, repoID, &status)
	require.NoError(t, err)

	// Trigger a steady state run
	job := jobs.RunCodeqlOnPush{
		RepoID:     repoID,
		OwnerID:    ownerID,
		Sha:        ts.Sha("beef"),
		Ref:        ts.Ref([]byte("main")),
		ActorGRID:  ts.ActorGRID("123"),
		ActorLogin: "bot",
	}

	mockManagedAnalysesAPI.EXPECT().AreRequiredServicesEnabled(gomock.Any(), repoID).Return(true, &ts.ProximaTenant{}, ts.CodeqlPacks(""), nil)

	//
	// !!! The Assertion is here !!!
	// The steady state does not include the language that was removed
	//
	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).Times(1).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			run.WorkflowRunID = 101
			require.NotContains(t, run.Workflow, "javascript")
			return nil
		},
	).Times(1)

	// Execute the steady state call
	err = job.Perform(ctx, &aqueduct.TSServices{ManagedAnalyses: ma})
	require.NoError(t, err)

}
