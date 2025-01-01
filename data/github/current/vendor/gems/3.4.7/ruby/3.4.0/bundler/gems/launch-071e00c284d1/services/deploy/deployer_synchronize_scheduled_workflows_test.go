package deploy

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/schedulemanager"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

const (
	repositoryID   = "R_repo-id"
	userID         = "U_user-id"
	installationID = 321
)

type SynchronizeScheduleWorkflowsSuite struct {
	suite.Suite
	svc          *service
	ghtwirp      *ghtwirp.MockClient
	scheduleMngr *schedulemanager.MockManager
}

func TestDeployer_SynchronizeScheduleWorkflowsSuite(t *testing.T) {
	suite.Run(t, new(SynchronizeScheduleWorkflowsSuite))
}

func (s *SynchronizeScheduleWorkflowsSuite) SetupTest() {
	s.scheduleMngr = &schedulemanager.MockManager{}
	s.ghtwirp = &ghtwirp.MockClient{}
	s.svc = &service{
		cfg: config{
			Obs:                   observability.NewNullObservability(),
			AqueductQueue:         queueName,
			Log:                   logger.TestLogger(),
			GithubTwirpClient:     s.ghtwirp,
			WorkflowSourceFactory: workflowinvoker.NullWorkflowSourceFactory{},
			ScheduleManager:       s.scheduleMngr,
		},
	}
	migrator := deployer.NewGlobalIDMigrator(s.ghtwirp)
	s.svc.gidMigrator = migrator
}

func (s *SynchronizeScheduleWorkflowsSuite) Test_Success() {
	ctx := context.Background()

	s.scheduleMngr.On("SynchronizeScheduledWorkflows", mock.Anything, &launchtypes.SynchronizeScheduledWorkflowsRequest{
		Ref: branchRef.String(),
		RepositoryNodeId: &pbtypes.Identity{
			GlobalId: types.GlobalID(repositoryID).String(),
		},
		InstallationId: int64(installationID),
		ActorNodeId: &pbtypes.Identity{
			GlobalId: types.GlobalID(userID).String(),
		},
	}).Return(nil, nil).Once()

	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		return types.GlobalID(globalID)
	}, nil)

	res, err := s.svc.SynchronizeScheduledWorkflows(ctx, &launchtypes.SynchronizeScheduledWorkflowsRequest{
		Ref: branchRef.String(),
		RepositoryNodeId: &pbtypes.Identity{
			GlobalId: repositoryID,
		},
		InstallationId: int64(installationID),
		ActorNodeId: &pbtypes.Identity{
			GlobalId: userID,
		},
	})

	s.NoError(err)
	s.Nil(res)
	s.scheduleMngr.AssertExpectations(s.T())
	s.ghtwirp.AssertExpectations(s.T())
}
