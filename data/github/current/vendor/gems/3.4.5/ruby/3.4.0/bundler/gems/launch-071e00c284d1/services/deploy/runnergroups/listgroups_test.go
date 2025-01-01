package runnergroups

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

type listGroupsTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestListGroupsTestSuite(t *testing.T) {
	suite.Run(t, new(listGroupsTestSuite))
}

func (s *listGroupsTestSuite) SetupTest() {
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

func (s *listGroupsTestSuite) TestServiceWillReturnRunnerGroups() {
	runnerGroups := mockRunnerGroups()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListGroups", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroups, nil)

	req := &ListGroupsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "GlobalIdPlanOwner",
		},
	}

	res, err := s.svc.ListGroups(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.RunnerGroups, len(runnerGroups))
}

func (s *listGroupsTestSuite) TestServiceFailsWithInvalidGlobalID() {

	req := &ListGroupsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "GlobalIdPlanOwner",
		},
	}

	res, err := s.svc.ListGroups(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *listGroupsTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListGroupsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "GlobalIdPlanOwner",
		},
	}

	res, err := s.svc.ListGroups(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func mockRunnerGroups() []*azp.RunnerGroup {
	return []*azp.RunnerGroup{
		{
			ID:           1,
			Name:         "MazeGroup",
			OwningTenant: "ownerId",
			Visibility: azp.Visibility{
				VisibilityType: "all",
			},
			RunnerScaleSets: []*azp.RunnerScaleSet{
				{
					ID:   1,
					Name: "MazeScaleSet",
					Statistics: azp.RunnerScaleSetStatistics{
						TotalAssignedJobs: 1,
					},
					Labels: []*azp.Label{
						{
							ID:   1,
							Name: "MazeScaleSet",
						},
					},
				},
				{
					ID:   2,
					Name: "GrazeScaleSet",
					Statistics: azp.RunnerScaleSetStatistics{
						TotalAssignedJobs: 1,
					},
					Labels: []*azp.Label{
						{
							ID:   1,
							Name: "GrazieScaleSet",
						},
					},
				},
			},
		},
	}
}
