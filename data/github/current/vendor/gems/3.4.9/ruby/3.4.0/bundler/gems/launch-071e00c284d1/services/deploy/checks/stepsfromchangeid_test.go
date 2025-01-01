package checks

import (
	"context"
	"testing"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type stepsFromChangeIDTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestStepsFromChangeIDTestSuite(t *testing.T) {
	suite.Run(t, new(stepsFromChangeIDTestSuite))
}

func (s *stepsFromChangeIDTestSuite) SetupTest() {
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

func (s *stepsFromChangeIDTestSuite) TestStepsFromChangeIDWillReturnAllSteps() {
	expectedActionsSteps := mockActionsSteps()
	expectedCheckSteps := mockCheckSteps()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("StepsFromChangeID", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(expectedActionsSteps, nil)

	repoID := pbtypes.Identity{
		GlobalId: "46704D16-FDBA-45DC-8387-CFDC8B36D120",
	}
	req := &StepsFromChangeIDRequest{
		ChangeId:     0,
		RepositoryId: &repoID,
		JobId:        "75CA465A-E9F0-4F66-8E1D-3ACAF92866B3",
		PlanId:       "60133805-0B02-48C5-9F34-D56512F42DAC",
	}

	res, err := s.svc.StepsFromChangeID(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.Steps, len(expectedCheckSteps))
	s.Equal(expectedCheckSteps, res.Steps)
}

func (s *stepsFromChangeIDTestSuite) TestStepsFromChangeIDFailsWithInvalidRepoID() {
	repoID := pbtypes.Identity{
		GlobalId: "",
	}
	req := &StepsFromChangeIDRequest{
		ChangeId:     0,
		RepositoryId: &repoID,
		JobId:        "75CA465A-E9F0-4F66-8E1D-3ACAF92866B3",
		PlanId:       "60133805-0B02-48C5-9F34-D56512F42DAC",
	}

	res, err := s.svc.StepsFromChangeID(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("repo id cannot be nil"))
}

func (s *stepsFromChangeIDTestSuite) TestStepsFromChangeIDFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("uh oh!"))

	repoID := pbtypes.Identity{
		GlobalId: "46704D16-FDBA-45DC-8387-CFDC8B36D120",
	}
	req := &StepsFromChangeIDRequest{
		ChangeId:     0,
		RepositoryId: &repoID,
		JobId:        "75CA465A-E9F0-4F66-8E1D-3ACAF92866B3",
		PlanId:       "60133805-0B02-48C5-9F34-D56512F42DAC",
	}

	res, err := s.svc.StepsFromChangeID(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: uh oh!"))
	s.arr.AssertExpectations(s.T())
}

func (s *stepsFromChangeIDTestSuite) TestStepsFromChangeIDFailsWithInternalError() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("StepsFromChangeID", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, errs.New("oh no!"))

	repoID := pbtypes.Identity{
		GlobalId: "46704D16-FDBA-45DC-8387-CFDC8B36D120",
	}
	req := &StepsFromChangeIDRequest{
		ChangeId:     0,
		RepositoryId: &repoID,
		JobId:        "75CA465A-E9F0-4F66-8E1D-3ACAF92866B3",
		PlanId:       "60133805-0B02-48C5-9F34-D56512F42DAC",
	}

	res, err := s.svc.StepsFromChangeID(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *stepsFromChangeIDTestSuite) TestStepsFromChangeIDForRunWillReturnAllJobsWithSteps() {
	expectedActionsJobSteps := mockActionsJobSteps()
	expectedCheckJobSteps := mockCheckJobSteps()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("StepsFromChangeIDForRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(expectedActionsJobSteps, nil)

	repoID := pbtypes.Identity{
		GlobalId: "46704D16-FDBA-45DC-8387-CFDC8B36D120",
	}

	req := &StepsFromChangeIDForRunRequest{
		ChangeId:     0,
		RepositoryId: &repoID,
		PlanId:       "60133805-0B02-48C5-9F34-D56512F42DAC",
	}

	res, err := s.svc.StepsFromChangeIDForRun(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Len(res.JobSteps, len(expectedCheckJobSteps))
}

func (s *stepsFromChangeIDTestSuite) TestStepsFromChangeIDForRunFailsWithInvalidRepoID() {
	repoID := pbtypes.Identity{
		GlobalId: "",
	}
	req := &StepsFromChangeIDForRunRequest{
		ChangeId:     0,
		RepositoryId: &repoID,
		PlanId:       "60133805-0B02-48C5-9F34-D56512F42DAC",
	}

	res, err := s.svc.StepsFromChangeIDForRun(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("repo id cannot be nil"))
}

func (s *stepsFromChangeIDTestSuite) TestStepsFromChangeIDForRunFailsWithInternalError() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("StepsFromChangeIDForRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, errs.New("oh no!"))

	repoID := pbtypes.Identity{
		GlobalId: "46704D16-FDBA-45DC-8387-CFDC8B36D120",
	}
	req := &StepsFromChangeIDForRunRequest{
		ChangeId:     0,
		RepositoryId: &repoID,
		PlanId:       "60133805-0B02-48C5-9F34-D56512F42DAC",
	}

	res, err := s.svc.StepsFromChangeIDForRun(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}
