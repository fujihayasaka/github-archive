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

type listAgentsTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
	jr  *deployer.MockJobsRepository
}

func TestListAgentsTestSuite(t *testing.T) {
	suite.Run(t, new(listAgentsTestSuite))
}

func (s *listAgentsTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &deployer.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.jr = &deployer.MockJobsRepository{}
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: s.rcf,
		azpResourceRepo:      s.arr,
		jobsRepository:       s.jr,
	}
}

func (s *listAgentsTestSuite) TestServiceWillReturnAgents() {
	poolAgents := mockPoolAgents()

	const poolID int64 = 1
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListPoolAgents", mock.Anything, poolID).Return(poolAgents, nil)
	s.jr.On("GetWorkflowJobsFromJobIds", mock.Anything, mock.Anything).Return(make(map[string]string), nil)

	req := &ListPoolAgentsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PoolId: poolID,
	}

	res, err := s.svc.ListPoolAgents(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Agents, len(poolAgents))
}

func (s *listAgentsTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListPoolsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListPools(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockPoolAgents() []*azp.RunnerV2 {
	return []*azp.RunnerV2{
		{
			ID:            1,
			Name:          "MyAgent",
			Status:        "offline",
			RunnerGroupID: 1,
		},
	}
}
