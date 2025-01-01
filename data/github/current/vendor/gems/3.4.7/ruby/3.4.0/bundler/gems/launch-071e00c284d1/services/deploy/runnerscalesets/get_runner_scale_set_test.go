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

type getRunnerScaleSetTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestGetRunnerScaleSetTestSuite(t *testing.T) {
	suite.Run(t, new(getRunnerScaleSetTestSuite))
}

func (s *getRunnerScaleSetTestSuite) SetupTest() {
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

func (s *getRunnerScaleSetTestSuite) TestServiceReturnsScaleSet() {
	scaleSet := mockScaleSet()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunnerScaleSet", mock.Anything, mock.Anything).Return(scaleSet, nil)

	req := &GetRunnerScaleSetRequest{
		OwnerId:    &pbtypes.Identity{GlobalId: "Global_Id"},
		ScaleSetId: 1,
	}

	res, err := s.svc.GetRunnerScaleSet(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())

	expectedResponse := &GetRunnerScaleSetResponse{
		RunnerScaleSet: ConvertDetailedRunnerScaleSetFromAzp(scaleSet),
	}
	s.Equal(expectedResponse, res)
}

func (s *getRunnerScaleSetTestSuite) TestScaleSetNotFound() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)

	// azp returns a nil a scaleset (404)
	s.rrc.On("GetRunnerScaleSet", mock.Anything, mock.Anything).Return(nil, nil)

	req := &GetRunnerScaleSetRequest{
		OwnerId:    &pbtypes.Identity{GlobalId: "Global_Id"},
		ScaleSetId: 1,
	}

	res, err := s.svc.GetRunnerScaleSet(context.Background(), req)
	s.Nil(res)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())

	st, ok := err.(twirp.Error)
	s.True(ok)
	s.Equal(twirp.NotFound, st.Code())
	s.Equal("no runner scale set found for id: 1", st.Msg())
}

func (s *getRunnerScaleSetTestSuite) TestServiceFailsWithInvalidGlobalID() {
	req := &GetRunnerScaleSetRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
		ScaleSetId: 1,
	}

	res, err := s.svc.GetRunnerScaleSet(context.Background(), req)
	s.Nil(res)

	st, ok := err.(twirp.Error)
	s.True(ok)
	s.Equal(twirp.InvalidArgument, st.Code())
	s.Equal("global id cannot be empty", st.Msg())
}

func (s *getRunnerScaleSetTestSuite) TestServiceFailsWithoutScaleSetID() {
	req := &GetRunnerScaleSetRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "Global_Id",
		},
	}

	res, err := s.svc.GetRunnerScaleSet(context.Background(), req)
	s.Nil(res)

	st, ok := err.(twirp.Error)
	s.True(ok)
	s.Equal(twirp.InvalidArgument, st.Code())
	s.Equal("scale set id must be provided", st.Msg())
}

func mockScaleSet() *azp.RunnerScaleSet {
	return &azp.RunnerScaleSet{
		ID:              1,
		Name:            "scale set",
		RunnerGroupID:   1,
		RunnerGroupName: "runnerGroupName",
		Status:          "online",
		Statistics: azp.RunnerScaleSetStatistics{
			TotalAvailableJobs:     1,
			TotalAcquiredJobs:      2,
			TotalAssignedJobs:      3,
			TotalRunningJobs:       4,
			TotalRegisteredRunners: 5,
			TotalBusyRunners:       6,
			TotalIdleRunners:       7,
		},
		Labels: []*azp.Label{
			{
				ID:   1,
				Name: "scale set",
			},
		},
	}
}
