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

type getRunnerTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
	jr  *deployer.MockJobsRepository
}

func TestGetRunnerTestSuite(t *testing.T) {
	suite.Run(t, new(getRunnerTestSuite))
}

func (s *getRunnerTestSuite) SetupTest() {
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

func (s *getRunnerTestSuite) TestCanHandleNilRunner() {
	expectedRunner := &azp.RunnerV2{
		ID:   1,
		Name: "runner 1",
		Labels: []*azp.Label{
			{
				ID:   1,
				Name: "windows",
				Type: "system",
			},
			{
				ID:   2,
				Name: "x86",
				Type: "system",
			},
		},
		Status: "online",
		AssignedRequest: &azp.AssignedRequest{
			JobName:          "job 1",
			CheckRunGlobalID: "CR_KgD1b3RvYmU6OTQwNjQwMjI",
		},
		CurrentParallelism: 1,
	}
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunner", mock.Anything, int64(1)).Return(expectedRunner, nil)

	s.jr.On("GetWorkflowJobFromJobID", mock.Anything, mock.Anything, mock.Anything).Return(nil, nil)

	req := &GetRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		RunnerId: int64(1),
	}

	res, err := s.svc.GetRunner(context.Background(), req)
	actualRunner := res.Runner
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("runner 1", actualRunner.GetName())
	s.Equal("windows", actualRunner.GetOs())
	s.Equal("x86", actualRunner.GetArch())
	s.Equal("online", actualRunner.GetStatus())
	s.Equal("windows", actualRunner.GetLabels()[0].GetName())
	s.Equal("job 1", actualRunner.GetAssignedRequest().GetJobName())
	s.Equal("CR_KgD1b3RvYmU6OTQwNjQwMjI", actualRunner.GetAssignedRequest().GetCheckRunId())
	s.Equal(int64(1), actualRunner.GetCurrentParallelism())
}

func (s *getRunnerTestSuite) TestRunnerWithNoSystemLabels() {
	expectedRunner := &azp.RunnerV2{
		ID:     1,
		Name:   "runner 1",
		Labels: []*azp.Label{},
		Status: "online",
		AssignedRequest: &azp.AssignedRequest{
			JobName:          "job 1",
			CheckRunGlobalID: "CR_KgD1b3RvYmU6OTQwNjQwMjI",
		},
		CurrentParallelism: 1,
		OperatingSystem:    "test OS",
	}
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunner", mock.Anything, int64(1)).Return(expectedRunner, nil)
	s.jr.On("GetWorkflowJobFromJobID", mock.Anything, mock.Anything, mock.Anything).Return(nil, nil)

	req := &GetRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		RunnerId: int64(1),
	}

	res, err := s.svc.GetRunner(context.Background(), req)
	actualRunner := res.Runner
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("runner 1", actualRunner.GetName())
	s.Equal("test OS", actualRunner.GetOs())
	s.Equal("unknown", actualRunner.GetArch())
	s.Equal("online", actualRunner.GetStatus())
	s.Equal("job 1", actualRunner.GetAssignedRequest().GetJobName())
	s.Equal("CR_KgD1b3RvYmU6OTQwNjQwMjI", actualRunner.GetAssignedRequest().GetCheckRunId())
	s.Equal(int64(1), actualRunner.GetCurrentParallelism())
}

func (s *getRunnerTestSuite) TestRunnerWithNoSystemLabelsAndNoOS() {
	expectedRunner := &azp.RunnerV2{
		ID:     1,
		Name:   "runner 1",
		Labels: []*azp.Label{},
		Status: "online",
		AssignedRequest: &azp.AssignedRequest{
			JobName:          "job 1",
			CheckRunGlobalID: "CR_KgD1b3RvYmU6OTQwNjQwMjI",
		},
		CurrentParallelism: 1,
	}
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunner", mock.Anything, int64(1)).Return(expectedRunner, nil)
	s.jr.On("GetWorkflowJobFromJobID", mock.Anything, mock.Anything, mock.Anything).Return(nil, nil)

	req := &GetRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		RunnerId: int64(1),
	}

	res, err := s.svc.GetRunner(context.Background(), req)
	actualRunner := res.Runner
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("runner 1", actualRunner.GetName())
	s.Equal("unknown", actualRunner.GetOs())
	s.Equal("unknown", actualRunner.GetArch())
	s.Equal("online", actualRunner.GetStatus())
	s.Equal("job 1", actualRunner.GetAssignedRequest().GetJobName())
	s.Equal("CR_KgD1b3RvYmU6OTQwNjQwMjI", actualRunner.GetAssignedRequest().GetCheckRunId())
	s.Equal(int64(1), actualRunner.GetCurrentParallelism())
}

