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

type DisableScheduledWorkflowSuite struct {
	suite.Suite
	svc          *service
	ghtwirp      *ghtwirp.MockClient
	scheduleMngr *schedulemanager.MockManager
}

func TestDeployer_DisableScheduledWorkflowSuite(t *testing.T) {
	suite.Run(t, new(DisableScheduledWorkflowSuite))
}

func (s *DisableScheduledWorkflowSuite) SetupTest() {
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

func (s *DisableScheduledWorkflowSuite) Test_DisableScheduledWorkflow() {
	ctx := context.Background()

	repositoryID := "repo-id"
	environment := "production"
	workflowFilePath := ".github/workflows/production.yml"

	s.scheduleMngr.On("DisableScheduledWorkflow", mock.Anything, &launchtypes.DisableScheduledWorkflowRequest{
		Environment: environment,
		RepositoryNodeId: &pbtypes.Identity{
			GlobalId: types.GlobalID(repositoryID).String(),
		},
		WorkflowFilePath: workflowFilePath,
	}).Return(nil, nil)

	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		return types.GlobalID(globalID)
	}, nil)

	res, err := s.svc.DisableScheduledWorkflow(ctx, &launchtypes.DisableScheduledWorkflowRequest{
		Environment: environment,
		RepositoryNodeId: &pbtypes.Identity{
			GlobalId: repositoryID,
		},
		WorkflowFilePath: workflowFilePath,
	})

	s.NoError(err)
	s.Nil(res)
	s.scheduleMngr.AssertExpectations(s.T())
	s.ghtwirp.AssertExpectations(s.T())
}
