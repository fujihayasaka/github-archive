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

type updateRunnersTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestBulkUpdateRunnerLabelsTestSuite(t *testing.T) {
	suite.Run(t, new(updateRunnersTestSuite))
}

func (s *updateRunnersTestSuite) SetupTest() {
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

func (s *updateRunnersTestSuite) TestServiceWillBulkUpdateRunnerLabels() {
	runners := mockRunners()
	expectedOperations := []*azp.RunnerOp{
		{
			Op:    "add",
			Path:  "/1/labels",
			Value: []int64{1},
		},
		{
			Op:    "remove",
			Path:  "/2/labels",
			Value: []int64{2, 3},
		},
		{
			Op:    "add",
			Path:  "/3/labels",
			Value: []int64{4},
		},
		{
			Op:    "remove",
			Path:  "/3/labels",
			Value: []int64{5, 6},
		},
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateRunners", mock.Anything, expectedOperations).Return(runners, nil)

	req := &BulkUpdateRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkUpdateRunnerLabelsRequest_LabelOps{
			{RunnerId: 1, Additions: []int64{1}},
			{RunnerId: 2, Removals: []int64{2, 3}},
			{RunnerId: 3, Additions: []int64{4}, Removals: []int64{5, 6}},
		},
	}

	res, err := s.svc.BulkUpdateRunnerLabels(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Runners, len(runners))
	s.Equal(runners, mapToAzpRunners(res.Runners))
}

func (s *updateRunnersTestSuite) TestServiceFailsWithInvalidGlobalID() {

	req := &BulkUpdateRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
		Updates: []*BulkUpdateRunnerLabelsRequest_LabelOps{},
	}

	res, err := s.svc.BulkUpdateRunnerLabels(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *updateRunnersTestSuite) TestServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &BulkUpdateRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkUpdateRunnerLabelsRequest_LabelOps{},
	}

	res, err := s.svc.BulkUpdateRunnerLabels(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *updateRunnersTestSuite) TestServiceFailsWithBadCredentials() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateRunners", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &BulkUpdateRunnerLabelsRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Updates: []*BulkUpdateRunnerLabelsRequest_LabelOps{},
	}

	res, err := s.svc.BulkUpdateRunnerLabels(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}