func (s *getRunnerTestSuite) TestServiceWillGetRunner() {
	expectedRunner := &azp.RunnerV2{
		ID:   1,
		Name: "runner 1",
		Labels: []*azp.Label{
			{
				ID:   1,
				Name: "windows",
				Type: "system",
			},
			{
				ID:   2,
				Name: "x86",
				Type: "system",
			},
		},
		Status: "online",
		AssignedRequest: &azp.AssignedRequest{
			JobName:          "job 1",
			CheckRunGlobalID: "CR_KgD1b3RvYmU6OTQwNjQwMjI",
		},
		CurrentParallelism: 1,
	}
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunner", mock.Anything, int64(1)).Return(expectedRunner, nil)

	workflowJob := &deployer.WorkflowJob{
		ID:              1,
		ExternalJobID:   "1",
		WorkflowBuildID: 1,
		CheckRunID:      "1",
	}
	s.jr.On("GetWorkflowJobFromJobID", mock.Anything, mock.Anything, mock.Anything).Return(workflowJob, nil)

	req := &GetRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		RunnerId: int64(1),
	}

	res, err := s.svc.GetRunner(context.Background(), req)
	actualRunner := res.Runner
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("runner 1", actualRunner.GetName())
	s.Equal("windows", actualRunner.GetOs())
	s.Equal("x86", actualRunner.GetArch())
	s.Equal("online", actualRunner.GetStatus())
	s.Equal("windows", actualRunner.GetLabels()[0].GetName())
	s.Equal("job 1", actualRunner.GetAssignedRequest().GetJobName())
	s.Equal("1", actualRunner.GetAssignedRequest().GetCheckRunId())
	s.Equal(int64(1), actualRunner.GetCurrentParallelism())
}

func (s *getRunnerTestSuite) TestServiceFailsWithInvalidGlobalID() {
	req := &GetRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.GetRunner(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *getRunnerTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &GetRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.GetRunner(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *getRunnerTestSuite) TestServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunner", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &GetRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.GetRunner(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *getRunnerTestSuite) TestCanCreateMacOSRunner() {
	expectedRunner := &azp.RunnerV2{
		ID:   1,
		Name: "runner 1",
		Labels: []*azp.Label{
			{
				ID:   1,
				Name: "macOS",
				Type: "system",
			},
			{
				ID:   2,
				Name: "x86",
				Type: "system",
			},
		},
		Status: "online",
		AssignedRequest: &azp.AssignedRequest{
			JobName:          "job 1",
			CheckRunGlobalID: "CR_KgD1b3RvYmU6OTQwNjQwMjI",
		},
		CurrentParallelism: 1,
	}
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunner", mock.Anything, int64(1)).Return(expectedRunner, nil)

	s.jr.On("GetWorkflowJobFromJobID", mock.Anything, mock.Anything, mock.Anything).Return(nil, nil)

	req := &GetRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		RunnerId: int64(1),
	}

	res, err := s.svc.GetRunner(context.Background(), req)
	actualRunner := res.Runner
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("runner 1", actualRunner.GetName())
	s.Equal("macOS", actualRunner.GetOs())
	s.Equal("x86", actualRunner.GetArch())
	s.Equal("online", actualRunner.GetStatus())
	s.Equal("macOS", actualRunner.GetLabels()[0].GetName())
	s.Equal("job 1", actualRunner.GetAssignedRequest().GetJobName())
	s.Equal("CR_KgD1b3RvYmU6OTQwNjQwMjI", actualRunner.GetAssignedRequest().GetCheckRunId())
	s.Equal(int64(1), actualRunner.GetCurrentParallelism())
}
