package largerrunners

import (
	context "context"
	"testing"
	"time"

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

type updatePoolTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestUpdatePoolTestSuite(t *testing.T) {
	suite.Run(t, new(updatePoolTestSuite))
}

func (s *updatePoolTestSuite) SetupTest() {
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

func (s *updatePoolTestSuite) TestServiceWillReturnRunnerPools() {
	runnerPool := mockRunnerPool(false)

	poolID := runnerPool.ID
	requestedMaxRunners := int64(2)

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateRunnerPool", mock.Anything, poolID, mock.Anything).Return(runnerPool, nil)

	imageKey := &ImageKey{
		Source:  ImageKey_Custom,
		Id:      "1",
		Version: "1.0.0",
	}

	req := &UpdatePoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PoolId:            poolID,
		Name:              "MyPoolPool",
		Platform:          "linux",
		RunnerGroupId:     1,
		Labels:            make([]string, 0),
		IsPublicIpEnabled: false,
		MaximumRunners:    requestedMaxRunners,
		Image:             imageKey,
	}

	res, err := s.svc.UpdatePool(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(poolID, res.Pool.GetId())
	s.Equal("MyCoolPool", res.Pool.GetName())
	s.Equal(PoolState_Provisioning, res.Pool.GetState())
	s.Equal("linux", res.Pool.GetPlatform())
	s.Equal(int64(1), res.Pool.GetRunnerGroupId())
	s.Equal(make([]string, 0), res.Pool.GetLabels())
	s.Equal(false, res.Pool.GetPublicIpEnabled())
	s.Equal(int64(10), res.Pool.GetMaximumRunners())
	s.Equal("latest", res.Pool.GetImage().Version)
}

func (s *updatePoolTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &UpdatePoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.UpdatePool(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockImageVersion() *azp.ImageVersion {
	size := int32(30)
	lastUsedOn := "2024-01-01T00:00:00Z"

	return &azp.ImageVersion{
		ImageDefinitionID:               2,
		Version:                         "2.0.0",
		ImageVersionState:               "ImportingBlob",
		ImageVersionImportFailureReason: "",
		ImageVersionCreatedOn:           time.Now(),
		ImageVersionSize:                &size,
		ImageVersionLastUsedOn:          &lastUsedOn,
	}
}
