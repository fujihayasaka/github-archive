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

type updateRunnerTargetsTestSuite struct {
	suite.Suite

	svc *service

	rrc *azp.MockRepositoryClient
}

func TestUpdateTargetsTestSuite(t *testing.T) {
	suite.Run(t, new(updateRunnerTargetsTestSuite))
}

func (s *updateRunnerTargetsTestSuite) SetupTest() {
	arr := &db.MockAzpResourcesRepository{}
	arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	visibility := &azp.Visibility{
		SelectedTargets: []types.GlobalID{"foo", "bar"},
	}
	s.rrc = &azp.MockRepositoryClient{}
	s.rrc.On("UpdateGroupTargets", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(visibility, nil)
	rcf := &azp.MockRepositoryClientFactory{}
	rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: rcf,
		azpResourceRepo:      arr,
	}
}

func (s *updateRunnerTargetsTestSuite) TestServiceWillUpdateTargetsInAGroup() {
	req := &UpdateTargetsRequest{
		OwnerId:   &pbtypes.Identity{GlobalId: "owner"},
		GroupId:   2,
		TargetIds: []*pbtypes.Identity{{GlobalId: "repo"}},
	}

	res, err := s.svc.UpdateTargets(context.Background(), req)
	s.Require().NoError(err)
	s.rrc.AssertCalled(s.T(), "UpdateGroupTargets", mock.Anything, req.GroupId, req.TargetIds)
	s.Assert().NotNil(res)
}
