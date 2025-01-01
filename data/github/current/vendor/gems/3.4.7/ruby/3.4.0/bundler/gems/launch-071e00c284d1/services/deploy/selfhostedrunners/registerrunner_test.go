package selfhostedrunners

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
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type registerRunnerTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestRegisterRunnerTestSuite(t *testing.T) {
	suite.Run(t, new(registerRunnerTestSuite))
}

func (s *registerRunnerTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &deployer.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: s.rcf,
		azpResourceRepo:      s.arr,
		isMultiTenant:        false,
		actorFFChecker: func(context.Context, string, types.GlobalID) bool {
			return true
		},
	}
}

func (s *registerRunnerTestSuite) TestServiceWillReturnProvidedCredentials() {

	cred := s.getMockCredentials()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunnerRegistrationCredentials", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(cred, nil)

	req := &RegisterRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		BillingOwnerId: &pbtypes.Identity{
			GlobalId: "BillingOwnerGlobalId",
		},
	}

	res, err := s.svc.RegisterRunner(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(cred.Data.HostURL, res.GetUrl())
	s.Equal(cred.Scheme, res.GetTokenSchema())
	s.Equal(cred.Data.Token, res.GetToken())
}

func (s *registerRunnerTestSuite) TestServiceFailsWithInvalidGlobalID() {

	req := &RegisterRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.RegisterRunner(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *registerRunnerTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &RegisterRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.RegisterRunner(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *registerRunnerTestSuite) TestServiceFailsWithBadCredentials() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunnerRegistrationCredentials", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &RegisterRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		BillingOwnerId: &pbtypes.Identity{
			GlobalId: "BillingOwnerGlobalId",
		},
	}

	res, err := s.svc.RegisterRunner(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *registerRunnerTestSuite) TestServiceFailsWhenMissingTenantSlug() {
	s.svc.isMultiTenant = true
	req := &RegisterRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}
	res, err := s.svc.RegisterRunner(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("tenant slug cannot be nil for proxima"))
}

func (s *registerRunnerTestSuite) getMockCredentials() *azp.RunnerRegistrationCredentials {
	return &azp.RunnerRegistrationCredentials{
		Scheme: "scheme",
		Data:   &azp.RunnerRegistrationToken{Token: "token", HostURL: "https://www.example.org/register"},
	}
}
