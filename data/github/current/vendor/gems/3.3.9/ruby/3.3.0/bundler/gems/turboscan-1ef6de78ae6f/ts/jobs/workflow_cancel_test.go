package jobs_test

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/jobs"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestCancelQueuedRuns_Success(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := newManagedAnalysisService(t, db)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	mockManagedAnalysesAPI := mocks.NewMockManagedAnalysesAPI(mockCtrl)
	ma := &maservice.ManagedAnalyses{
		DataService:          s,
		GitHubTwirpApiClient: mockManagedAnalysesAPI,
		UpdateRepoMetadata:   mockUpdateRepository,
	}

	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	_, err := createCodeqlRepo(ctx, s, repoID, nil, config)
	require.NoError(t, err)
	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_PENDING,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  config.ID,
	}
	dbtest.RequireCreate(t, db, run)

	response := map[ts.WorkflowRunEID]ghgh.WorkflowRunState{workflowRunID: {Status: "completed", Conclusion: "cancelled"}}
	mockManagedAnalysesAPI.EXPECT().CancelQueuedRuns(gomock.Any(), ts.RepositoryEID(1), []ts.WorkflowRunEID{workflowRunID}).Return(response, nil)
	err = jobs.CancelQueuedRuns(ctx, ma, []ts.CodeqlRun{*run})

	require.NoError(t, err)

	// Reload from the DB
	outConfig, err := getCurrentConfig(ctx, s, repoID)
	require.NoError(t, err)
	require.Nil(t, outConfig)
	run, err = s.GetCodeqlRun(ctx, repoID, workflowRunID)
	require.NoError(t, err)

	// Assert changes
	require.Equal(t, ts.CodeQlRunStatus_CANCELLED, run.Status)
}

func TestCancelQueuedRuns_SyncStatus(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := newManagedAnalysisService(t, db)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	mockManagedAnalysesAPI := mocks.NewMockManagedAnalysesAPI(mockCtrl)
	ma := &maservice.ManagedAnalyses{
		DataService:          s,
		GitHubTwirpApiClient: mockManagedAnalysesAPI,
		UpdateRepoMetadata:   mockUpdateRepository,
	}

	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	_, err := createCodeqlRepo(ctx, s, repoID, nil, config)
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

	response := map[ts.WorkflowRunEID]ghgh.WorkflowRunState{workflowRunID: {Status: "completed", Conclusion: "failure"}}
	mockManagedAnalysesAPI.EXPECT().CancelQueuedRuns(gomock.Any(), ts.RepositoryEID(1), []ts.WorkflowRunEID{workflowRunID}).Return(response, nil)
	err = jobs.CancelQueuedRuns(ctx, ma, []ts.CodeqlRun{*run})

	require.NoError(t, err)

	// Reload from the DB
	outConfig, err := getCurrentConfig(ctx, s, repoID)
	require.NoError(t, err)
	require.Nil(t, outConfig)
	run, err = s.GetCodeqlRun(ctx, repoID, workflowRunID)
	require.NoError(t, err)

	// Assert changes
	require.Equal(t, ts.CodeqlRunStatus_FAILED, run.Status)
}

func TestCancelQueuedRuns_CompletedStatus(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := newManagedAnalysisService(t, db)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	mockManagedAnalysesAPI := mocks.NewMockManagedAnalysesAPI(mockCtrl)
	ma := &maservice.ManagedAnalyses{
		DataService:          s,
		GitHubTwirpApiClient: mockManagedAnalysesAPI,
		UpdateRepoMetadata:   mockUpdateRepository,
	}

	config := baseCodeqlConfig().Deprecate()
	dbtest.RequireCreate(t, db, config)
	_, err := createCodeqlRepo(ctx, s, repoID, nil, nil)
	require.NoError(t, err)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_FAILED,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	response := map[ts.WorkflowRunEID]ghgh.WorkflowRunState{workflowRunID: {Status: "completed", Conclusion: "success"}}
	mockManagedAnalysesAPI.EXPECT().CancelQueuedRuns(gomock.Any(), ts.RepositoryEID(1), []ts.WorkflowRunEID{workflowRunID}).Return(response, nil)
	err = jobs.CancelQueuedRuns(ctx, ma, []ts.CodeqlRun{*run})

	require.NoError(t, err)

	// Reload from the DB
	outConfig, err := getCurrentConfig(ctx, s, repoID)
	require.NoError(t, err)
	require.Nil(t, outConfig)
	run, err = s.GetCodeqlRun(ctx, repoID, workflowRunID)
	require.NoError(t, err)

	// Assert nothing has changed
	require.Equal(t, ts.CodeqlRunStatus_FAILED, run.Status)
}
