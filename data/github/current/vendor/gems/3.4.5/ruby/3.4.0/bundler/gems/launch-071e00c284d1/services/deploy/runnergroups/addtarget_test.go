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
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type addTargetTestSuite struct {
	suite.Suite

	svc *service

	rrc *azp.MockRepositoryClient
}

func TestAddTargetTestSuite(t *testing.T) {
	suite.Run(t, new(addTargetTestSuite))
}

func (s *addTargetTestSuite) SetupTest() {
	arr := &db.MockAzpResourcesRepository{}
	arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	visibility := &azp.Visibility{
		SelectedTargets: []types.GlobalID{"foo", "bar"},
	}
	s.rrc = &azp.MockRepositoryClient{}
	s.rrc.On("AddTarget", mock.Anything, mock.Anything, mock.Anything).Return(visibility, nil)
	rcf := &azp.MockRepositoryClientFactory{}
	rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: rcf,
		azpResourceRepo:      arr,
	}
}

func (s *addTargetTestSuite) TestServiceWillAddATarget() {
	req := &AddTargetRequest{
		OwnerId:  &pbtypes.Identity{GlobalId: "owner"},
		GroupId:  2,
		TargetId: &pbtypes.Identity{GlobalId: "repository"},
	}

	res, err := s.svc.AddTarget(context.Background(), req)
	s.Require().NoError(err)
	s.rrc.AssertCalled(s.T(), "AddTarget", mock.Anything, req.GroupId, req.TargetId)
	s.Assert().NotNil(res)
}
