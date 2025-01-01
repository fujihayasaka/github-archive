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
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type addRunnersTestSuite struct {
	suite.Suite

	svc *service

	rrc *azp.MockRepositoryClient
}

func TestAddRunnersTestSuite(t *testing.T) {
	suite.Run(t, new(addRunnersTestSuite))
}

func (s *addRunnersTestSuite) SetupTest() {
	arr := &db.MockAzpResourcesRepository{}
	arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	runnerGroup := mockRunnerGroup()
	s.rrc = &azp.MockRepositoryClient{}
	s.rrc.On("AddRunners", mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	rcf := &azp.MockRepositoryClientFactory{}
	rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: rcf,
		azpResourceRepo:      arr,
	}
}

func (s *addRunnersTestSuite) TestServiceWillAddARunner() {
	req := &AddRunnersRequest{
		OwnerId:   &pbtypes.Identity{GlobalId: "owner"},
		GroupId:   2,
		RunnerIds: []int64{1, 2, 3},
	}

	res, err := s.svc.AddRunners(context.Background(), req)
	s.Require().NoError(err)
	s.rrc.AssertCalled(s.T(), "AddRunners", mock.Anything, req.GroupId, req.RunnerIds)
	s.Assert().NotNil(res)
}
