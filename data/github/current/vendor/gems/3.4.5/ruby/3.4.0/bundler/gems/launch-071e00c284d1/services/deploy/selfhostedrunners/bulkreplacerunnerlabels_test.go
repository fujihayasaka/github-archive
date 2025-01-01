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

type replaceLabelsTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestBulkReplaceRunnerLabelsTestSuite(t *testing.T) {
	suite.Run(t, new(replaceLabelsTestSuite))
}

func (s *replaceLabelsTestSuite) SetupTest() {
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

func (s *replaceLabelsTestSuite) TestServiceWillBulkReplaceRunnerLabels() {
	runners := mockRunners()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runners, int64(0), nil)
	s.rrc.On("UpdateRunners", mock.Anything, mock.Anything).Return(runners, nil)

	req := &BulkReplaceRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkReplaceRunnerLabelsRequest_RunnerLabelsUpdate{
			{RunnerId: 1, LabelIds: []int64{1}},
			{RunnerId: 2, LabelIds: []int64{2, 3}},
			{RunnerId: 3, LabelIds: []int64{4, 5, 6}},
		},
	}

	res, err := s.svc.BulkReplaceRunnerLabels(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Runners, len(runners))
	s.Equal(runners, mapToAzpRunners(res.Runners))
}

func (s *replaceLabelsTestSuite) TestServiceCorrectlySendsRemoveOperations() {
	runners := mockRunners()

	expectedRemoveOperation := &azp.RunnerOp{
		Op:    "remove",
		Path:  "/3/labels",
		Value: []int64{2},
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runners, int64(0), nil)
	s.rrc.On("UpdateRunners", mock.Anything, []*azp.RunnerOp{expectedRemoveOperation}).Return(runners, nil)

	req := &BulkReplaceRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkReplaceRunnerLabelsRequest_RunnerLabelsUpdate{
			{RunnerId: 1, LabelIds: []int64{1, 2}},
			{RunnerId: 2, LabelIds: []int64{1, 2}},
			{RunnerId: 3, LabelIds: []int64{1}}, // We are removing label 2 from runner 3
		},
	}

	res, err := s.svc.BulkReplaceRunnerLabels(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *replaceLabelsTestSuite) TestServiceCorrectlySendsAddOperations() {
	runners := mockRunners()

	expectedAddOperation := &azp.RunnerOp{
		Op:    "add",
		Path:  "/3/labels",
		Value: []int64{3, 4},
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runners, int64(0), nil)
	s.rrc.On("UpdateRunners", mock.Anything, []*azp.RunnerOp{expectedAddOperation}).Return(runners, nil)

	req := &BulkReplaceRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkReplaceRunnerLabelsRequest_RunnerLabelsUpdate{
			{RunnerId: 1, LabelIds: []int64{1, 2}},
			{RunnerId: 2, LabelIds: []int64{1, 2}},
			{RunnerId: 3, LabelIds: []int64{1, 2, 3, 4}}, // We are adding label 3 and 4 to runner 3
		},
	}

	res, err := s.svc.BulkReplaceRunnerLabels(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *replaceLabelsTestSuite) TestServiceFailsWithInvalidGlobalID() {

	req := &BulkReplaceRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
		Updates: []*BulkReplaceRunnerLabelsRequest_RunnerLabelsUpdate{},
	}

	res, err := s.svc.BulkReplaceRunnerLabels(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *replaceLabelsTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &BulkReplaceRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkReplaceRunnerLabelsRequest_RunnerLabelsUpdate{},
	}

	res, err := s.svc.BulkReplaceRunnerLabels(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *replaceLabelsTestSuite) TestServiceFailsWithBadCredentials() {
	runners := mockRunners()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateRunners", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))
	s.rrc.On("ListRunnersV2", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runners, int64(0), nil)

	req := &BulkReplaceRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkReplaceRunnerLabelsRequest_RunnerLabelsUpdate{},
	}

	res, err := s.svc.BulkReplaceRunnerLabels(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *replaceLabelsTestSuite) TestServiceWillBulkReplaceRunnerLabelsForSingleRunner() {
	runner := &azp.RunnerV2{
		ID:   1,
		Name: "runner 1",
		Labels: []*azp.Label{
			{
				ID:   1,
				Name: "windows",
				Type: "system",
			},
		},
		Status: "online",
		AssignedRequest: &azp.AssignedRequest{
			JobName:          "job 1",
			PlanID:           "PlanID1",
			JobID:            "JobID1",
			CheckRunGlobalID: "CR_1",
		},
		CurrentParallelism: 1,
	}
	runners := []*azp.RunnerV2{runner}

	expectedAddOperation := &azp.RunnerOp{
		Op:    "add",
		Path:  "/1/labels",
		Value: []int64{2},
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetRunner", mock.Anything, int64(1)).Return(runner, nil)
	s.rrc.On("UpdateRunners", mock.Anything, []*azp.RunnerOp{expectedAddOperation}).Return(runners, nil)

	req := &BulkReplaceRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkReplaceRunnerLabelsRequest_RunnerLabelsUpdate{
			{RunnerId: 1, LabelIds: []int64{1, 2}},
		},
	}

	res, err := s.svc.BulkReplaceRunnerLabels(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Runners, len(runners))
	s.Equal(runners, mapToAzpRunners(res.Runners))
}
