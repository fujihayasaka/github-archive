package workflowcanceler

import (
	"context"
	"testing"
	"time"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/build"
)

var (
	testActorID            int64 = 16991201
	testActorGlobalID            = types.GlobalID(testutils.EncodeGlobalID(types.GlobalIDUserType, testActorID))
	testOwnerID            int64 = 1
	testOwnerGlobalID            = types.GlobalID(testutils.EncodeGlobalID(types.GlobalIDOrganizationType, testOwnerID))
	testRepoID             int64 = 3
	testRepoGlobalID             = types.GlobalID(testutils.EncodeGlobalID(types.GlobalIDRepositoryType, testRepoID))
	testCheckSuiteID       int64 = 123
	testCheckSuiteGlobalID       = types.GlobalID(testutils.EncodeGlobalID(types.GlobalIDCheckSuiteType, testCheckSuiteID))
)

func TestWorkflowCanceler(t *testing.T) {
	suite.Run(t, new(workflowCancelerTestSuite))
}

type workflowCancelerTestSuite struct {
	suite.Suite
	mockHealer *mockHealer
	wbr        *deployer.MockWorkflowBuildsRepository
	rcf        *azp.MockRepositoryClientFactory
	rcm        *azp.MockRepositoryClient
	log        testutils.RecordingLogger
	svc        Canceler
	hyd        *mockCancelHydro
	ghTwirp    *ghtwirp.MockClient
}

func (s *workflowCancelerTestSuite) SetupTest() {
	log := testutils.NewRecordingLogger()
	obs := observability.New(log.Logger, statter.NullStatter())

	s.wbr = deployer.NewMockWorkflowBuildsRepository(s.T())
	s.rcf = azp.NewMockRepositoryClientFactory(s.T())
	s.rcm = azp.NewMockRepositoryClient(s.T())
	s.hyd = newMockCancelHydro(s.T())
	s.ghTwirp = ghtwirp.NewMockClient(s.T())
	s.log = log
	s.mockHealer = newMockHealer(s.T())
	s.svc = NewWorkflowCanceler(obs, s.mockHealer, s.wbr, s.rcf, s.hyd, s.ghTwirp)
}

func (s *workflowCancelerTestSuite) TestAZPClientIsCalled() {
	ctx := context.TODO()
	executionID := types.NewRandomWorkflowExecutionID()
	wfb := &deployer.WorkflowBuildState{
		RepositoryID:    testRepoGlobalID,
		CheckSuiteID:    testCheckSuiteGlobalID,
		DatabaseID:      1,
		ExternalBuildID: "3",
		ExecutionID:     executionID,
	}
	s.hyd.EXPECT().EmitWorkflowCancelRequest(mock.MatchedBy(func(cr *hydroV0.WorkflowCancelRequest) bool {
		t := cr.RequestedAt.AsTime()
		s.True(time.Since(t).Abs() < time.Second, "unexpected requested at")
		r := *cr
		r.RequestedAt = nil
		s.Equal(hydroV0.WorkflowCancelRequest{
			RequestedAt:                nil,
			ExternalProviderReference:  "3",
			WorkflowBuildId:            1,
			WorkflowRepositoryGlobalId: testRepoGlobalID.String(),
			WorkflowRepositoryId:       uint64(testRepoID),
			CheckSuiteGlobalId:         testCheckSuiteGlobalID.String(),
			CancelFailureReason:        healingSkipped,
		}, r)
		return true
	}))
	s.rcm.EXPECT().Cancel(mock.Anything, "3", (*azp.CancelOptions)(nil)).Return(nil)
	s.rcf.EXPECT().ClientFromRepoGID(mock.Anything, wfb.RepositoryID).Return(s.rcm, nil)
	err := s.svc.Cancel(ctx, wfb, nil)
	s.NoError(err)
}

func (s *workflowCancelerTestSuite) TestHandlesMissingExternalID() {
	ctx := context.TODO()
	wfb := &deployer.WorkflowBuildState{
		RepositoryID:    testRepoGlobalID,
		DatabaseID:      1,
		State:           build.WorkflowStateNone,
		ExternalBuildID: "",
	}
	s.hyd.EXPECT().EmitWorkflowCancelRequest(mock.MatchedBy(func(cr *hydroV0.WorkflowCancelRequest) bool {
		s.Equal(notRequested, cr.CancelFailureReason)
		return true
	}))
	err := s.svc.Cancel(ctx, wfb, nil)
	s.EqualError(err, "unable to cancel this workflow, external build identifier is empty")
	s.hyd.AssertExpectations(s.T())
}

func (s *workflowCancelerTestSuite) TestFailureFromCancelService() {
	ctx := context.TODO()
	wfb := &deployer.WorkflowBuildState{
		RepositoryID:    testRepoGlobalID,
		CheckSuiteID:    testCheckSuiteGlobalID,
		DatabaseID:      1,
		ExternalBuildID: "3",
	}
	s.hyd.EXPECT().EmitWorkflowCancelRequest(mock.MatchedBy(func(cr *hydroV0.WorkflowCancelRequest) bool {
		s.Equal(cancelFailed, cr.CancelFailureReason)
		return true
	}))
	s.rcm.EXPECT().Cancel(mock.Anything, "3", (*azp.CancelOptions)(nil)).Return(errs.New("boom"))
	s.rcf.EXPECT().ClientFromRepoGID(mock.Anything, wfb.RepositoryID).Return(s.rcm, nil)
	err := s.svc.Cancel(ctx, wfb, nil)
	s.Error(err)
}

func (s *workflowCancelerTestSuite) TestHandlesAlreadyCompletedRunAlwaysSkips() {
	ctx := context.TODO()
	executionID := types.NewRandomWorkflowExecutionID()
	wfb := &deployer.WorkflowBuildState{
		RepositoryID:    testRepoGlobalID,
		DatabaseID:      1,
		ExternalBuildID: "3",
		ExecutionID:     executionID,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID:            uint32(testOwnerID),
				GlobalRelayID: testOwnerGlobalID.String(),
			},
		},
	}
	s.hyd.EXPECT().EmitWorkflowCancelRequest(mock.MatchedBy(func(cr *hydroV0.WorkflowCancelRequest) bool {
		s.Equal(healingSkipped, cr.CancelFailureReason)
		return true
	}))
	s.rcm.EXPECT().Cancel(mock.Anything, "3", (*azp.CancelOptions)(nil)).Return(nil)
	s.rcf.EXPECT().ClientFromRepoGID(mock.Anything, wfb.RepositoryID).Return(s.rcm, nil)
	err := s.svc.Cancel(ctx, wfb, nil)
	s.NoError(err)
}
