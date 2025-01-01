package largerrunners

import (
	context "context"
	"testing"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type deletePoolTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestDeletePoolTestSuite(t *testing.T) {
	suite.Run(t, new(deletePoolTestSuite))
}

func (s *deletePoolTestSuite) SetupTest() {
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

func (s *deletePoolTestSuite) TestServiceWillReturnWithNoError() {
	runnerPool := mockRunnerPool(false)
	runnerPool.State = "Deleting"

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteRunnerPool", mock.Anything, mock.Anything).Return(runnerPool, nil)

	req := &DeletePoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PoolId: 1,
	}

	res, err := s.svc.DeletePool(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.Equal(runnerPool.ID, res.Pool.GetId())
	s.Equal(runnerPool.State, res.Pool.GetState().String())
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *deletePoolTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &DeletePoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PoolId: 1,
	}

	res, err := s.svc.DeletePool(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}
