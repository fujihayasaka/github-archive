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

type listBetaFeaturesTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListBetaFeaturesTestSuite(t *testing.T) {
	suite.Run(t, new(listBetaFeaturesTestSuite))
}

func (s *listBetaFeaturesTestSuite) SetupTest() {
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

func (s *listBetaFeaturesTestSuite) TestServiceWillListBetaFeatures() {
	betaFeatures := mockBetaFeatures()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListBetaFeatures", mock.Anything).Return(betaFeatures, nil)

	req := &ListBetaFeaturesRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListBetaFeatures(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Features, 1)
}

func (s *listBetaFeaturesTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListBetaFeaturesRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListBetaFeatures(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockBetaFeatures() []*azp.BetaFeature {
	return []*azp.BetaFeature{
		{
			Name:            "BetaFeature",
			EnabledForUser:  true,
			EnabledGlobally: false,
		},
	}
}
