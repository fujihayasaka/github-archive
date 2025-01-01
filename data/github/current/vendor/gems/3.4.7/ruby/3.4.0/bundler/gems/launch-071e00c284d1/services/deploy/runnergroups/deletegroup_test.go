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

type deleteGroupTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *db.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestDeleteGroupTestSuite(t *testing.T) {
	suite.Run(t, new(deleteGroupTestSuite))
}

func (s *deleteGroupTestSuite) SetupTest() {
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

func (s *deleteGroupTestSuite) TestServiceWillDeleteARunnerGroup() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteGroup", mock.Anything, mock.Anything, mock.Anything).Return(nil)

	req := &DeleteGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		GroupId: 123,
	}

	res, err := s.svc.DeleteGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.GetStatus(), "deleted")
}
