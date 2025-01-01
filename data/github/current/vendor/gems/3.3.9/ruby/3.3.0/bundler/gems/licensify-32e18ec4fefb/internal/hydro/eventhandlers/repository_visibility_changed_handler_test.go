package eventhandlers_test

import (
	"context"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	hydroRepositoriesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/repositories/v1"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/monolith"
	repositoriesv1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type repositoryVisibilityChangedTestSuite struct {
	suite.Suite
	mockDB             *mocks.MockDBReadWriter
	mockAqueductClient *mocks.MockAqueductClient
	mockMonolithAPI    *mocks.MockMonolithAPI
	handler            *eventhandlers.EventHandler
	cfg                *config.Config
}

func (s *repositoryVisibilityChangedTestSuite) SetupTest() {
	s.cfg, _ = config.Load()
	statter := s.cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	s.mockDB = &mocks.MockDBReadWriter{}
	s.mockAqueductClient = &mocks.MockAqueductClient{}
	s.mockMonolithAPI = &mocks.MockMonolithAPI{}
	monolithClient := &monolith.Client{RepositoriesAPI: s.mockMonolithAPI}
	jobby := &jobs.Jobby{Cfg: s.cfg, AqueductClient: s.mockAqueductClient}
	eventHandler, _ := eventhandlers.NewEventHandler(&mocks.MockDBReadWriter{}, jobby, monolithClient, statter, tracer)
	s.handler = eventHandler
}

func (s *repositoryVisibilityChangedTestSuite) TestHandleEnvelopeSkipsMissingRepositoryID() {
	logger := log.NewNullLogger()
	msg := stubs.NewRepositoryVisibilityChangedHydroMsg()
	msg.RepositoryId = 0

	skip, err := s.handler.HandleRepoVisibilityChanged(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryVisibilityChangedTestSuite) TestHandleEnvelopeSkipsMissingCustomerID() {
	logger := log.NewNullLogger()
	msg := stubs.NewRepositoryVisibilityChangedHydroMsg()

	request := &repositoriesv1.GetRepositoryInformationRequest{
		Id: uint64(msg.RepositoryId),
	}
	response := &repositoriesv1.GetRepositoryInformationResponse{
		Repository: &repositoriesv1.Repository{},
	}
	s.mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	_, err := s.handler.HandleRepoVisibilityChanged(context.Background(), logger, msg)
	s.Require().NoError(err.Err)
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryVisibilityChangedTestSuite) TestHandleEnvelopeSkipsInactiveRepos() {
	logger := log.NewNullLogger()
	msg := stubs.NewRepositoryVisibilityChangedHydroMsg()

	request := &repositoriesv1.GetRepositoryInformationRequest{
		Id: uint64(msg.RepositoryId),
	}
	response := &repositoriesv1.GetRepositoryInformationResponse{
		Repository: &repositoriesv1.Repository{
			OwnerCustomerId: int64(stubs.NewRandomID()),
			IsActive:        false,
		},
	}

	s.mockMonolithAPI.On(
		"GetRepositoryInformation",
		mock.Anything,
		request,
	).Return(response, nil).Once()

	_, err := s.handler.HandleRepoVisibilityChanged(context.Background(), logger, msg)
	s.Require().NoError(err.Err)
	s.mockAqueductClient.AssertNotCalled(s.T(), "Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryVisibilityChangedTestSuite) TestHandlerQueuesDeleteJobOnPublicVisibility() {
	jobID := "jobID-1234"
	logger := log.NewNullLogger()

	msg := stubs.NewRepositoryVisibilityChangedHydroMsg()
	msg.NewVisibility = hydroRepositoriesv1.VisibilityChanged_PUBLIC

	request := &repositoriesv1.GetRepositoryInformationRequest{
		Id: uint64(msg.RepositoryId),
	}
	response := &repositoriesv1.GetRepositoryInformationResponse{
		Repository: &repositoriesv1.Repository{
			OwnerCustomerId: int64(stubs.NewRandomID()),
			IsActive:        false,
		},
	}

	s.mockMonolithAPI.On(
		"GetRepositoryInformation",
		mock.Anything,
		request,
	).Return(response, nil).Once()
	s.mockAqueductClient.On(
		"Send",
		mock.Anything,
		mock.MatchedBy(func(j aqueduct.Job) bool {
			return j.App == s.cfg.AqueductApp &&
				j.Queue == queues.QueueDeleteEnablements &&
				j.Headers[jobs.JobNameHeader] == jobs.JobNameDeleteEnablements
		}),
		mock.AnythingOfType("[]aqueduct.SendOption"),
	).Return(jobID, nil).Times(1)

	_, err := s.handler.HandleRepoVisibilityChanged(context.Background(), logger, msg)
	s.Require().NoError(err.Err)
}

func (s *repositoryVisibilityChangedTestSuite) TestHandlerQueuesCreateRepositoryCollaboratorsJobOnConsumableVisibilities() {
	jobID := "jobID-1234"
	logger := log.NewNullLogger()

	msg := stubs.NewRepositoryVisibilityChangedHydroMsg()

	request := &repositoriesv1.GetRepositoryInformationRequest{
		Id: uint64(msg.RepositoryId),
	}
	response := &repositoriesv1.GetRepositoryInformationResponse{
		Repository: &repositoriesv1.Repository{
			OwnerCustomerId: int64(stubs.NewRandomID()),
			IsActive:        false,
		},
	}

	s.mockMonolithAPI.On(
		"GetRepositoryInformation",
		mock.Anything,
		request,
	).Return(response, nil).Once()
	s.mockAqueductClient.On(
		"Send",
		mock.Anything,
		mock.MatchedBy(func(j aqueduct.Job) bool {
			return j.App == s.cfg.AqueductApp &&
				j.Queue == queues.QueueCreateRepositoryCollaborators &&
				j.Headers[jobs.JobNameHeader] == jobs.JobNameCreateRepositoryCollaborators
		}),
		mock.AnythingOfType("[]aqueduct.SendOption"),
	).Return(jobID, nil).Times(1)

	_, err := s.handler.HandleRepoVisibilityChanged(context.Background(), logger, msg)
	s.Require().NoError(err.Err)
}

func TestRepositoryVisibilityChangedHandlerSuite(t *testing.T) {
	suite.Run(t, new(repositoryVisibilityChangedTestSuite))
}
