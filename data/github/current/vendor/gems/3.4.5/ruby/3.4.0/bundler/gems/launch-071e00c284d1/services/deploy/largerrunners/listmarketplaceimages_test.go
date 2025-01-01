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

type listMarketplaceImagesTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListMarketplaceImagesTestSuite(t *testing.T) {
	suite.Run(t, new(listMarketplaceImagesTestSuite))
}

func (s *listMarketplaceImagesTestSuite) SetupTest() {
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

func (s *listMarketplaceImagesTestSuite) TestServiceWillReturnMachineSpecs() {
	images := mockMarketplaceImages()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListMarketplaceImages", mock.Anything, mock.Anything).Return(images, nil)

	req := &ListMarketplaceImagesRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListMarketplaceImages(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Images, len(images))
}

func (s *listMarketplaceImagesTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListMarketplaceImagesRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListMarketplaceImages(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockMarketplaceImages() []*azp.Image {
	return []*azp.Image{
		{
			ID:          "Ubuntu18",
			DisplayName: "18.04",
			SizeGB:      10,
			Platform:    "linux-x64",
		},
	}
}
