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

type getPoolTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestGetPoolTestSuite(t *testing.T) {
	suite.Run(t, new(getPoolTestSuite))
}

func (s *getPoolTestSuite) SetupTest() {
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

func (s *getPoolTestSuite) TestServiceWillReturnRunnerPool() {
	runnerPool := mockRunnerPool(false)

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunnerPool", mock.Anything, mock.Anything).Return(runnerPool, nil)

	req := &GetPoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PoolId: 1,
	}

	res, err := s.svc.GetPool(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())

	s.Equal(PoolState_Provisioning, res.Pool.State)
	s.Equal("MyCoolPool", res.Pool.Name)
}

func (s *getPoolTestSuite) TestServiceWillReturnRunnerPoolWithPublicIPs() {
	runnerPool := mockRunnerPool(true)

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunnerPool", mock.Anything, mock.Anything).Return(runnerPool, nil)

	req := &GetPoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PoolId: 1,
	}

	res, err := s.svc.GetPool(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())

	s.Equal(PoolState_Provisioning, res.Pool.State)
	s.Equal("MyCoolPool", res.Pool.Name)

	s.True(res.Pool.PublicIpEnabled)
	s.Equal(1, len(res.Pool.PublicIps))
	s.True(res.Pool.PublicIps[0].Enabled)
}

func (s *getPoolTestSuite) TestServiceWillReturnRunnerPoolWithStuck() {
	runnerPool := mockRunnerPoolStuck()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunnerPool", mock.Anything, mock.Anything).Return(runnerPool, nil)

	req := &GetPoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PoolId: 1,
	}

	res, err := s.svc.GetPool(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())

	s.Equal(PoolState_Stuck, res.Pool.State)
}

func (s *getPoolTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &GetPoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PoolId: 1,
	}

	res, err := s.svc.GetPool(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockRunnerPoolStuck() *azp.RunnerPool {
	return &azp.RunnerPool{
		ID:              1,
		Name:            "MyCoolPool",
		State:           "Stuck",
		Platform:        "linux",
		RunnerGroupID:   1,
		Labels:          make([]string, 0),
		RunnerCount:     1,
		PublicIPEnabled: false,
		MaximumRunners:  10,
	}
}
