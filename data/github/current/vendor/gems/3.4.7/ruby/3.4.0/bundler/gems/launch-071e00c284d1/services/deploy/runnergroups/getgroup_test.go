package runnergroups

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type getGroupTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestGetGroupTestSuite(t *testing.T) {
	suite.Run(t, new(getGroupTestSuite))
}

func (s *getGroupTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &deployer.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: s.rcf,
		azpResourceRepo:      s.arr,
	}
}

func (s *getGroupTestSuite) TestServiceWillReturnRunnerGroup() {
	runnerGroup := mockRunnerGroup()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)

	req := &GetGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		GroupId: 123,
	}

	res, err := s.svc.GetGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetId(), runnerGroup.ID)
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), false)
	s.Equal(res.RunnerGroup.GetRestrictedToWorkflows(), true)
	s.Equal(res.RunnerGroup.GetAllowPublic(), true)
}

func mockRunnerGroup() *azp.RunnerGroup {
	return &azp.RunnerGroup{
		ID:           1,
		Name:         "MazeGroup",
		OwningTenant: "ownerId",
		Visibility: azp.Visibility{
			VisibilityType:        "all",
			AllowPublic:           true,
			SelectedWorkflowRefs:  make([]string, 0),
			RestrictedToWorkflows: true,
		},
	}
}
