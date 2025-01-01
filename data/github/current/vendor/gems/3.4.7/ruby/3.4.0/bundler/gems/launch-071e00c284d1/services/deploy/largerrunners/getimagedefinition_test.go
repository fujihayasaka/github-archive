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

type getImageDefinitionTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestGetImageDefinitionTestSuite(t *testing.T) {
	suite.Run(t, new(getImageDefinitionTestSuite))
}

func (s *getImageDefinitionTestSuite) SetupTest() {
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

func (s *getImageDefinitionTestSuite) TestServiceWillReturnImageDefinition() {
	latestVersion := "1.0.0"
	imageDefinition := mockImageDefinition(&latestVersion)
	expectedLatestVersion := &wrappers.StringValue{Value: "1.0.0"}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetImageDefinition", mock.Anything, mock.Anything, mock.Anything).Return(imageDefinition, nil)

	req := &GetImageDefinitionRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "Global_Id",
		},
		ImageDefinitionId: 2,
	}

	res, err := s.svc.GetImageDefinition(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.ImageDefinition.Id, imageDefinition.ID)
	s.Equal(res.ImageDefinition.State, ImageDefinition_ImageDefinitionState(0)) // 0 means Provisioning state
	s.Equal(res.ImageDefinition.VersionCount, imageDefinition.ImageDefinitionVersionCount)
	s.Equal(res.ImageDefinition.TotalVersionsSize, imageDefinition.ImageDefinitionTotalVersionsSize)
	s.Equal(res.ImageDefinition.LatestVersion, expectedLatestVersion)
}

func (s *getImageDefinitionTestSuite) TestServiceWillReturnImageDefinitionWithNilLatestVersion() {
	imageDefinition := mockImageDefinition(nil)
	var expectedLatestVersion *wrappers.StringValue = nil

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetImageDefinition", mock.Anything, mock.Anything, mock.Anything).Return(imageDefinition, nil)

	req := &GetImageDefinitionRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "Global_Id",
		},
		ImageDefinitionId: 2,
	}

	res, err := s.svc.GetImageDefinition(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.ImageDefinition.Id, imageDefinition.ID)
	s.Equal(res.ImageDefinition.State, ImageDefinition_ImageDefinitionState(0)) // 0 means Provisioning state
	s.Equal(res.ImageDefinition.VersionCount, imageDefinition.ImageDefinitionVersionCount)
	s.Equal(res.ImageDefinition.TotalVersionsSize, imageDefinition.ImageDefinitionTotalVersionsSize)
	s.Equal(res.ImageDefinition.LatestVersion, expectedLatestVersion)
}

func (s *getImageDefinitionTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &GetImageDefinitionRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "Global_Id",
		},
		ImageDefinitionId: 2,
	}

	res, err := s.svc.GetImageDefinition(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}
