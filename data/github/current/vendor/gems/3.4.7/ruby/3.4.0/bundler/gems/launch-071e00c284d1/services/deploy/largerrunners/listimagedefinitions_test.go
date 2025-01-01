package largerrunners

import (
	"context"
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

type listImageDefinitionsTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListImageDefinitionsTestSuite(t *testing.T) {
	suite.Run(t, new(listImageDefinitionsTestSuite))
}

func (s *listImageDefinitionsTestSuite) SetupTest() {
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

func (s *listMachineSpecsTestSuite) TestServiceWillReturnImageDefinitions() {
	imageDefinitions := mockImageDefinitions()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListImageDefinitions", mock.Anything, mock.Anything).Return(imageDefinitions, nil)

	req := &ListImageDefinitionsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListImageDefinitions(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.ImageDefinitions, len(imageDefinitions))
}

func (s *listImageDefinitionsTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListImageDefinitionsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListImageDefinitions(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockImageDefinitions() []*azp.ImageDefinition {
	latestVersion := "1.0.0"
	return []*azp.ImageDefinition{
		{
			ID:                               1,
			Name:                             "1",
			OsType:                           "Linux",
			ImageDefinitionState:             "Provisioning",
			ImageDefinitionVersionCount:      3,
			ImageDefinitionTotalVersionsSize: 30,
			ImageDefinitionLatestVersion:     &latestVersion,
		},
		{
			ID:                               2,
			Name:                             "2",
			OsType:                           "Windows",
			ImageDefinitionState:             "Ready",
			ImageDefinitionVersionCount:      3,
			ImageDefinitionTotalVersionsSize: 30,
			ImageDefinitionLatestVersion:     nil,
		},
	}
}
