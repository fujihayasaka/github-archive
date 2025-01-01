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

type removeRunnerTestSuite struct {
	suite.Suite

	svc *service

	rrc *azp.MockRepositoryClient
}

func TestRemoveRunnerTestSuite(t *testing.T) {
	suite.Run(t, new(removeRunnerTestSuite))
}

func (s *removeRunnerTestSuite) SetupTest() {
	arr := &db.MockAzpResourcesRepository{}
	arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	runnerGroup := mockRunnerGroup()
	s.rrc = &azp.MockRepositoryClient{}
	s.rrc.On("RemoveRunner", mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	rcf := &azp.MockRepositoryClientFactory{}
	rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: rcf,
		azpResourceRepo:      arr,
	}
}

func (s *removeRunnerTestSuite) TestServiceWillRemoveARunner() {
	req := &RemoveRunnerRequest{
		OwnerId:  &pbtypes.Identity{GlobalId: "owner"},
		GroupId:  2,
		RunnerId: 3,
	}

	res, err := s.svc.RemoveRunner(context.Background(), req)
	s.Require().NoError(err)
	s.rrc.AssertCalled(s.T(), "RemoveRunner", mock.Anything, req.GroupId, req.RunnerId)
	s.Assert().NotNil(res)
}
