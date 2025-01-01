package runnerscalesets

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	twirp "github.com/twitchtv/twirp"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type listRunnerScaleSetsTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListRunnerScaleSetsTestSuite(t *testing.T) {
	suite.Run(t, new(listRunnerScaleSetsTestSuite))
}

func (s *listRunnerScaleSetsTestSuite) SetupTest() {
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

func (s *listRunnerScaleSetsTestSuite) TestServiceReturnsScaleSets() {
	scaleSets := []*azp.RunnerScaleSet{
		mockScaleSet(),
		mockScaleSet(),
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnerScaleSets", mock.Anything, mock.Anything).Return(scaleSets, nil)

	req := &ListRunnerScaleSetsRequest{
		OwnerId: &pbtypes.Identity{GlobalId: "Global_Id"},
	}

	res, err := s.svc.ListRunnerScaleSets(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())

	expectedResponse := &ListRunnerScaleSetsResponse{
		RunnerScaleSets: MapAzpRunnerScaleSets(scaleSets),
	}
	s.Equal(expectedResponse, res)
}

func (s *listRunnerScaleSetsTestSuite) TestServiceFailsWithInvalidGlobalID() {
	req := &ListRunnerScaleSetsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.ListRunnerScaleSets(context.Background(), req)
	s.Nil(res)

	st, ok := err.(twirp.Error)
	s.True(ok)
	s.Equal(twirp.InvalidArgument, st.Code())
	s.Equal("global id cannot be empty", st.Msg())
}
