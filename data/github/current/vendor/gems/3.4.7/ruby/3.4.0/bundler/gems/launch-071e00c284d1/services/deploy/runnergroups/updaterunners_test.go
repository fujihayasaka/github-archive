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

type updateRunnerTestSuite struct {
	suite.Suite

	svc *service

	rrc *azp.MockRepositoryClient
}

func TestUpdateRunnersTestSuite(t *testing.T) {
	suite.Run(t, new(updateRunnerTestSuite))
}

func (s *updateRunnerTestSuite) SetupTest() {
	arr := &db.MockAzpResourcesRepository{}
	arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	runnerGroup := mockRunnerGroup()
	s.rrc = &azp.MockRepositoryClient{}
	s.rrc.On("UpdateGroupRunners", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	rcf := &azp.MockRepositoryClientFactory{}
	rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: rcf,
		azpResourceRepo:      arr,
	}
}

func (s *updateRunnerTestSuite) TestServiceWillUpdateRunnersInAGroup() {
	req := &UpdateRunnersRequest{
		OwnerId:           &pbtypes.Identity{GlobalId: "owner"},
		GroupId:           2,
		RunnerIds:         []int64{1, 2, 3},
		IsEnterpriseOwner: false,
	}

	res, err := s.svc.UpdateRunners(context.Background(), req)
	s.Require().NoError(err)
	s.rrc.AssertCalled(s.T(), "UpdateGroupRunners", mock.Anything, req.GroupId, req.RunnerIds)
	s.Assert().NotNil(res)
}
