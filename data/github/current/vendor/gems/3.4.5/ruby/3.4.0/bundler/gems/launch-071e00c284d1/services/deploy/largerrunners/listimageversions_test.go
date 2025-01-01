package largerrunners

import (
	"context"
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

type listImageVersionsTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListImageVersionsTestSuite(t *testing.T) {
	suite.Run(t, new(listImageVersionsTestSuite))
}

func (s *listImageVersionsTestSuite) SetupTest() {
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

func (s *listMachineSpecsTestSuite) TestServiceWillReturnImageVersions() {
	imageVersions := mockImageVersions()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListImageVersions", mock.Anything, mock.Anything, mock.Anything).Return(imageVersions, nil)

	req := &ListImageVersionsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		ImageDefinitionId: 2,
	}

	res, err := s.svc.ListImageVersions(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.ImageVersions, len(imageVersions))
}

func (s *listImageVersionsTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListImageVersionsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		ImageDefinitionId: 2,
	}

	res, err := s.svc.ListImageVersions(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockImageVersions() []*azp.ImageVersion {
	size := int32(30)
	lastUsedOn := "2024-01-01T00:00:00Z"

	return []*azp.ImageVersion{
		{
			ImageDefinitionID:               2,
			Version:                         "1.0.0",
			ImageVersionState:               "Ready",
			ImageVersionImportFailureReason: "",
			ImageVersionCreatedOn:           time.Now(),
			ImageVersionSize:                &size,
			ImageVersionLastUsedOn:          nil,
		},
		{
			ImageDefinitionID:               2,
			Version:                         "2.0.0",
			ImageVersionState:               "ImportingBlob",
			ImageVersionImportFailureReason: "",
			ImageVersionCreatedOn:           time.Now(),
			ImageVersionSize:                nil,
			ImageVersionLastUsedOn:          &lastUsedOn,
		},
	}
}
