package deploy

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/services/deploy/workflowcanceler"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils"
)

const (
	testCheckSuiteID    = "CheckSuiteID"
	testExternalBuildID = "1234567890"

	testActorName     = "monalisa"
	testActorID       = 2
	testActorGlobalID = "U_kgAC"
)

func TestDeployer_WorkflowCancel(t *testing.T) {
	suite.Run(t, new(WorkflowCancelSuite))
}

type WorkflowCancelSuite struct {
	suite.Suite
	svc           *service
	db            *deployer.MockWorkflowBuildsRepository
	canceler      *workflowcanceler.MockCanceler
	ghtwirpClient *ghtwirp.MockClient
}

func (s *WorkflowCancelSuite) SetupTest() {
	log := logger.TestLogger()
	nullStatter := statter.NullStatter()
	publisher := &events.MockPublisher{}
	emitter, err := events.NewEmitter(
		events.WithPublisher(publisher),
		events.WithLogger(log),
		events.WithStatter(nullStatter),
	)
	s.Require().NoError(err)

	s.ghtwirpClient = &ghtwirp.MockClient{}
	s.ghtwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(
		func(ctx context.Context, globalID string) types.GlobalID {
			if globalID == "" {
				return types.NilGlobalID
			}
			return types.GlobalID(globalID)
		}, nil)

	s.canceler = &workflowcanceler.MockCanceler{}

	s.db = &deployer.MockWorkflowBuildsRepository{}
	s.svc = &service{
		cfg: config{
			Log:               log,
			Stats:             nullStatter,
			Obs:               observability.New(log, nullStatter),
			Events:            emitter,
			WorkflowCanceler:  s.canceler,
			WorkflowBuilds:    s.db,
			WorkflowFilePath:  utils.DefaultWorkflowFilePath,
			GithubTwirpClient: s.ghtwirpClient,
		},
	}
	migrator := deployer.NewGlobalIDMigrator(s.ghtwirpClient)
	s.svc.gidMigrator = migrator
}

func (s *WorkflowCancelSuite) TestMissingCheckSuiteID() {
	ctx := context.Background()
	_, err := s.svc.WorkflowCancel(ctx, &pb.WorkflowCancelRequest{})
	s.Assert().Error(err)
}

func (s *WorkflowCancelSuite) TestCancelBuild() {
	ctx := context.Background()
	checkSuiteID := types.IdentityFromGlobalID(testCheckSuiteID)

	wfState := &deployer.WorkflowBuildState{
		CheckSuiteID:    types.IdentityToGlobalID(ctx, checkSuiteID),
		ExternalBuildID: testExternalBuildID,
	}

	s.db.On("GetWorkflowBuildStateByCheckSuiteID", mock.Anything, mock.Anything).Return(wfState, true, nil)

	testActorCopy := testActorName
	s.canceler.On("Cancel", mock.Anything, wfState, &azp.CancelOptions{
		ActorName: &testActorCopy,
		Force:     false,
	}).Return(nil)

	_, err := s.svc.WorkflowCancel(ctx, &pb.WorkflowCancelRequest{
		CheckSuiteId:       types.IdentityFromGlobalID(types.IdentityToGlobalID(ctx, checkSuiteID)),
		CanceledById:       testActorID,
		CanceledByName:     testActorName,
		CanceledByGlobalId: types.IdentityFromGlobalID(testActorGlobalID),
	})

	s.Assert().NoError(err)
	s.db.AssertExpectations(s.T())
	s.canceler.AssertExpectations(s.T())
}

func (s *WorkflowCancelSuite) TestForceCancelBuild() {
	ctx := context.Background()
	checkSuiteID := types.IdentityFromGlobalID(testCheckSuiteID)

	wfState := &deployer.WorkflowBuildState{
		CheckSuiteID:    types.IdentityToGlobalID(ctx, checkSuiteID),
		ExternalBuildID: testExternalBuildID,
	}

	s.db.On("GetWorkflowBuildStateByCheckSuiteID", mock.Anything, mock.Anything).Return(wfState, true, nil)

	testActorCopy := testActorName
	s.canceler.On("Cancel", mock.Anything, wfState, &azp.CancelOptions{
		ActorName: &testActorCopy,
		Force:     true,
	}).Return(nil)

	_, err := s.svc.WorkflowCancel(ctx, &pb.WorkflowCancelRequest{
		CheckSuiteId:       types.IdentityFromGlobalID(types.IdentityToGlobalID(ctx, checkSuiteID)),
		CanceledById:       testActorID,
		CanceledByName:     testActorName,
		CanceledByGlobalId: types.IdentityFromGlobalID(testActorGlobalID),
		Force:              true,
	})

	s.Assert().NoError(err)
	s.db.AssertExpectations(s.T())
	s.canceler.AssertExpectations(s.T())
}

func (s *WorkflowCancelSuite) TestUnknownCheckSuiteId() {
	ctx := context.Background()

	s.db.On("GetWorkflowBuildStateByCheckSuiteID", mock.Anything, mock.Anything).Return(nil, false, nil)

	_, err := s.svc.WorkflowCancel(ctx, &pb.WorkflowCancelRequest{
		CheckSuiteId: types.IdentityFromGlobalID(testCheckSuiteID),
	})

	s.Assert().Error(err)
	s.db.AssertExpectations(s.T())
}

func (s *WorkflowCancelSuite) TestDatabaseError() {
	ctx := context.Background()

	s.db.On("GetWorkflowBuildStateByCheckSuiteID", mock.Anything, mock.Anything).Return(nil, false, errors.New("Unknown Database Error"))

	_, err := s.svc.WorkflowCancel(ctx, &pb.WorkflowCancelRequest{
		CheckSuiteId: types.IdentityFromGlobalID(testCheckSuiteID),
	})

	s.Assert().Error(err)
	s.db.AssertExpectations(s.T())
}

func (s *WorkflowCancelSuite) TestCancelBuildError() {
	ctx := context.Background()

	checkSuiteID := types.IdentityFromGlobalID(testCheckSuiteID)

	wfState := &deployer.WorkflowBuildState{
		CheckSuiteID:    types.IdentityToGlobalID(ctx, checkSuiteID),
		ExternalBuildID: testExternalBuildID,
	}

	s.db.On("GetWorkflowBuildStateByCheckSuiteID", mock.Anything, mock.Anything).Return(wfState, true, nil)

	s.canceler.On("Cancel", mock.Anything, wfState, &azp.CancelOptions{}).Return(errors.New("Unknown AZP Error"))

	_, err := s.svc.WorkflowCancel(ctx, &pb.WorkflowCancelRequest{
		CheckSuiteId: types.IdentityFromGlobalID(testExternalBuildID),
	})

	s.Assert().Error(err)
	s.db.AssertExpectations(s.T())
	s.canceler.AssertExpectations(s.T())
}
