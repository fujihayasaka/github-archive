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

type createPoolTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestCreatePoolTestSuite(t *testing.T) {
	suite.Run(t, new(createPoolTestSuite))
}

func (s *createPoolTestSuite) SetupTest() {
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

func (s *createPoolTestSuite) TestServiceWillReturnRunnerPool() {
	runnerPool := mockRunnerPool(false)

	poolID := runnerPool.ID
	requestedMaxRunners := int64(2)

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("CreateRunnerPool", mock.Anything, mock.Anything).Return(runnerPool, nil)

	imageKey := &ImageKey{
		Source:  ImageKey_Curated,
		Id:      "testimage",
		Version: "latest",
	}

	req := &CreatePoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Name:              "MyCoolPool",
		Platform:          "linux",
		RunnerGroupId:     poolID,
		Labels:            make([]string, 0),
		Image:             imageKey,
		IsPublicIpEnabled: false,
		MaximumRunners:    requestedMaxRunners,
		PersistentOsDisk:  false,
	}

	res, err := s.svc.CreatePool(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("MyCoolPool", res.Pool.GetName())
	s.Equal(PoolState_Provisioning, res.Pool.GetState())
	s.Equal("linux", res.Pool.GetPlatform())
	s.Equal(int64(1), res.Pool.GetRunnerGroupId())
	s.Equal(make([]string, 0), res.Pool.GetLabels())
	s.Equal(false, res.Pool.GetPublicIpEnabled())
	s.Equal(runnerPool.MaximumRunners, res.Pool.GetMaximumRunners())
	s.Equal(false, res.Pool.GetPersistentOsDisk())
	s.Equal("", res.Pool.ErrorCode)
}

func (s *createPoolTestSuite) TestServiceWillCreateImage() {
	runnerPool := mockRunnerPool(false)
	image := mockImage()

	latestVersion := "1.0.0"
	imageDef := mockImageDefinition(&latestVersion)

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("CreateImageDefinition", mock.Anything, mock.Anything, mock.Anything).Return(imageDef, nil)
	s.rrc.On("CreateImageVersion", mock.Anything, mock.Anything, mock.Anything).Return(image, nil)
	s.rrc.On("CreateRunnerPool", mock.Anything, mock.Anything).Return(runnerPool, nil)

	imageKey := &ImageKey{
		Id:      "",
		Version: "latest",
		Source:  ImageKey_Custom,
	}

	req := &CreatePoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Name:              "MyCoolPool",
		Platform:          "linux",
		RunnerGroupId:     1,
		Labels:            make([]string, 0),
		Image:             imageKey,
		IsPublicIpEnabled: false,
		ImageSasUri:       "test://uri",
		MaximumRunners:    1,
		PersistentOsDisk:  false,
	}

	res, err := s.svc.CreatePool(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("MyCoolPool", res.Pool.GetName())
	s.Equal(PoolState_Provisioning, res.Pool.GetState())
	s.Equal("linux", res.Pool.GetPlatform())
	s.Equal(int64(1), res.Pool.GetRunnerGroupId())
	s.Equal(make([]string, 0), res.Pool.GetLabels())
	s.Equal(false, res.Pool.GetPublicIpEnabled())
	s.Equal(runnerPool.MaximumRunners, res.Pool.GetMaximumRunners())
	s.Equal(false, res.Pool.GetPersistentOsDisk())
}

func (s *createPoolTestSuite) TestServiceWillCreateImageWithExistingCustomImage() {
	runnerPool := mockRunnerPool(false)

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("CreateRunnerPool", mock.Anything, mock.Anything).Return(runnerPool, nil)

	imageKey := &ImageKey{
		Id:      "1",
		Version: "latest",
		Source:  ImageKey_Custom,
	}

	req := &CreatePoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Name:              "MyCoolPool",
		Platform:          "linux",
		RunnerGroupId:     1,
		Labels:            make([]string, 0),
		Image:             imageKey,
		IsPublicIpEnabled: false,
		ImageSasUri:       "",
		MaximumRunners:    1,
	}

	res, err := s.svc.CreatePool(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("MyCoolPool", res.Pool.GetName())
	s.Equal(PoolState_Provisioning, res.Pool.GetState())
	s.Equal("linux", res.Pool.GetPlatform())
	s.Equal(int64(1), res.Pool.GetRunnerGroupId())
	s.Equal(make([]string, 0), res.Pool.GetLabels())
	s.Equal(false, res.Pool.GetPublicIpEnabled())
	s.Equal(runnerPool.MaximumRunners, res.Pool.GetMaximumRunners())
}

func (s *createPoolTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &CreatePoolRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.CreatePool(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockRunnerPool(publicIpEnabled bool) *azp.RunnerPool {
	publicIP := azp.PublicIP{
		Enabled: publicIpEnabled,
	}

	imageKey := azp.ImageKey{
		ID:      "1",
		Version: "latest",
		Source:  "Custom",
	}

	publicIPs := make([]azp.PublicIP, 0)
	publicIPs = append(publicIPs, publicIP)

	return &azp.RunnerPool{
		ID:              1,
		Name:            "MyCoolPool",
		State:           "Provisioning",
		Platform:        "linux",
		RunnerGroupID:   1,
		Labels:          make([]string, 0),
		Ephemeral:       true,
		RunnerCount:     1,
		PublicIPs:       publicIPs,
		MaximumRunners:  10,
		Image:           imageKey,
		PublicIPEnabled: publicIpEnabled,
	}
}

func mockImage() *azp.ImageVersion {
	return &azp.ImageVersion{
		Version:           "1.0.0",
		ImageDefinitionID: 1,
	}
}

func mockImageDefinition(latestVersion *string) *azp.ImageDefinition {
	return &azp.ImageDefinition{
		ID:                               1,
		Name:                             "ImageDefinition",
		OsType:                           "Linux",
		ImageDefinitionVersionCount:      3,
		ImageDefinitionTotalVersionsSize: 30,
		ImageDefinitionLatestVersion:     latestVersion,
		Platform:                         "linux-x64",
	}
}
