package selfhostedrunners

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	errs "github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type deleteRunnerTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestDeleteRunnersTestSuite(t *testing.T) {
	suite.Run(t, new(deleteRunnerTestSuite))
}

func (s *deleteRunnerTestSuite) SetupTest() {
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

func (s *deleteRunnerTestSuite) TestServiceWillDeleteRunner() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteRunner", mock.Anything, int64(1)).Return(nil)

	req := &DeleteRunnerRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		RunnerId: int64(1),
	}

	res, err := s.svc.DeleteRunner(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.Status, "deleted")
}

func (s *deleteRunnerTestSuite) TestServiceFailsWithInvalidGlobalID() {

	req := &DeleteRunnerRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "",
		},
		RunnerId: 1,
	}

	res, err := s.svc.DeleteRunner(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("repository id cannot be nil"))
}

func (s *deleteRunnerTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &DeleteRunnerRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		RunnerId: 1,
	}

	res, err := s.svc.DeleteRunner(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *deleteRunnerTestSuite) TestServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("DeleteRunner", mock.Anything, int64(1)).Return(errs.New("error!"))

	req := &DeleteRunnerRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		RunnerId: 1,
	}

	res, err := s.svc.DeleteRunner(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}
