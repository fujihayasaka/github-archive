package largerrunners

import (
	"context"
	"testing"

	"github.com/golang/protobuf/ptypes/wrappers"
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

type createImageVersionTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestCreateImageVersionTestSuite(t *testing.T) {
	suite.Run(t, new(createImageVersionTestSuite))
}

func (s *createImageVersionTestSuite) SetupTest() {
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

func (s *createImageVersionTestSuite) TestServiceWillReturnImageVersion() {
	imageVersion := mockImageVersion()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("CreateImageVersion", mock.Anything, mock.Anything, mock.Anything).Return(imageVersion, nil)

	req := &CreateImageVersionRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		ImageDefinitionId: 2,
		ImageSasUri:       "test://uri",
	}

	res, err := s.svc.CreateImageVersion(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.ImageVersion.Version, imageVersion.Version)
	s.Equal(res.ImageVersion.State, ImageVersion_ImageState(0)) // 0 means ImportingBlob state
	s.NotNil(res.ImageVersion.CreatedOn)
	s.Equal(res.ImageVersion.Size, &wrappers.Int32Value{Value: *imageVersion.ImageVersionSize})
}

func (s *createImageVersionTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &CreateImageVersionRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		ImageDefinitionId: 2,
		ImageSasUri:       "test://uri",
	}

	res, err := s.svc.CreateImageVersion(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}
