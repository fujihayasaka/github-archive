package runnergroups

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	db "github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type createGroupTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *db.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestCreateGroupTestSuite(t *testing.T) {
	suite.Run(t, new(createGroupTestSuite))
}

func (s *createGroupTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &db.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: s.rcf,
		azpResourceRepo:      s.arr,
	}
}

func (s *createGroupTestSuite) TestServiceWillCreateARunnerGroup() {
	runnerGroup := mockRunnerGroup()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("CreateGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)

	req := &CreateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Name:       runnerGroup.Name,
		Visibility: Visibility_ALL,
		RunnerIds:  []int64{1, 2, 3, 4},
	}

	res, err := s.svc.CreateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetId(), runnerGroup.ID)
	s.Equal(res.RunnerGroup.GetName(), runnerGroup.Name)
	s.Equal(res.RunnerGroup.GetVisibility(), Visibility_ALL)
}
