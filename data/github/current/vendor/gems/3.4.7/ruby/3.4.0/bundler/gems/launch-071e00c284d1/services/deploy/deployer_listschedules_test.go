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

type ListWorkflowSchedulesSuite struct {
	suite.Suite
	svc          *service
	ghtwirp      *ghtwirp.MockClient
	scheduleMngr *schedulemanager.MockManager
}

func TestDeployer_ListWorkflowSchedulesSuite(t *testing.T) {
	suite.Run(t, new(ListWorkflowSchedulesSuite))
}

func (s *ListWorkflowSchedulesSuite) SetupTest() {
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

func (s *ListWorkflowSchedulesSuite) Test_Success() {
	ctx := context.Background()

	s.scheduleMngr.On("ListSchedules", mock.Anything, &launchtypes.ListSchedulesRequest{
		Environment: "Test",
		RepositoryNodeId: &pbtypes.Identity{
			GlobalId: types.GlobalID(repositoryID).String(),
		},
	}).Return(&launchtypes.ListSchedulesResponse{
		WorkflowSchedules: []*launchtypes.WorkflowSchedule{
			{
				Id:                 42,
				RepositoryNodeId:   &pbtypes.Identity{GlobalId: repositoryID},
				WorkflowIdentifier: "workflow-one",
				WorkflowFilePath:   "workflow-one-path",
				Environment:        "Test",
				Schedule:           "0 0 * * *",
			},
		},
	}, nil).Once()

	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		return types.GlobalID(globalID)
	}, nil)

	res, err := s.svc.ListSchedules(ctx, &launchtypes.ListSchedulesRequest{
		Environment: "Test",
		RepositoryNodeId: &pbtypes.Identity{
			GlobalId: repositoryID,
		},
	})

	s.NoError(err)
	s.NotNil(res)
	s.scheduleMngr.AssertExpectations(s.T())
	s.ghtwirp.AssertExpectations(s.T())
}
