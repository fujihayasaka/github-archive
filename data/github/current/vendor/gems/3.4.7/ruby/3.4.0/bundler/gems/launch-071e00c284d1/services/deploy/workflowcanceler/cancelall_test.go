package workflowcanceler

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/build"
)

func TestWorkflowCancelerCancelAll(t *testing.T) {
	suite.Run(t, new(workflowCancelerTestSuite))
}

func (s *workflowCancelerTestSuite) Test_SuccessfulCancellation_ForActorIDExludeRepoIDs() {
	ctx := context.Background()

	executionID := types.NewRandomWorkflowExecutionID()
	anotherExecutionID := types.NewRandomWorkflowExecutionID()

	states := []*deployer.WorkflowBuildState{
		{
			DatabaseID:      1,
			State:           build.WorkflowStateQueued,
			ExternalBuildID: "12",
			RepositoryID:    testRepoGlobalID,
			ExecutionID:     executionID,
		},
		{
			DatabaseID:      2,
			State:           build.WorkflowStateStarted,
			ExternalBuildID: "13",
			RepositoryID:    testRepoGlobalID,
			ExecutionID:     anotherExecutionID,
		},
	}

	s.wbr.EXPECT().GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(mock.Anything, testActorGlobalID, []types.GlobalID{}, mock.Anything, int64(-1)).Return(states, nil).Once()
	s.hyd.EXPECT().EmitWorkflowCancelRequest(mock.Anything).Return()

	s.rcm.EXPECT().Cancel(mock.Anything, "12", (*azp.CancelOptions)(nil)).Return(nil)
	s.rcm.EXPECT().Cancel(mock.Anything, "13", (*azp.CancelOptions)(nil)).Return(nil)
	s.rcf.EXPECT().ClientFromRepoGID(mock.Anything, testRepoGlobalID).Return(s.rcm, nil)

	count, err := s.svc.CancelAllWorkflowsForActorIDExludeRepoIDs(ctx, testActorGlobalID, []types.GlobalID{})

	s.NoError(err)
	s.NotNil(count)
	s.Equal(int64(2), count)
	s.wbr.AssertExpectations(s.T())
}

func (s *workflowCancelerTestSuite) Test_FailedCancellation_ForActorIDExludeRepoIDs() {
	ctx := context.Background()

	executionID := types.NewRandomWorkflowExecutionID()
	executionID2 := types.NewRandomWorkflowExecutionID()
	executionID3 := types.NewRandomWorkflowExecutionID()

	workflowMetadata := &metadata.WorkflowMetadata{
		RepositoryOwner: &metadata.WorkflowMetadataUser{
			ID:            uint32(testActorID),
			GlobalRelayID: testActorGlobalID.String(),
		},
	}

	states := []*deployer.WorkflowBuildState{
		{
			DatabaseID:       1,
			State:            build.WorkflowStateQueued,
			ExternalBuildID:  "12",
			RepositoryID:     testRepoGlobalID,
			ExecutionID:      executionID,
			WorkflowMetadata: workflowMetadata,
		},
		{
			DatabaseID:       2,
			State:            build.WorkflowStateStarted,
			ExternalBuildID:  "13",
			RepositoryID:     testRepoGlobalID,
			ExecutionID:      executionID2,
			WorkflowMetadata: workflowMetadata,
		},
		{
			DatabaseID:       3,
			State:            build.WorkflowStateStarted,
			ExternalBuildID:  "14",
			RepositoryID:     testRepoGlobalID,
			ExecutionID:      executionID3,
			WorkflowMetadata: workflowMetadata,
		},
	}
	testActorGlobalID := types.GlobalID("user-1")
	s.wbr.EXPECT().GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(mock.Anything, testActorGlobalID, []types.GlobalID{}, mock.Anything, int64(-1)).Return(states, nil).Once()
	s.hyd.EXPECT().EmitWorkflowCancelRequest(mock.Anything).Return()

	s.rcm.EXPECT().Cancel(mock.Anything, "12", (*azp.CancelOptions)(nil)).Return(errors.New("test error 1")).Times(1)
	s.rcm.EXPECT().Cancel(mock.Anything, "13", (*azp.CancelOptions)(nil)).Return(nil).Times(1)
	s.rcm.EXPECT().Cancel(mock.Anything, "14", (*azp.CancelOptions)(nil)).Return(errors.New("test error 2")).Times(1)

	s.rcf.EXPECT().ClientFromRepoGID(mock.Anything, testRepoGlobalID).Return(s.rcm, nil)

	count, err := s.svc.CancelAllWorkflowsForActorIDExludeRepoIDs(ctx, testActorGlobalID, []types.GlobalID{})

	s.Error(err)
	s.Contains(err.Error(), "2 errors occurred")
	s.Contains(err.Error(), "test error 1")
	s.Contains(err.Error(), "test error 2")
	s.NotNil(count)
	s.Equal(int64(1), count)
	s.wbr.AssertExpectations(s.T())
	s.rcm.AssertExpectations(s.T())
	s.mockHealer.AssertExpectations(s.T())
}
