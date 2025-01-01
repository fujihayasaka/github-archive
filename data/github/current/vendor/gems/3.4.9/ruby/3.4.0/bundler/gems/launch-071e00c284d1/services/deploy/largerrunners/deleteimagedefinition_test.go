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

type deleteImageDefinitionTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestDeleteImageDefinitionTestSuite(t *testing.T) {
	suite.Run(t, new(deleteImageDefinitionTestSuite))
}

func (s *deleteImageDefinitionTestSuite) SetupTest() {
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

func (s *deleteImageDefinitionTestSuite) TestServiceWillDeleteImageDefinition() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteImageDefinition", mock.Anything, mock.Anything).Return(nil)

	req := &DeleteImageDefinitionRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "G_lobalId",
		},
		ImageDefinitionId: 2,
	}

	res, err := s.svc.DeleteImageDefinition(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *deleteImageDefinitionTestSuite) TestServiceFailsIfImageDefinitionIsReferencedByRunner() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteImageDefinition", mock.Anything, mock.Anything).Return(errs.New("Cannot delete image because it's being referenced by runner"))

	req := &DeleteImageDefinitionRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "G_lobalId",
		},
		ImageDefinitionId: 2,
	}

	res, err := s.svc.DeleteImageDefinition(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *deleteImageDefinitionTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &DeleteImageDefinitionRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "G_lobalId",
		},
		ImageDefinitionId: 2,
	}

	res, err := s.svc.DeleteImageDefinition(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}
