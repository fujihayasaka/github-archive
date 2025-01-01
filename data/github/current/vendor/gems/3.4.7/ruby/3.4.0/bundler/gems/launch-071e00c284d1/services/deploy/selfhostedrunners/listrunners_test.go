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
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type listRunnersTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
	jr  *deployer.MockJobsRepository
}

func TestListRunnersTestSuite(t *testing.T) {
	suite.Run(t, new(listRunnersTestSuite))
}

func (s *listRunnersTestSuite) SetupTest() {
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

func (s *listRunnersTestSuite) TestServiceWillReturnRunnersListV2() {
	expectedRunners := mockRunners()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(expectedRunners, int64(len(expectedRunners)), nil)

	workflowJob := &deployer.WorkflowJob{
		ID:              1,
		ExternalJobID:   "",
		WorkflowBuildID: 1,
		CheckRunID:      "",
	}
	s.jr.On("GetWorkflowJobFromJobID", mock.Anything, mock.Anything, mock.Anything).Return(workflowJob, nil)

	req := &ListRunnersRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListRunnersV2(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Runners, len(expectedRunners))
	s.Equal(MapDetailedAzpRunners(expectedRunners), res.Runners)
}

func (s *listRunnersTestSuite) TestServiceWillReturnRunnersListV2WithAssignedRequests() {
	expectedRunners := mockRunners()
	expectedExternalJobID := expectedRunners[0].AssignedRequest.PlanID + "," + expectedRunners[0].AssignedRequest.JobID
	expectedPoolID := int64(2)
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, expectedPoolID, mock.Anything, mock.Anything).Return(expectedRunners, int64(len(expectedRunners)), nil)

	workflowJobs := make(map[string]string)
	workflowJobs[expectedExternalJobID] = "checkRunID1"
	s.jr.On("GetWorkflowJobsFromJobIds", mock.Anything, []string{expectedExternalJobID}, mock.Anything).Return(workflowJobs, nil)

	req := &ListRunnersRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		IncludeAssignedRequest: true,
		PoolId:                 expectedPoolID,
	}

	res, err := s.svc.ListRunnersV2(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Runners, len(expectedRunners))
	for _, r := range res.Runners {
		if r.AssignedRequest != nil {
			s.Equal(r.AssignedRequest.CheckRunId, workflowJobs[expectedExternalJobID])
		}
	}
}

func (s *listRunnersTestSuite) TestServiceWillReturnRunnersListV2WithAssignedRequestsWithoutWorkflowJobs() {
	expectedRunners := mockRunners()
	expectedExternalJobID := expectedRunners[0].AssignedRequest.PlanID + "," + expectedRunners[0].AssignedRequest.JobID
	expectedPoolID := int64(2)
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, expectedPoolID, mock.Anything, mock.Anything).Return(expectedRunners, int64(len(expectedRunners)), nil)

	// no workflow jobs found
	workflowJobs := make(map[string]string)
	s.jr.On("GetWorkflowJobsFromJobIds", mock.Anything, []string{expectedExternalJobID}, mock.Anything).Return(workflowJobs, nil)

	req := &ListRunnersRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		IncludeAssignedRequest: true,
		PoolId:                 expectedPoolID,
	}

	res, err := s.svc.ListRunnersV2(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Runners, len(expectedRunners))
	for _, r := range res.Runners {
		if r.AssignedRequest != nil {
			s.Equal(r.AssignedRequest.CheckRunId, "CR_1")
		}
	}
}

func (s *listRunnersTestSuite) TestServiceWillPaginateRunnersListV2() {
	expectedRunners := mockRunners()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	workflowJob := &deployer.WorkflowJob{
		ID:              1,
		ExternalJobID:   "",
		WorkflowBuildID: 1,
		CheckRunID:      "",
	}
	s.jr.On("GetWorkflowJobFromJobID", mock.Anything, mock.Anything, mock.Anything).Return(workflowJob, nil)
	s.rrc.On("ListRunnersV2", mock.Anything, int64(1), int64(30), mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(expectedRunners, int64(len(expectedRunners)), nil)

	req := &ListRunnersRequest{
		Page:    1,
		PerPage: 30,
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListRunnersV2(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Runners, len(expectedRunners))
	s.Equal(MapDetailedAzpRunners(expectedRunners), res.Runners)
}

func (s *listRunnersTestSuite) TestServiceFailsWithInvalidGlobalID() {

	req := &ListRunnersRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.ListRunnersV2(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *listRunnersTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &ListRunnersRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListRunnersV2(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *listRunnersTestSuite) TestServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, int64(0), errs.New("error!"))

	req := &ListRunnersRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.ListRunnersV2(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *listRunnersTestSuite) TestServiceWillFilterByRunnerNameOnRunnersListV2() {
	expectedRunners := []*azp.RunnerV2{mockRunners()[0]}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, "runner 1", mock.Anything).Return(expectedRunners, int64(len(expectedRunners)), nil)

	workflowJob := &deployer.WorkflowJob{
		ID:              1,
		ExternalJobID:   "",
		WorkflowBuildID: 1,
		CheckRunID:      "",
	}
	s.jr.On("GetWorkflowJobFromJobID", mock.Anything, mock.Anything, mock.Anything).Return(workflowJob, nil)

	req := &ListRunnersRequest{
		RepositoryId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Name: "runner 1",
	}

	res, err := s.svc.ListRunnersV2(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Runners, len(expectedRunners))
	s.Equal(MapDetailedAzpRunners(expectedRunners), res.Runners)
}
