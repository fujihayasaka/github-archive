package selfhostedrunners

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	errs "github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type createLabelTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestCreateLabelTestSuite(t *testing.T) {
	suite.Run(t, new(createLabelTestSuite))
}

func (s *createLabelTestSuite) SetupTest() {
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

func (s *createLabelTestSuite) TestServiceWillCreateLabel() {
	expectedLabel := &azp.Label{
		ID:   1,
		Name: "label 1",
		Type: "user",
	}
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("CreateLabel", mock.Anything, mock.Anything).Return(expectedLabel, nil)

	req := &CreateLabelRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Name: "label 1",
	}

	res, err := s.svc.CreateLabel(context.Background(), req)
	actualLabel := res.Label
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("label 1", actualLabel.GetName())
	s.Equal("user", actualLabel.GetType())
}

func (s *createLabelTestSuite) TestServiceFailsWithInvalidGlobalID() {
	req := &CreateLabelRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.CreateLabel(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *createLabelTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &CreateLabelRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.CreateLabel(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *createLabelTestSuite) TestServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("CreateLabel", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &CreateLabelRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.CreateLabel(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}
