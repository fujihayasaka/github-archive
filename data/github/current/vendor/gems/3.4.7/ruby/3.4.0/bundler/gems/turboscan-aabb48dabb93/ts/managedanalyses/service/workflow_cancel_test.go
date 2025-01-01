package managedanalyses_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestCancelQueuedRuns_Success(t *testing.T) {
	db, ctx, ma, _, _, mockAPI := setup(t)

	config := baseCodeqlConfig().MakeStaged()
	dbtest.RequireCreate(t, db, config)
	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, config)
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
	mockAPI.EXPECT().CancelQueuedRuns(gomock.Any(), ts.RepositoryEID(1), []ts.WorkflowRunEID{workflowRunID}).Return(response, nil)
	err = ma.CancelQueuedRuns(ctx, []ts.CodeqlRun{*run})

	require.NoError(t, err)

	// Reload from the DB
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)

	require.Nil(t, codeqlRepo.CurrentConfig)
	run = codeqlRepo.FailedConfig.ValidationRun
	require.Equal(t, workflowRunID, run.WorkflowRunID)

	// Assert changes
	require.Equal(t, ts.CodeQlRunStatus_CANCELLED, run.Status)
}

func TestCancelQueuedRuns_SyncStatus(t *testing.T) {
	db, ctx, ma, _, _, mockAPI := setup(t)

	config := baseCodeqlConfig().MakeStaged()
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

	response := map[ts.WorkflowRunEID]ghgh.WorkflowRunState{workflowRunID: {Status: "completed", Conclusion: "failure"}}
	mockAPI.EXPECT().CancelQueuedRuns(gomock.Any(), ts.RepositoryEID(1), []ts.WorkflowRunEID{workflowRunID}).Return(response, nil)
	err = ma.CancelQueuedRuns(ctx, []ts.CodeqlRun{*run})

	require.NoError(t, err)

	// Reload from the DB
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)

	run = codeqlRepo.FailedConfig.ValidationRun
	require.Equal(t, workflowRunID, run.WorkflowRunID)

	// Assert changes
	require.Equal(t, ts.CodeqlRunStatus_FAILED, run.Status)
}

func TestCancelQueuedRuns_CompletedStatus(t *testing.T) {
	db, ctx, ma, _, _, mockAPI := setup(t)

	config := baseCodeqlConfig().Deprecate()
	dbtest.RequireCreate(t, db, config)
	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, nil, nil)
	require.NoError(t, err)

	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   workflowRunID,
		Status:          ts.CodeqlRunStatus_FAILED,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
	}
	dbtest.RequireCreate(t, db, run)

	response := map[ts.WorkflowRunEID]ghgh.WorkflowRunState{workflowRunID: {Status: "completed", Conclusion: "success"}}
	mockAPI.EXPECT().CancelQueuedRuns(gomock.Any(), ts.RepositoryEID(1), []ts.WorkflowRunEID{workflowRunID}).Return(response, nil)
	err = ma.CancelQueuedRuns(ctx, []ts.CodeqlRun{*run})

	require.NoError(t, err)

	// Reload from the DB
	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	// We directly load the run as the relevant config is not part of the codeqlrepo
	run, err = ma.DataService.GetCodeqlRun(ctx, repoID, workflowRunID)
	require.NoError(t, err)

	// The repo state should be unchanged, in particular the config should not be promoted
	require.Nil(t, codeqlRepo.CurrentConfig)

	// Assert nothing has changed
	require.Equal(t, ts.CodeqlRunStatus_FAILED, run.Status)
}
