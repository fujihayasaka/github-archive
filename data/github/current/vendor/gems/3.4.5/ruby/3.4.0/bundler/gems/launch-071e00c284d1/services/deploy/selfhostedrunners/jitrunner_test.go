package selfhostedrunners

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
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type generateJITRunnerTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
	jr  *deployer.MockJobsRepository
}

func TestGenerateJITRunnerTestSuite(t *testing.T) {
	suite.Run(t, new(generateJITRunnerTestSuite))
}

func (s *generateJITRunnerTestSuite) SetupTest() {
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

func (s *generateJITRunnerTestSuite) TestGenerateJitRunnerConfig() {
	expectedRunner := &azp.RunnerV2{
		ID:   1,
		Name: "Runner-1",
		Labels: []*azp.Label{
			{
				ID:   1,
				Name: "self-hosted",
				Type: "system",
			},
		},
	}
	expectedConfig := "abc123"
	expectedResponse := &azp.JITRunnerConfig{
		Runner:           expectedRunner,
		EncodedJITConfig: expectedConfig,
	}

	req := &GenerateJitRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		Name:          "Runner-1",
		RunnerGroupId: 1,
		Labels:        []string{"self-hosted"},
		WorkFolder:    "_work",
		GithubUrl:     "https://github.com/bbq-beets",
	}

	settings := &azp.JITRunnerSettings{
		Name:          "Runner-1",
		RunnerGroupID: 1,
		Labels:        []string{"self-hosted"},
		WorkFolder:    "_work",
		GithubURL:     "https://github.com/bbq-beets",
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GenerateJITRunnerConfig", mock.Anything, settings).Return(expectedResponse, nil)

	res, err := s.svc.GenerateJitRunnerConfig(context.Background(), req)
	actualRunner := res.Runner
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal("Runner-1", actualRunner.GetName())
}

func (s *generateJITRunnerTestSuite) TestServiceFailsWithInvalidGlobalID() {
	req := &GenerateJitRunnerRequest{}

	res, err := s.svc.GenerateJitRunnerConfig(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *generateJITRunnerTestSuite) TestServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &GenerateJitRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.GenerateJitRunnerConfig(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *generateJITRunnerTestSuite) TestServiceFailsWithBadCredentials() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GenerateJITRunnerConfig", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &GenerateJitRunnerRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.GenerateJitRunnerConfig(context.Background(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}
